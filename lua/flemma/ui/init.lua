--- UI module for Flemma plugin
--- Handles visual presentation: rulers, spinners, folding, and signs
---@class flemma.UI
local M = {}

local log = require("flemma.logging")
local state = require("flemma.state")
local config = require("flemma.config")
local buffer_utils = require("flemma.utilities.buffer")
local preview = require("flemma.ui.preview")
local folding = require("flemma.ui.folding")
local roles = require("flemma.utilities.roles")
local callbacks = require("flemma.core.callbacks")
local migration = require("flemma.migration")
local parser = require("flemma.parser")
local writequeue = require("flemma.buffer.writequeue")

-- Extmark priority constants
-- Higher values take precedence when multiple extmarks overlap on the same line.
-- The hierarchy from lowest to highest:
--   1. LINE_HIGHLIGHT (50)      - Base backgrounds for messages and frontmatter
--   2. THINKING_BLOCK (100)     - Thinking block backgrounds, overrides message line highlights
--   3. CURSORLINE (125)         - CursorLine overlay, blends with underlying line highlights
--   4. THINKING_TAG (200)       - Text styling for <thinking> and </thinking> tags
--   5. SPINNER (300)            - Spinner line, highest priority to suppress spell checking
local PRIORITY = {
  LINE_HIGHLIGHT = 50,
  THINKING_BLOCK = 100,
  CURSORLINE = 125,
  THINKING_TAG = 200,
  TOOL_EXECUTION = 250,
  SPINNER = 300,
}

local SPINNER_LABEL = "Thinking…"

-- Define namespace for our extmarks
local ns_id = vim.api.nvim_create_namespace("flemma")
local spinner_ns = vim.api.nvim_create_namespace("flemma_spinner")
local line_hl_ns = vim.api.nvim_create_namespace("flemma_line_highlights")
local cursorline_ns = vim.api.nvim_create_namespace("flemma_cursorline")
local thinking_ns = vim.api.nvim_create_namespace("flemma_thinking_tags")
local tool_exec_ns = vim.api.nvim_create_namespace("flemma_tool_execution")
local tool_preview_ns = vim.api.nvim_create_namespace("flemma_tool_preview")

---@class flemma.ui.ToolIndicator
---@field extmark_id integer
---@field timer integer|nil

---Get or initialize the tool indicators table for a buffer
---@param bufnr integer
---@return table<string, flemma.ui.ToolIndicator>
local function get_tool_indicators(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  if not buffer_state.tool_indicators then
    buffer_state.tool_indicators = {}
  end
  return buffer_state.tool_indicators
end

--- Execute a command in the context of a buffer's window
---@param bufnr number Buffer number
---@param cmd string Command to execute
function M.buffer_cmd(bufnr, cmd)
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return
  end
  vim.fn.win_execute(winid, "noautocmd " .. cmd)
end

---Add rulers merged with role marker lines
---@param bufnr integer
---@param doc flemma.ast.DocumentNode
function M.add_rulers(bufnr, doc)
  -- Clear existing extmarks
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  local current_config = state.get_config()
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

  local spinner_line = state.get_buffer_state(bufnr).spinner_line_idx0

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

      -- On the spinner line, only replace : with a space (no ruler extension)
      -- so the EOL spinner text isn't covered by overlay chars.
      -- On all other lines, extend ruler chars to the window edge.
      if line_idx == spinner_line then
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

---Build spinner virt_text chunks, appending ruler chars when rulers are enabled.
---@param spinner_text string The spinner frame + label text
---@param bufnr integer
---@return {[1]:string, [2]:string}[]
local function build_spinner_virt_text(spinner_text, bufnr)
  local current_config = state.get_config()
  local ruler_config = current_config.ruler
  local rulers_enabled = ruler_config and ruler_config.enabled ~= false

  -- When rulers are off, the colon overlay isn't present, so add a leading space
  local prefix = rulers_enabled and "" or " "
  ---@type {[1]:string, [2]:string}[]
  local chunks = { { prefix .. spinner_text, "FlemmaAssistantSpinner" } }

  if rulers_enabled then
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      -- Use win_width chars — the window clips excess, so overshoot is fine
      local win_width = vim.api.nvim_win_get_width(winid)
      table.insert(chunks, { " " .. string.rep(ruler_config.char, win_width), "FlemmaRuler" })
    end
  end

  return chunks
end

---Show loading spinner
---@param bufnr integer
---@return integer timer_id
function M.start_loading_spinner(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local frame = 1
  local spinner_line_idx0 = nil
  local spinner_extmark_id = nil

  writequeue.schedule(bufnr, function()
    buffer_utils.with_modifiable(bufnr, function()
      -- Clear any existing virtual text
      vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
      vim.api.nvim_buf_clear_namespace(bufnr, spinner_ns, 0, -1)

      -- Write @Assistant: on its own line so the parser recognises it as a message
      local last_line = buffer_utils.get_last_line(bufnr)
      if last_line:match("%S") then
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "", "@Assistant:" })
      else
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "@Assistant:" })
      end

      -- Track the spinner line position and create the animated extmark.
      -- "Thinking…" is virtual text so the buffer line stays as just "@Assistant:"
      -- which the parser can recognise as a role marker.
      -- hl_mode="combine" lets the spinner inherit line highlights (from apply_line_highlights, cursorline, etc.)
      spinner_line_idx0 = vim.api.nvim_buf_line_count(bufnr) - 1
      local spinner_text = spinner_frames[frame] .. " " .. SPINNER_LABEL
      spinner_extmark_id = vim.api.nvim_buf_set_extmark(bufnr, spinner_ns, spinner_line_idx0, 0, {
        virt_text = build_spinner_virt_text(spinner_text, bufnr),
        virt_text_pos = "eol",
        hl_mode = "combine",
        priority = PRIORITY.SPINNER,
        spell = false,
      })

      -- Expose extmark info so the timer and update_thinking_preview can coordinate
      buffer_state.spinner_extmark_id = spinner_extmark_id
      buffer_state.spinner_line_idx0 = spinner_line_idx0
      buffer_state.spinner_preview_text = nil

      -- Immediately update UI after adding the thinking message
      M.update_ui(bufnr)
      -- Move to bottom and center the line so user sees the message
      M.move_to_bottom(bufnr)
      M.center_cursor(bufnr)
    end)
  end)

  local timer = vim.fn.timer_start(100, function()
    if not buffer_state.current_request then
      return
    end

    -- Only update the extmark — no buffer modification needed.
    -- The timer owns all extmark updates; update_thinking_preview just sets
    -- buffer_state.spinner_preview_text for the timer to pick up.
    if spinner_line_idx0 ~= nil and spinner_extmark_id ~= nil then
      frame = (frame % #spinner_frames) + 1
      local preview_text = buffer_state.spinner_preview_text
      local label = preview_text and SPINNER_LABEL .. "  (" .. preview_text .. ")" or SPINNER_LABEL
      local spinner_text = spinner_frames[frame] .. " " .. label
      pcall(vim.api.nvim_buf_set_extmark, bufnr, spinner_ns, spinner_line_idx0, 0, {
        id = spinner_extmark_id,
        virt_text = build_spinner_virt_text(spinner_text, bufnr),
        virt_text_pos = "eol",
        hl_mode = "combine",
        priority = PRIORITY.SPINNER,
        spell = false,
      })
    end
  end, { ["repeat"] = -1 })

  buffer_state.spinner_timer = timer
  return timer
end

---Clean up spinner and prepare for response
---@param bufnr integer
function M.cleanup_spinner(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  buffer_utils.with_modifiable(bufnr, function()
    local buffer_state = state.get_buffer_state(bufnr)
    if buffer_state.spinner_timer then
      vim.fn.timer_stop(buffer_state.spinner_timer)
      buffer_state.spinner_timer = nil
    end

    -- Clear spinner/thinking preview state
    buffer_state.spinner_extmark_id = nil
    buffer_state.spinner_line_idx0 = nil
    buffer_state.spinner_preview_text = nil

    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1) -- Clear rulers/virtual text
    vim.api.nvim_buf_clear_namespace(bufnr, spinner_ns, 0, -1) -- Remove spinner suppression

    local last_line_content, line_count = buffer_utils.get_last_line(bufnr)
    if line_count == 0 then
      M.update_ui(bufnr) -- Ensure UI is clean even if buffer is empty
      return
    end

    -- Only modify lines if the last line is the empty @Assistant: spinner placeholder.
    -- "Thinking…" is now virtual text, so the buffer line is just "@Assistant:".
    if last_line_content and last_line_content == "@Assistant:" then
      M.buffer_cmd(bufnr, "undojoin") -- Group changes for undo

      -- Get the line before the "@Assistant:" marker (if it exists)
      local prev_line_actual_content = nil
      if line_count > 1 then
        prev_line_actual_content = buffer_utils.get_line(bufnr, line_count - 1)
      end

      -- Ensure we maintain a blank line if needed, or remove the spinner line
      if prev_line_actual_content and prev_line_actual_content:match("%S") then
        -- Previous line has content, replace spinner line with a blank line
        vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count, false, { "" })
      else
        -- Previous line is blank or doesn't exist, remove the spinner line entirely
        vim.api.nvim_buf_set_lines(bufnr, line_count - 1, line_count, false, {})
      end
    else
      log.debug("cleanup_spinner(): Last line is not the spinner placeholder, not modifying lines.")
    end

    M.update_ui(bufnr) -- Force UI update after cleaning up spinner
  end)
end

---Store thinking preview text for the spinner timer to render.
---The timer owns all extmark updates so the animation stays smooth.
---@param bufnr integer
---@param preview_text string Truncated preview to display (e.g. "329 characters")
function M.update_thinking_preview(bufnr, preview_text)
  local buffer_state = state.get_buffer_state(bufnr)
  buffer_state.spinner_preview_text = preview_text
end

---Place signs for a message
---@param bufnr integer
---@param start_line integer
---@param end_line integer
---@param role string
function M.place_signs(bufnr, start_line, end_line, role)
  local current_config = state.get_config()
  if not current_config.signs.enabled then
    return
  end

  -- Map the display role to the internal config key
  local internal_role_key = roles.to_key(role)

  local sign_name = "flemma_" .. internal_role_key -- Construct sign name like "flemma_user"
  local sign_config = current_config.signs[internal_role_key] -- Look up config using "user", "system", etc.

  -- Check if the sign is actually defined before trying to place it
  if vim.tbl_isempty(vim.fn.sign_getdefined(sign_name)) then
    log.debug("place_signs(): Sign not defined: " .. sign_name .. " for role " .. role)
    return
  end

  if sign_config and sign_config.hl ~= false then
    for lnum = start_line, end_line do
      vim.fn.sign_place(0, "flemma_ns", sign_name, bufnr, { lnum = lnum })
    end
  end
end

---Apply full-line background highlighting for messages and frontmatter
---@param bufnr integer
---@param doc flemma.ast.DocumentNode
function M.apply_line_highlights(bufnr, doc)
  local current_config = state.get_config()
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

---Apply buffer-local settings for chat files
---@param bufnr? integer Buffer number, defaults to current buffer
local function apply_chat_buffer_settings(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  folding.setup_folding(bufnr)

  if config.editing.disable_textwidth then
    vim.bo[bufnr].textwidth = 0
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
    callback = function(ev)
      migration.migrate_buffer(ev.buf)
      vim.bo[ev.buf].filetype = "chat"
      apply_chat_buffer_settings(ev.buf)
    end,
  })

  -- Handle manual filetype changes to 'chat'
  vim.api.nvim_create_autocmd("FileType", {
    group = augroup,
    pattern = "chat",
    callback = function(ev)
      apply_chat_buffer_settings(ev.buf)
    end,
  })

  -- Handle updatetime management for chat buffers
  if config.editing.manage_updatetime then
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
  local current_config = state.get_config()
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

---Add virtual line previews inside empty flemma:tool fenced blocks
---Shows a compact summary of the tool call (name + input) so users can see
---what they're approving/rejecting without the content being editable.
---@param bufnr integer
---@param doc flemma.ast.DocumentNode
function M.add_tool_previews(bufnr, doc)
  vim.api.nvim_buf_clear_namespace(bufnr, tool_preview_ns, 0, -1)

  -- Build tool_use lookup: id -> ToolUseSegment
  ---@type table<string, flemma.ast.ToolUseSegment>
  local tool_use_map = {}
  for _, msg in ipairs(doc.messages) do
    if msg.role == "Assistant" then
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "tool_use" then
          tool_use_map[seg.id] = seg --[[@as flemma.ast.ToolUseSegment]]
        end
      end
    end
  end

  -- Compute available text width from the buffer's window
  local winid = vim.fn.bufwinid(bufnr)
  local max_length = preview.get_text_area_width(winid)

  local line_count = vim.api.nvim_buf_line_count(bufnr)

  -- Find tool_result segments with status and empty content
  for _, msg in ipairs(doc.messages) do
    if roles.is_user(msg.role) then
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "tool_result" and seg.status and seg.content == "" then
          local tool_use = tool_use_map[seg.tool_use_id]
          if tool_use then
            -- Opening fence is one line before closing fence (empty content)
            local opening_fence_line = seg.position.end_line - 1
            local line_idx = opening_fence_line - 1 -- 0-indexed

            if line_idx >= 0 and line_idx < line_count then
              local preview_text = preview.format_tool_preview(tool_use.name, tool_use.input, max_length)
              vim.api.nvim_buf_set_extmark(bufnr, tool_preview_ns, line_idx, 0, {
                virt_lines = { { { preview_text, "FlemmaToolPreview" } } },
              })
            end
          end
        end
      end
    end
  end
end

---Force UI update (rulers, signs, and line highlights)
---@param bufnr integer
function M.update_ui(bufnr)
  -- Ensure buffer is valid before proceeding
  if not vim.api.nvim_buf_is_valid(bufnr) then
    log.debug("update_ui(): Invalid buffer: " .. bufnr)
    return
  end

  -- Bail if config is not fully initialized (e.g. in test environments)
  local current_config = state.get_config()
  if not current_config.ruler or not current_config.signs then
    return
  end

  -- Parse messages using AST
  local doc = parser.get_parsed_document(bufnr)

  M.add_rulers(bufnr, doc)
  M.highlight_thinking_tags(bufnr, doc)
  M.apply_line_highlights(bufnr, doc)
  M.add_tool_previews(bufnr, doc)
  -- Note: spinner extmark (with suppression) is managed by start_loading_spinner and its timer

  -- Re-apply CursorLine overlay now that line highlights are refreshed,
  -- so the blend reflects the current AST state instead of the pre-edit state.
  update_cursorline(bufnr)

  folding.invalidate_folds(bufnr)
  folding.fold_completed_blocks(bufnr)

  -- Clear and reapply all signs
  vim.fn.sign_unplace("flemma_ns", { buffer = bufnr })

  -- Place signs for each message based on AST positions
  for _, msg in ipairs(doc.messages) do
    M.place_signs(bufnr, msg.position.start_line, msg.position.end_line, msg.role)
  end
end

---Move cursor to end of buffer
---@param bufnr? integer If provided, moves cursor in the window displaying that buffer
function M.move_to_bottom(bufnr)
  if bufnr then
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      vim.fn.win_execute(winid, "normal! G")
    end
    return
  end
  vim.cmd("normal! G")
end

---Center cursor line in window
---@param bufnr? integer If provided, centers cursor in the window displaying that buffer
function M.center_cursor(bufnr)
  if bufnr then
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      vim.fn.win_execute(winid, "normal! zz")
    end
    return
  end
  vim.cmd("normal! zz")
end

---Move cursor to specific position
---@param line integer
---@param col integer
---@param bufnr? integer
function M.set_cursor(line, col, bufnr)
  if bufnr then
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      vim.api.nvim_win_set_cursor(winid, { line, col })
    end
    return
  end
  vim.api.nvim_win_set_cursor(0, { line, col })
end

-- ============================================================================
-- Tool Execution Indicators
-- ============================================================================

local TOOL_SPINNER_FRAMES = { "◐", "◓", "◑", "◒" }

--- Get the current line of a tool execution extmark (auto-adjusted by Neovim)
---@param bufnr integer
---@param extmark_id integer
---@return integer|nil 0-based line index, or nil if extmark not found
local function get_extmark_line(bufnr, extmark_id)
  local ok, pos = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, tool_exec_ns, extmark_id, {})
  if ok and pos and #pos >= 1 then
    return pos[1]
  end
  return nil
end

--- Show pending-approval indicator for a tool
--- Creates a static extmark (no spinner) at the tool result header line.
--- Automatically replaced when `show_tool_indicator` starts the execution spinner.
---@param bufnr integer
---@param tool_id string
---@param header_line integer 1-based line number of the tool result header
function M.show_pending_tool_indicator(bufnr, tool_id, header_line)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  M.clear_tool_indicator(bufnr, tool_id)

  local line_idx = header_line - 1

  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, tool_exec_ns, line_idx, 0, {
    virt_text = { { " ● Pending", "FlemmaToolPending" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
    priority = PRIORITY.TOOL_EXECUTION,
    spell = false,
  })

  get_tool_indicators(bufnr)[tool_id] = {
    extmark_id = extmark_id,
    timer = nil,
  }
end

--- Show execution indicator for a tool
--- Creates extmark with animated spinner at the tool result header line
---@param bufnr integer
---@param tool_id string
---@param header_line integer 1-based line number of the tool result header
function M.show_tool_indicator(bufnr, tool_id, header_line)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Clean up any existing indicator for this tool
  M.clear_tool_indicator(bufnr, tool_id)

  local line_idx = header_line - 1
  local frame = 1

  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, tool_exec_ns, line_idx, 0, {
    virt_text = { { " " .. TOOL_SPINNER_FRAMES[frame] .. " Executing…", "FlemmaToolPending" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
    priority = PRIORITY.TOOL_EXECUTION,
    spell = false,
  })

  local timer ---@type integer
  timer = vim.fn.timer_start(100, function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      -- Buffer gone — stop ourselves; buffer state cleanup may have already run
      vim.fn.timer_stop(timer)
      return
    end

    local indicators = get_tool_indicators(bufnr)
    local ind = indicators[tool_id]
    if not ind then
      return
    end

    local current_line = get_extmark_line(bufnr, ind.extmark_id)
    if not current_line then
      return
    end

    frame = (frame % #TOOL_SPINNER_FRAMES) + 1
    pcall(vim.api.nvim_buf_set_extmark, bufnr, tool_exec_ns, current_line, 0, {
      id = ind.extmark_id,
      virt_text = { { " " .. TOOL_SPINNER_FRAMES[frame] .. " Executing…", "FlemmaToolPending" } },
      virt_text_pos = "eol",
      hl_mode = "combine",
      priority = PRIORITY.TOOL_EXECUTION,
      spell = false,
    })
  end, { ["repeat"] = -1 })

  get_tool_indicators(bufnr)[tool_id] = {
    extmark_id = extmark_id,
    timer = timer,
  }
end

--- Update indicator to show completion/error state
--- Stops animation, shows final state
---@param bufnr integer
---@param tool_id string
---@param success boolean
function M.update_tool_indicator(bufnr, tool_id, success)
  local indicators = get_tool_indicators(bufnr)
  local ind = indicators[tool_id]
  if not ind then
    return
  end

  -- Stop animation timer
  if ind.timer then
    vim.fn.timer_stop(ind.timer)
    ind.timer = nil
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    indicators[tool_id] = nil
    return
  end

  -- Query extmark's current position (may have shifted due to buffer edits)
  local current_line = get_extmark_line(bufnr, ind.extmark_id)
  if not current_line then
    indicators[tool_id] = nil
    return
  end

  -- Show final state
  local text, hl
  if success then
    text = " ✓ Complete"
    hl = "FlemmaToolSuccess"
  else
    text = " ✗ Failed"
    hl = "FlemmaToolError"
  end

  pcall(vim.api.nvim_buf_set_extmark, bufnr, tool_exec_ns, current_line, 0, {
    id = ind.extmark_id,
    virt_text = { { text, hl } },
    virt_text_pos = "eol",
    hl_mode = "combine",
    priority = PRIORITY.TOOL_EXECUTION,
    spell = false,
  })
end

--- Clear indicator for a tool (removes extmark and stops timer)
---@param bufnr integer
---@param tool_id string
function M.clear_tool_indicator(bufnr, tool_id)
  local indicators = get_tool_indicators(bufnr)
  local ind = indicators[tool_id]
  if not ind then
    return
  end

  if ind.timer then
    vim.fn.timer_stop(ind.timer)
  end

  if vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, tool_exec_ns, ind.extmark_id)
  end

  indicators[tool_id] = nil
end

--- Reposition all tool indicators to their correct header lines after buffer modification.
--- When inject_placeholder or inject_result replaces lines containing an extmark,
--- Neovim pushes that extmark to the start of the replacement range, which may be
--- a different tool's header. This function uses the AST to find each tool_result's
--- actual position and moves the extmark there.
---@param bufnr integer
function M.reposition_tool_indicators(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Build tool_use_id → start_line map from AST
  local doc = parser.get_parsed_document(bufnr)
  local result_positions = {}
  for _, msg in ipairs(doc.messages) do
    if roles.is_user(msg.role) then
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "tool_result" then
          result_positions[seg.tool_use_id] = seg.position.start_line - 1 -- 0-based
        end
      end
    end
  end

  local indicators = get_tool_indicators(bufnr)
  for tool_id, ind in pairs(indicators) do
    local target_line = result_positions[tool_id]
    if target_line then
      local current_line = get_extmark_line(bufnr, ind.extmark_id)
      if current_line and current_line ~= target_line then
        -- Read current virtual text to preserve it during repositioning
        local ok, pos =
          pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, tool_exec_ns, ind.extmark_id, { details = true })
        if ok and pos and #pos >= 3 then
          pcall(vim.api.nvim_buf_set_extmark, bufnr, tool_exec_ns, target_line, 0, {
            id = ind.extmark_id,
            virt_text = pos[3].virt_text,
            virt_text_pos = "eol",
            hl_mode = "combine",
            priority = PRIORITY.TOOL_EXECUTION,
            spell = false,
          })
        end
      end
    end
  end
end

--- Schedule indicator clear after a delay, or immediately on user edit
--- Uses extmark_id guard to avoid clearing a newer indicator if tool is re-executed.
--- The on_lines listener only fires when the buffer is idle (not locked by tool
--- execution and no active API request), so programmatic edits from other tool
--- completions or streaming responses won't prematurely dismiss the indicator.
---@param bufnr integer
---@param tool_id string
---@param delay_ms integer Milliseconds to wait before clearing
function M.schedule_tool_indicator_clear(bufnr, tool_id, delay_ms)
  local indicators = get_tool_indicators(bufnr)
  local ind = indicators[tool_id]
  if not ind then
    return
  end
  local expected_extmark = ind.extmark_id
  local cleared = false

  local function do_clear()
    if cleared then
      return
    end
    local current = get_tool_indicators(bufnr)[tool_id]
    if not current or current.extmark_id ~= expected_extmark then
      cleared = true
      return -- indicator was replaced by re-execution
    end
    cleared = true
    M.clear_tool_indicator(bufnr, tool_id)
  end

  vim.defer_fn(function()
    do_clear()
  end, delay_ms)

  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_attach(bufnr, false, {
      on_lines = function()
        -- Ignore programmatic edits: tool result injection (buffer locked) and
        -- streaming responses (active API request). Only dismiss on user edits.
        local buffer_state = state.get_buffer_state(bufnr)
        if buffer_state.locked or buffer_state.current_request then
          return
        end
        vim.schedule(function()
          do_clear()
        end)
        return true -- detach after first user edit
      end,
    })
  end
end

--- Clear all tool indicators for a buffer (used on buffer cleanup)
---@param bufnr integer
function M.clear_all_tool_indicators(bufnr)
  local indicators = get_tool_indicators(bufnr)
  local to_clear = {}
  for tool_id in pairs(indicators) do
    table.insert(to_clear, tool_id)
  end

  for _, tool_id in ipairs(to_clear) do
    M.clear_tool_indicator(bufnr, tool_id)
  end

  -- Also clear the namespace for this buffer
  if vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, tool_exec_ns, 0, -1)
  end
end

---Set up UI-related autocmds and initialization
function M.setup()
  -- Create or clear the augroup for UI-related autocmds
  local augroup = vim.api.nvim_create_augroup("FlemmaUI", { clear = true })

  -- Add autocmd for updating rulers and signs (debounced via CursorHold)
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
      callbacks.update_ui(ev.buf)
      buffer_state.ui_update_tick = tick
    end,
  })

  -- Ensure buffer-local state gets cleaned up when chat buffers are removed.
  -- This prevents leaking timers or jobs if a buffer is deleted while a request/spinner is active.
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload", "BufDelete" }, {
    group = augroup,
    pattern = "*",
    callback = function(ev)
      if vim.bo[ev.buf].filetype == "chat" or string.match(vim.api.nvim_buf_get_name(ev.buf), "%.chat$") then
        M.cleanup_spinner(ev.buf)
        M.clear_all_tool_indicators(ev.buf)
        -- state.cleanup_buffer_state handles executor.cleanup_buffer internally
        state.cleanup_buffer_state(ev.buf)
      end
    end,
  })
end

return M
