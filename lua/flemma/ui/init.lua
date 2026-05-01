--- UI module for Flemma plugin
--- Handles visual presentation: rulers, progress indicators, and folding
---@class flemma.UI
local M = {}

local config_facade = require("flemma.config")
local log = require("flemma.logging")
local state = require("flemma.state")
local preview = require("flemma.ui.preview")
local folding = require("flemma.ui.folding")
local roles = require("flemma.utilities.roles")
local bridge = require("flemma.bridge")
local migration = require("flemma.migration")
local parser = require("flemma.parser")
local processor = require("flemma.processor")
local ast = require("flemma.ast")
local turns = require("flemma.ui.turns")
local activity = require("flemma.ui.activity")
local indicators = require("flemma.ui.indicators")
local str = require("flemma.utilities.string")

local PRIORITY = {
  LINE_HIGHLIGHT = 50,
  THINKING_BLOCK = 100,
  CURSORLINE = 125,
  THINKING_TAG = 200,
}

local ns_id = vim.api.nvim_create_namespace("flemma")
local line_hl_ns = vim.api.nvim_create_namespace("flemma_line_highlights")
local cursorline_ns = vim.api.nvim_create_namespace("flemma_cursorline")
local thinking_ns = vim.api.nvim_create_namespace("flemma_thinking_tags")
local tool_preview_ns = vim.api.nvim_create_namespace("flemma_tool_preview")

---Add rulers merged with role marker lines
---@param bufnr integer
---@param doc flemma.ast.DocumentNode
function M.add_rulers(bufnr, doc)
  -- Clear existing extmarks
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  local current_config = config_facade.get(bufnr)
  local ruler_config = current_config.ruler
  if ruler_config.enabled == false then
    return
  end

  -- Get the window displaying this buffer to calculate correct ruler width
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return
  end

  local win_width = vim.api.nvim_win_get_width(winid)

  local progress_line = state.get_buffer_state(bufnr).progress_last_line

  for _, msg in ipairs(doc.messages) do
    local line_idx = msg.position.start_line - 1
    if line_idx >= 0 and line_idx < vim.api.nvim_buf_line_count(bufnr) then
      -- Use the AST role directly — only recognized roles (You, System, Assistant) get rulers
      local role_name = msg.role
      local colon_col = 1 + #role_name -- position of ':' in @Role:

      -- Replace @ with ruler char
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_idx, 0, {
        virt_text = { { ruler_config.char, "FlemmaRuler" } },
        virt_text_pos = "overlay",
        hl_mode = "combine",
      })

      -- Insert a non-editable space between ruler char and the role name
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_idx, 1, {
        virt_text = { { " ", "FlemmaRuler" } },
        virt_text_pos = "inline",
        hl_mode = "combine",
      })

      -- Apply role style to just the name text (not the ruler chars)
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_idx, 1, {
        end_col = colon_col,
        hl_group = roles.highlight_group("FlemmaRole", role_name) .. "Name",
        hl_mode = "combine",
      })

      -- On the progress line, only replace : with a space (no ruler extension)
      -- so the EOL progress text isn't covered by overlay chars.
      -- On all other lines, extend ruler chars to the window edge.
      if line_idx == progress_line then
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_idx, colon_col, {
          virt_text = { { " ", "FlemmaRuler" } },
          virt_text_pos = "overlay",
          hl_mode = "combine",
        })
      else
        local inline_space = 1 -- inserted space between ruler char and role name
        local remaining = math.max(0, win_width - colon_col - 1 - inline_space)
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_idx, colon_col, {
          virt_text = { { " " .. string.rep(ruler_config.char, remaining), "FlemmaRuler" } },
          virt_text_pos = "overlay",
          hl_mode = "combine",
        })
      end
    end
  end
end

---Highlight thinking tags and blocks using extmarks (higher priority than Treesitter)
---@param bufnr integer
---@param doc flemma.ast.DocumentNode
function M.highlight_thinking_tags(bufnr, doc)
  -- Clear existing thinking tag highlights
  vim.api.nvim_buf_clear_namespace(bufnr, thinking_ns, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Iterate through messages and their segments to find thinking blocks
  for _, msg in ipairs(doc.messages) do
    if msg.segments then
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "thinking" and seg.position then
          -- Apply range extmark for thinking block background
          local start_idx = seg.position.start_line - 1
          local end_idx = (seg.position.end_line or seg.position.start_line) - 1
          if start_idx >= 0 and end_idx < #lines then
            vim.api.nvim_buf_set_extmark(bufnr, thinking_ns, start_idx, 0, {
              end_row = end_idx,
              end_col = #lines[end_idx + 1],
              line_hl_group = "FlemmaThinkingBlock",
              priority = PRIORITY.THINKING_BLOCK,
            })
          end

          -- Highlight opening tag text
          vim.api.nvim_buf_set_extmark(bufnr, thinking_ns, seg.position.start_line - 1, 0, {
            end_line = seg.position.start_line,
            hl_group = "FlemmaThinkingTag",
            priority = PRIORITY.THINKING_TAG,
          })
          -- Highlight closing tag text
          if seg.position.end_line then
            vim.api.nvim_buf_set_extmark(bufnr, thinking_ns, seg.position.end_line - 1, 0, {
              end_line = seg.position.end_line,
              hl_group = "FlemmaThinkingTag",
              priority = PRIORITY.THINKING_TAG,
            })
          end
        end
      end
    end
  end
end

---Apply full-line background highlighting for messages and frontmatter
---@param bufnr integer
---@param doc flemma.ast.DocumentNode
function M.apply_line_highlights(bufnr, doc)
  local current_config = config_facade.get(bufnr)
  if not current_config.line_highlights or not current_config.line_highlights.enabled then
    return
  end

  -- Clear existing line highlights
  vim.api.nvim_buf_clear_namespace(bufnr, line_hl_ns, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Highlight frontmatter if present
  if doc.frontmatter and doc.frontmatter.position then
    local start_idx = doc.frontmatter.position.start_line - 1
    local end_idx = (doc.frontmatter.position.end_line or doc.frontmatter.position.start_line) - 1
    if start_idx >= 0 and end_idx < #lines then
      vim.api.nvim_buf_set_extmark(bufnr, line_hl_ns, start_idx, 0, {
        end_row = end_idx,
        end_col = #lines[end_idx + 1],
        line_hl_group = "FlemmaLineFrontmatter",
        priority = PRIORITY.LINE_HIGHLIGHT,
      })
    end
  end

  -- Highlight messages with range extmarks (one per message)
  for _, msg in ipairs(doc.messages) do
    local hl_group = roles.highlight_group("FlemmaLine", msg.role)
    local start_idx = msg.position.start_line - 1
    local end_idx = (msg.position.end_line or msg.position.start_line) - 1
    if start_idx >= 0 and end_idx < #lines then
      vim.api.nvim_buf_set_extmark(bufnr, line_hl_ns, start_idx, 0, {
        end_row = end_idx,
        end_col = #lines[end_idx + 1],
        end_right_gravity = true,
        line_hl_group = hl_group,
        priority = PRIORITY.LINE_HIGHLIGHT,
      })
    end
  end

  -- Invalidate cursorline cache so update_cursorline() (called later in
  -- update_ui) re-evaluates with the new highlight groups instead of
  -- hitting the same-row early return.
  state.get_buffer_state(bufnr).cursorline_prev_row = nil
end

---Remove the CursorLine overlay extmark for a buffer.
---@param bufnr integer
local function remove_cursorline(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  local eid = buffer_state.cursorline_extmark_id
  if eid then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, cursorline_ns, eid)
    buffer_state.cursorline_extmark_id = nil
  end
  buffer_state.cursorline_prev_row = nil
end

---Check whether a window is a floating window.
---@param winid integer
---@return boolean
local function is_floating_window(winid)
  local ok, win_config = pcall(vim.api.nvim_win_get_config, winid)
  return ok and win_config.relative ~= nil and win_config.relative ~= ""
end

---Update the CursorLine overlay extmark for the current cursor position.
---Finds the line highlight (or thinking block) under the cursor and places
---a higher-priority extmark with the blended CursorLine variant.
---Uses a stable extmark ID to update in-place (no clear-and-recreate).
---Queries the buffer's own window for cursor position and cursorline state,
---so it works correctly even when focus is in a floating window.
---NOTE: bufwinid() returns only the first window displaying the buffer;
---if the same .chat buffer is open in multiple splits, only one gets the overlay.
---@param bufnr integer
local function update_cursorline(bufnr)
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return
  end

  local row = vim.api.nvim_win_get_cursor(winid)[1] - 1 -- 0-indexed

  -- Check cursorline on the buffer's own window, not whichever window has focus
  if not vim.wo[winid].cursorline then
    remove_cursorline(bufnr)
    return
  end

  -- Only show overlay when the buffer's window is "active": either focused directly
  -- or focus is in a transient floating window (completion menu, hover, etc.)
  local current_win = vim.api.nvim_get_current_win()
  if current_win ~= winid then
    if not is_floating_window(current_win) then
      remove_cursorline(bufnr)
      return
    end
  end

  local buffer_state = state.get_buffer_state(bufnr)

  -- Skip if cursor hasn't moved to a different line
  if row == buffer_state.cursorline_prev_row then
    return
  end
  buffer_state.cursorline_prev_row = row

  -- Find the line highlight group at the cursor row
  ---@type string|nil
  local target_hl_group

  -- Check thinking blocks namespace first (higher visual priority)
  local thinking_marks = vim.api.nvim_buf_get_extmarks(
    bufnr,
    thinking_ns,
    { row, 0 },
    { row, 0 },
    { details = true, overlap = true }
  )
  for _, mark in ipairs(thinking_marks) do
    local details = mark[4]
    if details and details.line_hl_group then
      target_hl_group = details.line_hl_group .. "CursorLine"
      break
    end
  end

  -- Check line highlights namespace
  if not target_hl_group then
    local line_marks = vim.api.nvim_buf_get_extmarks(
      bufnr,
      line_hl_ns,
      { row, 0 },
      { row, 0 },
      { details = true, overlap = true }
    )
    for _, mark in ipairs(line_marks) do
      local details = mark[4]
      if details and details.line_hl_group then
        target_hl_group = details.line_hl_group .. "CursorLine"
        break
      end
    end
  end

  if target_hl_group then
    ---@type vim.api.keyset.set_extmark
    local opts = {
      line_hl_group = target_hl_group,
      priority = PRIORITY.CURSORLINE,
    }
    local eid = buffer_state.cursorline_extmark_id
    if eid then
      opts.id = eid
    end
    buffer_state.cursorline_extmark_id = vim.api.nvim_buf_set_extmark(bufnr, cursorline_ns, row, 0, opts)
  else
    remove_cursorline(bufnr)
  end
end

-- Updatetime management state
-- We use reference counting to track how many chat buffers are "active"
-- (i.e., currently being displayed in a window). Only restore updatetime
-- when the last active chat buffer is left.
local updatetime_state = {
  original = nil, -- The original updatetime before any chat buffer was entered
  active_chat_buffers = {}, -- Set of bufnr that are currently active (in a window)
}

---Count active chat buffers
---@return integer
local function count_active_chat_buffers()
  local count = 0
  for _ in pairs(updatetime_state.active_chat_buffers) do
    count = count + 1
  end
  return count
end

---Parse the `editing.conceal` format `{conceallevel}{concealcursor}` into a
---pair. Accepts string (`"2nv"`), integer (`2`), or boolean/nil (skip).
---Returns nil when parsing should skip the override (unset/false/malformed).
---@param value string|integer|boolean|nil
---@return { level: integer, cursor: string }|nil
local function parse_conceal_override(value)
  if value == nil or value == false then
    return nil
  end
  local spec = tostring(value)
  local level_str, cursor_chars = spec:match("^(%d)(.*)$")
  if not level_str then
    return nil
  end
  return { level = tonumber(level_str), cursor = cursor_chars or "" }
end

---Toggle conceallevel between 0 and the configured level for the current
---window. No-op when `editing.conceal` is unset or false.
---
---When toggling from the configured level down to 0, the frontmatter fold
---rule starts emitting fold entries (it suppresses them at conceallevel >= 1
---because Neovim's `conceal_lines` hides the fold placeholder). The
---OptionSet autocmd invalidates the fold map, and because the window's
---foldlevel is typically 1, the newly created level-2 frontmatter fold
---auto-closes — collapsing the block under the cursor. We re-open it
---after the toggle so the transition feels transparent.
function M.toggle_conceal()
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_get_current_buf()
  local cfg = config_facade.get(bufnr)
  local parsed = cfg and cfg.editing and parse_conceal_override(cfg.editing.conceal)
  if not parsed then
    return
  end
  local current = vim.api.nvim_get_option_value("conceallevel", { win = winid, scope = "local" })
  if current == parsed.level then
    vim.api.nvim_set_option_value("conceallevel", 0, { win = winid, scope = "local" })
    -- The OptionSet autocmd has already fired synchronously, rebuilding the
    -- fold map. The frontmatter fold (level 2) was just created and auto-closed
    -- by foldlevel. Re-open it so the toggle doesn't collapse the block.
    local doc = parser.get_parsed_document(bufnr)
    if doc.frontmatter then
      local fm_start = doc.frontmatter.position.start_line
      local closed = vim.fn.foldclosed(fm_start)
      if closed ~= -1 then
        vim.api.nvim_win_call(winid, function()
          vim.cmd(fm_start .. "foldopen")
        end)
      end
    end
  else
    vim.api.nvim_set_option_value("conceallevel", parsed.level, { win = winid, scope = "local" })
  end
end

---Apply window-local settings for a chat buffer displayed in a window.
---Sets `conceallevel` and `concealcursor` from `editing.conceal`. A nil/false
---value leaves whatever the user/colorscheme has configured alone.
---
---Uses `scope = "local"` explicitly: `nvim_set_option_value` with only `win`
---specified mutates BOTH window-local and global values (equivalent to
---`:set`, not `:setlocal`). Without the scope hint we would pollute the
---user's global `conceallevel`/`concealcursor` every time a chat buffer is
---opened.
---@param winid integer Window ID
---@param bufnr integer Buffer displayed in the window
function M.apply_chat_window_settings(winid, bufnr)
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end
  local cfg = config_facade.get(bufnr)
  local parsed = cfg and cfg.editing and parse_conceal_override(cfg.editing.conceal)
  if not parsed then
    return
  end
  vim.api.nvim_set_option_value("conceallevel", parsed.level, { win = winid, scope = "local" })
  vim.api.nvim_set_option_value("concealcursor", parsed.cursor, { win = winid, scope = "local" })
end

---Apply buffer-local settings for chat files, plus window-local settings for
---whatever window currently hosts the buffer.
---@param bufnr integer Buffer number
local function apply_chat_buffer_settings(bufnr)
  folding.setup_folding(bufnr)
  turns.setup_statuscolumn(bufnr)

  local current = config_facade.get(bufnr)
  if current and current.editing and current.editing.disable_textwidth then
    vim.bo[bufnr].textwidth = 0
  end

  -- Enable gf / <C-w>f navigation for @./file references and {{ include() }} expressions.
  -- Extend isfname so Neovim's gf extracts a candidate that covers the full {{ ... }}
  -- expression — without these, cursor on ), }, or { wouldn't trigger includeexpr.
  for character in ("{()}"):gmatch(".") do
    vim.opt_local.isfname:append(character)
  end
  vim.bo[bufnr].includeexpr = 'v:lua.require("flemma.navigation").resolve_include_path_expr()'

  -- Apply window-scoped options (conceal) to whichever window currently shows
  -- the buffer. Our BufRead/BufNewFile and FileType callbacks always fire in
  -- that window, so bufwinid resolves correctly.
  local winid = vim.fn.bufwinid(bufnr)
  if winid ~= -1 then
    M.apply_chat_window_settings(winid, bufnr)
  end
end

---Set up chat filetype autocmds
function M.setup_chat_filetype_autocmds()
  -- Create or clear the augroup for all chat-related autocmds
  local augroup = vim.api.nvim_create_augroup("FlemmaChat", { clear = true })

  -- Reset updatetime state when re-initializing
  updatetime_state = {
    original = nil,
    active_chat_buffers = {},
  }

  -- Handle .chat file detection
  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    group = augroup,
    pattern = "*.chat",
    desc = "Flemma: migrate legacy .chat, set filetype, apply buffer+window settings",
    callback = function(ev)
      -- Clear any orphaned cursorline extmark from a prior session.
      -- :e reload fires BufUnload first, which calls cleanup_buffer_state() and
      -- sets buffer_states[bufnr] = nil — losing cursorline_extmark_id. The
      -- actual extmark in cursorline_ns survives the reload (extmarks are owned
      -- by the buffer object, not the text), leaving a permanently highlighted
      -- line that no code path can remove. Clearing the namespace here runs
      -- once per reload, not on every cursor move.
      vim.api.nvim_buf_clear_namespace(ev.buf, cursorline_ns, 0, -1)
      migration.migrate_buffer(ev.buf)
      vim.bo[ev.buf].filetype = "chat"
      apply_chat_buffer_settings(ev.buf)
      bridge.auto_prompt(ev.buf)
    end,
  })

  -- Handle manual filetype changes to 'chat'
  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = "chat",
    desc = "Flemma: apply buffer+window settings on filetype=chat",
    callback = function(ev)
      apply_chat_buffer_settings(ev.buf)
    end,
  })

  -- `conceallevel` / `concealcursor` are window-local, not buffer-local, and
  -- Neovim copies window-local options to new windows on :split/:tabedit. That
  -- means a sibling window opened from a chat window inherits Flemma's
  -- conceal override even though the sibling isn't a chat buffer. When a
  -- non-chat buffer lands in a window whose conceal values still match
  -- Flemma's chat fingerprint, restore the global defaults so filetype-
  -- specific ftplugins (or the user's init) decide what conceal means for
  -- that buffer.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = augroup,
    desc = "Flemma: restore global conceal when a non-chat buffer enters a window carrying chat's conceal fingerprint",
    callback = function(ev)
      local bufnr = ev.buf
      if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype == "chat" then
        return
      end
      local winid = vim.fn.bufwinid(bufnr)
      if winid == -1 then
        return
      end
      local cfg = config_facade.get(bufnr)
      local parsed = cfg and cfg.editing and parse_conceal_override(cfg.editing.conceal)
      if not parsed then
        return
      end
      local current_level = vim.api.nvim_get_option_value("conceallevel", { win = winid, scope = "local" })
      local current_cursor = vim.api.nvim_get_option_value("concealcursor", { win = winid, scope = "local" })
      if current_level ~= parsed.level or current_cursor ~= parsed.cursor then
        return
      end
      vim.api.nvim_set_option_value("conceallevel", vim.go.conceallevel, { win = winid, scope = "local" })
      vim.api.nvim_set_option_value("concealcursor", vim.go.concealcursor, { win = winid, scope = "local" })
    end,
  })

  -- The frontmatter fold rule reads `vim.wo.conceallevel` to decide whether
  -- to fold (see lua/flemma/ui/folding/rules/frontmatter.lua). The fold map
  -- cache is keyed on changedtick + bufnr, so a bare conceallevel flip
  -- wouldn't invalidate it. Rebuild on conceallevel changes in chat windows.
  vim.api.nvim_create_autocmd("OptionSet", {
    group = augroup,
    pattern = "conceallevel",
    desc = "Flemma: rebuild fold map when conceallevel changes in a chat buffer",
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      if vim.bo[bufnr].filetype == "chat" then
        folding.invalidate_folds(bufnr)
      end
    end,
  })

  -- Handle updatetime management for chat buffers
  local editing_config = config_facade.get()
  if editing_config and editing_config.editing and editing_config.editing.manage_updatetime then
    vim.api.nvim_create_autocmd("BufEnter", {
      group = augroup,
      pattern = "*.chat",
      callback = function(ev)
        local bufnr = ev.buf

        -- Save original updatetime on first chat buffer activation
        if updatetime_state.original == nil then
          updatetime_state.original = vim.o.updatetime
        end

        -- Mark this buffer as active
        updatetime_state.active_chat_buffers[bufnr] = true

        -- Set fast updatetime for chat buffers
        vim.o.updatetime = 100
      end,
    })

    vim.api.nvim_create_autocmd("BufLeave", {
      group = augroup,
      pattern = "*.chat",
      callback = function(ev)
        local bufnr = ev.buf

        -- Remove this buffer from active set
        updatetime_state.active_chat_buffers[bufnr] = nil

        -- Use vim.schedule to defer the check - this allows BufEnter on the
        -- next buffer to fire first, so we can see if we're switching to another
        -- chat buffer (in which case we shouldn't restore updatetime)
        vim.schedule(function()
          -- Only restore updatetime if no more active chat buffers
          if count_active_chat_buffers() == 0 and updatetime_state.original ~= nil then
            vim.o.updatetime = updatetime_state.original
            updatetime_state.original = nil
          end
        end)
      end,
    })

    -- Also clean up when buffers are deleted
    vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload", "BufDelete" }, {
      group = augroup,
      pattern = "*.chat",
      callback = function(ev)
        local bufnr = ev.buf
        updatetime_state.active_chat_buffers[bufnr] = nil

        -- Use vim.schedule here too for consistency
        vim.schedule(function()
          -- Restore if this was the last active chat buffer
          if count_active_chat_buffers() == 0 and updatetime_state.original ~= nil then
            vim.o.updatetime = updatetime_state.original
            updatetime_state.original = nil
          end
        end)
      end,
    })
  end

  -- CursorLine overlay: swap line highlight to blended CursorLine variant under cursor
  local current_config = config_facade.get()
  if current_config.line_highlights and current_config.line_highlights.enabled then
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
      group = augroup,
      pattern = "*.chat",
      callback = function(ev)
        update_cursorline(ev.buf)
      end,
    })

    -- Re-apply overlay when entering a chat window (including first entry
    -- where cursorline_prev_row is nil and the global WinEnter would skip it).
    vim.api.nvim_create_autocmd("WinEnter", {
      group = augroup,
      pattern = "*.chat",
      callback = function(ev)
        update_cursorline(ev.buf)
      end,
    })

    -- Global WinEnter: re-evaluate cursorline overlays for chat buffers that have one.
    -- When entering a regular (non-float) window, overlays on unfocused chat windows
    -- are cleared. When entering a floating window (completion menu, hover, etc.),
    -- overlays persist — the user is still conceptually in the chat window.
    -- No WinLeave handler is needed: the overlay persists untouched until WinEnter
    -- re-evaluates, avoiding any rendering frame where it's missing.
    vim.api.nvim_create_autocmd("WinEnter", {
      group = augroup,
      callback = function()
        for bufnr, buffer_state in state.each_buffer_state() do
          if buffer_state.cursorline_prev_row and vim.api.nvim_buf_is_valid(bufnr) then
            update_cursorline(bufnr)
          end
        end
      end,
    })

    -- React to :set cursorline / :set nocursorline / :setlocal variants.
    -- Ignore changes originating from floating windows (e.g., blink-cmp
    -- setting cursorline on its completion menu), which fire OptionSet
    -- but don't affect the chat window's cursorline state.
    vim.api.nvim_create_autocmd("OptionSet", {
      group = augroup,
      pattern = "cursorline",
      callback = function()
        if is_floating_window(vim.api.nvim_get_current_win()) then
          return -- Change originated from a floating window; ignore
        end

        -- Re-evaluate overlays for all chat buffers (not just those with an
        -- active overlay — :set cursorline needs to CREATE overlays too)
        for bufnr in state.each_buffer_state() do
          if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "chat" then
            update_cursorline(bufnr)
          end
        end
      end,
    })
  end
end

---Add virtual line previews inside empty tool_result fences that carry a
---lifecycle (status) suffix in the header. Shows a compact summary of the
---tool call (name + input) so users can see what they're approving/rejecting
---without the content being editable.
---@param bufnr integer
---@param doc flemma.ast.DocumentNode
function M.add_tool_previews(bufnr, doc)
  vim.api.nvim_buf_clear_namespace(bufnr, tool_preview_ns, 0, -1)

  local siblings = ast.build_tool_sibling_table(doc)

  -- Compute available text width from the buffer's window
  local winid = vim.fn.bufwinid(bufnr)
  local max_length = preview.get_text_area_width(winid)

  -- At conceallevel>=1, tree-sitter's markdown highlights query hides the
  -- fenced_code_block_delimiter lines entirely via `#set! conceal_lines ""`,
  -- taking any extmarks anchored to those lines (including our virt_lines)
  -- with them. Anchor one line higher — on the blank line between the
  -- `**Tool Result:**` header and the opening fence, which carries no conceal
  -- metadata — so the preview survives. At conceallevel=0 the fences render
  -- normally and we keep the original inside-the-fence position.
  local conceal_level = 0
  if winid ~= -1 then
    conceal_level = vim.api.nvim_get_option_value("conceallevel", { win = winid })
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)

  -- Show previews for tool_result blocks with empty content that are either
  -- pending/approved (have a lifecycle status suffix) or currently executing (have active indicator).
  -- Without the indicator check, the preview disappears when the executor
  -- clears the header status suffix at execution start.
  for _, msg in ipairs(doc.messages) do
    if roles.is_user(msg.role) then
      for _, seg in ipairs(msg.segments) do
        if
          seg.kind == "tool_result"
          and seg.content == ""
          and (seg.status or indicators.has_indicator(bufnr, seg.tool_use_id))
        then
          local sibling = siblings[seg.tool_use_id]
          local tool_use = sibling and sibling.use or nil
          if tool_use then
            -- Opening fence is one line before closing fence (empty content)
            local opening_fence_line = seg.position.end_line - 1
            local line_idx
            if conceal_level >= 1 then
              line_idx = opening_fence_line - 2 -- 0-indexed: blank line before fence
            else
              line_idx = opening_fence_line - 1 -- 0-indexed: opening fence line
            end

            if line_idx >= 0 and line_idx < line_count then
              local preview_text = preview.format_tool_preview(tool_use.name, tool_use.input, max_length)
              -- `line_hl_group` on the covering range extmark does not propagate to
              -- virt_lines, so the role's line bg would stop at the virt_line and
              -- reappear on the next buffer line — a visible stripe against tinted
              -- backgrounds. Paint the bg manually: combine FlemmaToolPreview fg
              -- with the role's line bg on the text chunk, then pad to the text
              -- area width so the bg extends like a real line_hl_group would.
              local role_hl = roles.highlight_group("FlemmaLine", msg.role)
              local pad_width = math.max(0, max_length - str.strwidth(preview_text))
              ---@type {[1]:string, [2]:string|string[]}[]
              local chunks = { { preview_text, { "FlemmaToolPreview", role_hl } } }
              if pad_width > 0 then
                table.insert(chunks, { string.rep(" ", pad_width), role_hl })
              end
              vim.api.nvim_buf_set_extmark(bufnr, tool_preview_ns, line_idx, 0, {
                virt_lines = { chunks },
              })
            end
          end
        end
      end
    end
  end
end

---Force UI update (rulers, line highlights, and turn indicators)
---@param bufnr integer
function M.update_ui(bufnr)
  -- Ensure buffer is valid before proceeding
  if not vim.api.nvim_buf_is_valid(bufnr) then
    log.debug("update_ui(): Invalid buffer: " .. bufnr)
    return
  end

  -- Bail if config is not fully initialized (e.g. in test environments)
  local current_config = config_facade.get(bufnr)
  if not current_config.ruler then
    return
  end

  -- Parse messages using AST
  local doc = parser.get_parsed_document(bufnr)

  M.add_rulers(bufnr, doc)
  M.highlight_thinking_tags(bufnr, doc)
  M.apply_line_highlights(bufnr, doc)
  M.add_tool_previews(bufnr, doc)
  -- Note: progress extmark (with spell suppression) is managed by start_progress and its timer

  -- Re-apply CursorLine overlay now that line highlights are refreshed,
  -- so the blend reflects the current AST state instead of the pre-edit state.
  update_cursorline(bufnr)

  folding.invalidate_folds(bufnr)
  folding.fold_completed_blocks(bufnr)
  turns.update(bufnr)
end

---Set up UI-related autocmds and initialization
function M.setup()
  -- Create or clear the augroup for UI-related autocmds
  local augroup = vim.api.nvim_create_augroup("FlemmaUI", { clear = true })

  -- Add autocmd for updating rulers and line highlights (debounced via CursorHold)
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "VimResized", "CursorHold", "CursorHoldI" }, {
    group = augroup,
    pattern = "*.chat",
    callback = function(ev)
      local buffer_state = state.get_buffer_state(ev.buf)
      local tick = vim.api.nvim_buf_get_changedtick(ev.buf)
      -- CursorHold fires frequently with low updatetime — skip if buffer unchanged
      if (ev.event == "CursorHold" or ev.event == "CursorHoldI") and buffer_state.ui_update_tick == tick then
        return
      end
      bridge.update_ui(ev.buf)
      buffer_state.ui_update_tick = tick
    end,
  })

  -- Passively evaluate frontmatter when buffer content changes so integrations
  -- (e.g., lualine) see up-to-date config values without waiting for a request send.
  -- Gated inside evaluate_frontmatter_if_changed: no-op unless the frontmatter code
  -- actually changed, and skipped when buffer is locked (request in flight).
  -- BufEnter covers switching to a buffer whose frontmatter hasn't been evaluated yet.
  vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged", "BufEnter" }, {
    group = augroup,
    pattern = "*.chat",
    callback = function(ev)
      processor.evaluate_frontmatter_if_changed(ev.buf)
    end,
  })

  -- Ensure buffer-local state gets cleaned up when chat buffers are removed.
  -- This prevents leaking timers or jobs if a buffer is deleted while a request/progress indicator is active.
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload", "BufDelete" }, {
    group = augroup,
    pattern = "*",
    callback = function(ev)
      if vim.bo[ev.buf].filetype == "chat" or string.match(vim.api.nvim_buf_get_name(ev.buf), "%.chat$") then
        activity.cleanup_progress(ev.buf, M.update_ui)
        indicators.clear_all_tool_indicators(ev.buf)
        -- state.cleanup_buffer_state handles executor.cleanup_buffer internally
        state.cleanup_buffer_state(ev.buf)
      end
    end,
  })
end

return M
