--- UI module for Flemma plugin
--- Handles visual presentation: rulers, progress indicators, and folding
---@class flemma.UI
local M = {}

local config_facade = require("flemma.config")
local hooks = require("flemma.hooks")
local log = require("flemma.logging")
local state = require("flemma.state")
local preview = require("flemma.ui.preview")
local highlighter = require("flemma.ui.highlighter")
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
local highlight = require("flemma.highlight")
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
local tool_approval_ns = vim.api.nvim_create_namespace("flemma_tool_approval")
local BASE_TOOL_PREVIEW_HL = "FlemmaToolPreview"

-- Approval-prompt keybind hints, keyed by bufnr. Built lazily on first render
-- from the buffer's keymaps config and reused across cursor moves. It is only
-- cleared on buffer teardown (see the BufWipeout/BufUnload/BufDelete autocmd in
-- M.setup), NOT on a runtime keymaps config change — acceptable because keymaps
-- are resolved when the buffer is set up, not per request. A user who rebinds
-- approval keys mid-session sees the new hints after reopening the buffer.
---@type table<integer, {key_display: string, label: string, min_pending: integer|nil}[]>
local keybind_hints_cache = {}
local fence_ns = vim.api.nvim_create_namespace("flemma_fence_overlays")

---@type string
local FENCE_BAR_CHAR = "╌"
local APPROVAL_OPEN = "꜖"
local APPROVAL_CLOSE = ""

---Build the virt_text chunks for a fence overlay on the given line.
---Returns nil when the line is not a fence delimiter.
---@param line string
---@param bar_hl string Highlight group for the bar portion
---@param label_hl string Highlight group for the language label
---@return {[1]:string, [2]:string}[]|nil
function M.build_fence_virt_text(line, bar_hl, label_hl)
  if not line:match("^```") then
    return nil
  end
  local bar = string.rep(FENCE_BAR_CHAR, 3)
  local lang = line:match("^```(.+)$")
  if lang then
    return { { bar, bar_hl }, { lang, label_hl } }
  end
  return { { bar, bar_hl } }
end

---Resolve the highlight groups for a fence overlay on the given row.
---Returns nil when fence overlays should not be shown (wrong filetype,
---conceal patch inactive, conceallevel too low, or line is not a fence).
---@param bufnr integer
---@param winid integer
---@param row integer 0-indexed line number
---@return string|nil bar_hl
---@return string|nil label_hl
function M.resolve_fence_highlights(bufnr, winid, row)
  if vim.bo[bufnr].filetype ~= "chat" then
    return nil, nil
  end
  if not highlight.is_fence_conceal_patched() then
    return nil, nil
  end
  local win_cl = vim.api.nvim_get_option_value("conceallevel", { win = winid, scope = "local" })
  if win_cl < 2 then
    return nil, nil
  end
  local bar_hl = "FlemmaFenceBar"
  local label_hl = "FlemmaFenceLabel"
  local buffer_state = state.get_buffer_state(bufnr)
  if buffer_state.cursorline_prev_row == row and buffer_state.cursorline_hl_group then
    local variants = highlight.get_fence_cursorline_map()[buffer_state.cursorline_hl_group]
    if variants then
      bar_hl = variants[bar_hl] or bar_hl
      label_hl = variants[label_hl] or label_hl
    end
  end
  return bar_hl, label_hl
end

---Register (or re-register) the decoration provider that places ephemeral
---fence overlay extmarks at draw time. Because marks are ephemeral they are
---re-evaluated on every redraw — no persistent state to invalidate when the
---user edits a fence delimiter.
function M.setup_fence_decoration_provider()
  vim.api.nvim_set_decoration_provider(fence_ns, {
    on_win = function(_, _, bufnr, _, _)
      if vim.bo[bufnr].filetype ~= "chat" then
        return false
      end
      if not highlight.is_fence_conceal_patched() then
        return false
      end
    end,
    on_line = function(_, winid, bufnr, row)
      local bar_hl, label_hl = M.resolve_fence_highlights(bufnr, winid, row)
      if not bar_hl then
        return
      end
      local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
      if not line then
        return
      end
      ---@cast bar_hl string
      ---@cast label_hl string
      local chunks = M.build_fence_virt_text(line, bar_hl, label_hl)
      if chunks then
        vim.api.nvim_buf_set_extmark(bufnr, fence_ns, row, 0, {
          virt_text = chunks,
          virt_text_pos = "overlay",
          hl_mode = "combine",
          ephemeral = true,
        })
      end
    end,
  })
end

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
  buffer_state.cursorline_hl_group = nil
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
    buffer_state.cursorline_hl_group = target_hl_group
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

---Set conceallevel for the current window. Returns false if `editing.conceal`
---is unset/false (no-op).
---@param level integer
---@return boolean applied
local function set_conceal_level(level)
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_get_current_buf()
  local cfg = config_facade.get(bufnr)
  local parsed = cfg and cfg.editing and parse_conceal_override(cfg.editing.conceal)
  if not parsed then
    return false
  end
  vim.api.nvim_set_option_value("conceallevel", level, { win = winid, scope = "local" })
  return true
end

---Toggle conceallevel between 0 and the configured level for the current
---window. No-op when `editing.conceal` is unset or false.
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
    set_conceal_level(0)
  else
    set_conceal_level(parsed.level)
  end
end

---Enable conceal (set to configured level). No-op when `editing.conceal` is
---unset or false.
function M.enable_conceal()
  local bufnr = vim.api.nvim_get_current_buf()
  local cfg = config_facade.get(bufnr)
  local parsed = cfg and cfg.editing and parse_conceal_override(cfg.editing.conceal)
  if not parsed then
    return
  end
  set_conceal_level(parsed.level)
end

---Disable conceal (set conceallevel to 0). No-op when `editing.conceal` is
---unset or false.
function M.disable_conceal()
  set_conceal_level(0)
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
    desc = "Flemma: run load-time migrations, set filetype, apply buffer+window settings",
    callback = function(ev)
      -- Patch the markdown treesitter highlights query on first .chat open,
      -- before setting filetype triggers the highlighter constructor.
      highlight.strip_fence_conceal()
      -- Clear any orphaned cursorline extmark from a prior session.
      -- :e reload fires BufUnload first, which calls cleanup_buffer_state() and
      -- sets buffer_states[bufnr] = nil — losing cursorline_extmark_id. The
      -- actual extmark in cursorline_ns survives the reload (extmarks are owned
      -- by the buffer object, not the text), leaving a permanently highlighted
      -- line that no code path can remove. Clearing the namespace here runs
      -- once per reload, not on every cursor move.
      vim.api.nvim_buf_clear_namespace(ev.buf, cursorline_ns, 0, -1)
      migration.migrate(ev.buf)
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
      hooks.dispatch("buffer:created", { bufnr = ev.buf })
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

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup,
    pattern = "*.chat",
    callback = function(ev)
      M.update_approval_prompt(ev.buf)
    end,
  })

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

---Compute the 0-indexed buffer row where a tool_result's preview and approval
---virt_lines anchor: the block's opening fence (one line above the closing
---fence at seg.position.end_line). virt_lines on that row render below it,
---inside the empty fence. May be negative for malformed blocks; callers guard.
---@param seg flemma.ast.ToolResultSegment
---@return integer row 0-indexed anchor row
local function tool_result_anchor_row(seg)
  local opening_fence_line = seg.position.end_line - 1 -- 1-indexed opening fence
  return opening_fence_line - 1 -- 0-indexed row for the extmark anchor
end

---Build virt_lines from highlighted chunk arrays with prefix, truncation, and trimming.
---@param lines_chunks {[1]: string, [2]: string}[][] Content-only highlighted chunks
---@param ctx flemma.ui.HighlightContext Highlight context with prefix/indent/lang
---@param role_hl string Role line highlight group
---@param max_length integer Text area width
---@param head integer Head line budget
---@param tail integer Tail line budget
---@return {[1]:string, [2]:string|string[]}[][] virt_lines
local function build_highlighted_virt_lines(lines_chunks, ctx, role_hl, max_length, head, tail)
  ---@type {[1]: string, [2]: string|string[]}[][]
  local prefixed = {}
  for i, content_chunks in ipairs(lines_chunks) do
    local prefix = i == 1 and ctx.name_prefix or ctx.indent
    local prefix_width = str.strwidth(prefix)
    local content_budget = max_length - prefix_width

    local truncated = preview.truncate_chunks(content_chunks, content_budget)

    ---@type {[1]: string, [2]: string|string[]}[]
    local line_chunks = { { prefix, { BASE_TOOL_PREVIEW_HL, role_hl } } }
    for _, chunk in ipairs(truncated) do
      line_chunks[#line_chunks + 1] = { chunk[1], { chunk[2], role_hl } }
    end

    local used = prefix_width
    for _, chunk in ipairs(truncated) do
      used = used + str.strwidth(chunk[1])
    end
    local pad = math.max(0, max_length - used)
    if pad > 0 then
      line_chunks[#line_chunks + 1] = { string.rep(" ", pad), role_hl }
    end

    prefixed[i] = line_chunks
  end

  return preview.trim_chunks(prefixed, head, tail)
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

  local winid = vim.fn.bufwinid(bufnr)
  local max_length = preview.get_text_area_width(winid)

  local line_count = vim.api.nvim_buf_line_count(bufnr)

  local approval_config = config_facade.get(bufnr).ui.approval
  local preview_opts = { head = approval_config.preview_lines.head, tail = approval_config.preview_lines.tail }

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
            local line_idx = tool_result_anchor_row(seg)

            if line_idx >= 0 and line_idx < line_count then
              local role_hl = roles.highlight_group("FlemmaLine", msg.role)
              local preview_lines, label, highlight_context =
                preview.format_tool_preview_multiline(tool_use.name, tool_use.input, max_length, preview_opts)

              ---@type {[1]:string, [2]:string|string[]}[][]
              local virt_lines

              local used_highlighted = false
              if highlight_context then
                local in_sync_scope = true
                highlighter.highlight(highlight_context.text, highlight_context.lang, function(lines_chunks)
                  if lines_chunks then
                    if in_sync_scope then
                      virt_lines = build_highlighted_virt_lines(
                        lines_chunks,
                        highlight_context,
                        role_hl,
                        max_length,
                        preview_opts.head or 6,
                        preview_opts.tail or 6
                      )
                      used_highlighted = true
                    else
                      bridge.update_ui(bufnr)
                    end
                  end
                end)
                in_sync_scope = false
              end

              if not used_highlighted then
                virt_lines = {}
                for _, line_text in ipairs(preview_lines) do
                  local pad_width = math.max(0, max_length - str.strwidth(line_text))
                  ---@type {[1]:string, [2]:string|string[]}[]
                  local chunks = { { line_text, { BASE_TOOL_PREVIEW_HL, role_hl } } }
                  if pad_width > 0 then
                    table.insert(chunks, { string.rep(" ", pad_width), role_hl })
                  end
                  virt_lines[#virt_lines + 1] = chunks
                end
              end

              if seg.status ~= "pending" and label and #preview_lines > 1 then
                local footer = "— " .. label
                local pad_width = math.max(0, max_length - str.strwidth(footer))
                ---@type {[1]:string, [2]:string|string[]}[]
                local footer_chunks = { { footer, { "FlemmaToolLabel", role_hl } } }
                if pad_width > 0 then
                  table.insert(footer_chunks, { string.rep(" ", pad_width), role_hl })
                end
                virt_lines[#virt_lines + 1] = footer_chunks
              end

              vim.api.nvim_buf_set_extmark(bufnr, tool_preview_ns, line_idx, 0, {
                virt_lines = virt_lines,
              })
            end
          end
        end
      end
    end
  end

  -- Reuse the sibling table already built above instead of rebuilding it.
  M.update_approval_prompt(bufnr, doc, siblings)
end

---Render the approval prompt line for each pending tool_result.
---Layout: `— <label>  ⏸ N/M · <hints>` — the label leads (mirroring the
---settled footer) so it stays in a fixed position when the tool is approved;
---the pause indicator (⏸) and affordance follow. When the cursor is within a
---pending tool_result's range, that tool gets full keybind hints; others get
---a brief "Awaiting approval…".
---@param bufnr integer
---@param doc? flemma.ast.DocumentNode
---@param siblings? table<string, flemma.ast.ToolSibling> Prebuilt sibling table; built from doc when omitted (lets add_tool_previews share its table)
function M.update_approval_prompt(bufnr, doc, siblings)
  vim.api.nvim_buf_clear_namespace(bufnr, tool_approval_ns, 0, -1)

  local approval_config = config_facade.get(bufnr).ui.approval
  if not approval_config.enabled then
    return
  end

  doc = doc or parser.get_parsed_document(bufnr)

  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(winid)[1]

  siblings = siblings or ast.build_tool_sibling_table(doc)
  local max_length = preview.get_text_area_width(winid)
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  local pending_tools = {}
  local queue_total = 0
  for _, msg in ipairs(doc.messages) do
    if roles.is_user(msg.role) then
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "tool_result" and seg.content == "" then
          local sibling = siblings[seg.tool_use_id]
          if sibling and sibling.use then
            queue_total = queue_total + 1
            if seg.status == "pending" then
              pending_tools[#pending_tools + 1] = { seg = seg, msg = msg, queue_index = queue_total }
            end
          end
        end
      end
    end
  end

  if #pending_tools == 0 then
    return
  end

  if not keybind_hints_cache[bufnr] then
    ---@type {key_display: string, label: string, min_pending: integer|nil}[]
    local hints = {}
    local keymaps_config = config_facade.get(bufnr).keymaps
    if keymaps_config.enabled then
      local bindings = {
        { key = keymaps_config.normal.tool_approve, label = "Approve" },
        { key = keymaps_config.normal.tool_reject, label = "Reject" },
        { key = keymaps_config.normal.tool_approve_all, label = "All", min_pending = 2 },
      }
      for _, b in ipairs(bindings) do
        if type(b.key) == "string" and b.key ~= "" then
          hints[#hints + 1] = {
            key_display = b.key,
            label = b.label,
            min_pending = b.min_pending,
          }
        end
      end
    end
    keybind_hints_cache[bufnr] = hints
  end
  local keybind_hints = keybind_hints_cache[bufnr]

  for _, entry in ipairs(pending_tools) do
    local seg = entry.seg
    local line_idx = tool_result_anchor_row(seg)

    if line_idx >= 0 and line_idx < line_count then
      local cursor_on_this = cursor_line >= seg.position.start_line and cursor_line <= seg.position.end_line

      local sibling = siblings[seg.tool_use_id]
      local tool_use = sibling and sibling.use
      local label = tool_use and preview.format_tool_label(tool_use.name, tool_use.input) or nil

      ---@type {[1]:string, [2]:string}[]
      local prompt_chunks = {}

      if label then
        table.insert(prompt_chunks, { APPROVAL_OPEN .. " " .. label, "FlemmaApprovalLabel" })
        table.insert(prompt_chunks, { "  ", "FlemmaApprovalLine" })
      end

      table.insert(prompt_chunks, { "⏸ ", "FlemmaApprovalIndicator" })

      if queue_total > 1 then
        local counter = string.format("%d/%d", entry.queue_index, queue_total)
        table.insert(prompt_chunks, { counter, "FlemmaApprovalIndicator" })
        table.insert(prompt_chunks, { " · ", "FlemmaApprovalIndicator" })
      end

      if cursor_on_this and #keybind_hints > 0 then
        local rendered = 0
        for _, hint in ipairs(keybind_hints) do
          if not hint.min_pending or #pending_tools >= hint.min_pending then
            if rendered > 0 then
              table.insert(prompt_chunks, { "  ", "FlemmaApprovalLine" })
            end
            table.insert(prompt_chunks, { hint.key_display, "FlemmaApprovalKey" })
            table.insert(prompt_chunks, { " ", "FlemmaApprovalLine" })
            table.insert(prompt_chunks, { hint.label, "FlemmaApprovalAction" })
            rendered = rendered + 1
          end
        end
      else
        table.insert(prompt_chunks, { "Awaiting approval…", "FlemmaApprovalIndicator" })
      end

      local prompt_text_width = 0
      for _, c in ipairs(prompt_chunks) do
        prompt_text_width = prompt_text_width + str.strwidth(c[1])
      end
      local remaining_pad = max_length - prompt_text_width
      if approval_config.layout == "block" then
        if remaining_pad > 0 then
          table.insert(prompt_chunks, { string.rep(" ", remaining_pad), "FlemmaApprovalLine" })
        end
      else
        if APPROVAL_CLOSE ~= "" then
          local close_str = " " .. APPROVAL_CLOSE
          local close_width = str.strwidth(close_str)
          if remaining_pad >= close_width then
            table.insert(prompt_chunks, { close_str, "FlemmaApprovalLabel" })
            remaining_pad = remaining_pad - close_width
          end
        end
        if remaining_pad > 0 then
          table.insert(prompt_chunks, { " ", "FlemmaApprovalLine" })
          remaining_pad = remaining_pad - 1
        end
        local fade_steps = math.min(remaining_pad, approval_config.fade or 0)
        for i = 1, fade_steps do
          table.insert(prompt_chunks, { " ", string.format("FlemmaApprovalFade%d", i) })
        end
        remaining_pad = remaining_pad - fade_steps
        if remaining_pad > 0 then
          local current_config = config_facade.get(bufnr)
          local line_hl = current_config.line_highlights
              and current_config.line_highlights.enabled
              and roles.highlight_group("FlemmaLine", entry.msg.role)
            or "Normal"
          table.insert(prompt_chunks, { string.rep(" ", remaining_pad), line_hl })
        end
      end

      vim.api.nvim_buf_set_extmark(bufnr, tool_approval_ns, line_idx, 0, {
        virt_lines = { prompt_chunks },
      })
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

  M.setup_fence_decoration_provider()

  -- Restore the original conceal_lines behaviour for markdown buffers that
  -- were opened after the conceal patch stripped the query. Their highlighter
  -- was constructed without _conceal_line, so fence delimiters stay visible
  -- at conceallevel >= 2. A "sandwich restart" (set original query → stop/start
  -- → set stripped query) gives each markdown buffer its own cached copy of the
  -- original query with conceal_lines metadata intact. Idempotent — only
  -- restarts once per buffer (subsequent entries see _conceal_line = true).
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = augroup,
    desc = "Flemma: restore conceal_lines in treesitter highlighter for markdown buffers",
    callback = function(ev)
      if not highlight.is_fence_conceal_patched() then
        return
      end
      local bufnr = ev.buf
      if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype ~= "markdown" then
        return
      end
      highlight.restore_highlighter_conceal(bufnr)
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
        keybind_hints_cache[ev.buf] = nil
        -- state.cleanup_buffer_state handles executor.cleanup_buffer internally
        state.cleanup_buffer_state(ev.buf)
      end
    end,
  })
end

return M
