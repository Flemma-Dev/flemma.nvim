--- UI module for Flemma plugin
--- Handles visual presentation: rulers, spinners, folding, and signs
---@class flemma.UI
local M = {}

local log = require("flemma.logging")
local state = require("flemma.state")
local config = require("flemma.config")
local preview = require("flemma.ui.preview")

-- Extmark priority constants
-- Higher values take precedence when multiple extmarks overlap on the same line.
-- The hierarchy from lowest to highest:
--   1. LINE_HIGHLIGHT (50)      - Base backgrounds for messages and frontmatter
--   2. THINKING_BLOCK (100)     - Thinking block backgrounds, overrides message line highlights
--   3. THINKING_TAG (200)       - Text styling for <thinking> and </thinking> tags
--   4. SPINNER (300)            - Spinner line, highest priority to suppress spell checking
local PRIORITY = {
  LINE_HIGHLIGHT = 50,
  THINKING_BLOCK = 100,
  THINKING_TAG = 200,
  TOOL_EXECUTION = 250,
  SPINNER = 300,
}

-- Define namespace for our extmarks
local ns_id = vim.api.nvim_create_namespace("flemma")
local spinner_ns = vim.api.nvim_create_namespace("flemma_spinner")
local line_hl_ns = vim.api.nvim_create_namespace("flemma_line_highlights")
local tool_exec_ns = vim.api.nvim_create_namespace("flemma_tool_execution")
local tool_preview_ns = vim.api.nvim_create_namespace("flemma_tool_preview")

--- Per-tool indicator state: key(bufnr, tool_id) -> { extmark_id, timer, bufnr, tool_id }
local tool_indicators = {}

local function indicator_key(bufnr, tool_id)
  return tostring(bufnr) .. ":" .. tool_id
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

---Add rulers between messages
---@param bufnr integer
---@param doc flemma.ast.DocumentNode
function M.add_rulers(bufnr, doc)
  -- Clear existing extmarks
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  local ruler_config = state.get_config().ruler
  if ruler_config.enabled == false then
    return
  end

  -- Get the window displaying this buffer to calculate correct ruler width
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    -- Buffer not displayed in any window, skip rulers
    return
  end

  local win_width = vim.api.nvim_win_get_width(winid)

  for i, msg in ipairs(doc.messages) do
    -- Add a ruler before each message after the first, and before the first if frontmatter exists
    if i > 1 or (i == 1 and doc.frontmatter ~= nil) then
      local line_idx = msg.position.start_line - 1
      if line_idx >= 0 and line_idx < vim.api.nvim_buf_line_count(bufnr) then
        -- Create virtual line with ruler using the FlemmaRuler highlight group
        local ruler_text = string.rep(ruler_config.char, win_width)
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_idx, 0, {
          virt_lines = { { { ruler_text, "FlemmaRuler" } } }, -- Use defined group
          virt_lines_above = true,
        })
      end
    end
  end
end

---Highlight thinking tags and blocks using extmarks (higher priority than Treesitter)
---@param bufnr integer
---@param doc flemma.ast.DocumentNode
function M.highlight_thinking_tags(bufnr, doc)
  local thinking_ns = vim.api.nvim_create_namespace("flemma_thinking_tags")

  -- Clear existing thinking tag highlights
  vim.api.nvim_buf_clear_namespace(bufnr, thinking_ns, 0, -1)

  local line_count = vim.api.nvim_buf_line_count(bufnr)

  -- Iterate through messages and their segments to find thinking blocks
  for _, msg in ipairs(doc.messages) do
    if msg.segments then
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "thinking" and seg.position then
          -- Apply line background highlight to the entire thinking block
          for lnum = seg.position.start_line, seg.position.end_line do
            local line_idx = lnum - 1
            if line_idx >= 0 and line_idx < line_count then
              vim.api.nvim_buf_set_extmark(bufnr, thinking_ns, line_idx, 0, {
                line_hl_group = "FlemmaThinkingBlock",
                priority = PRIORITY.THINKING_BLOCK,
              })
            end
          end

          -- Highlight opening tag text
          vim.api.nvim_buf_set_extmark(bufnr, thinking_ns, seg.position.start_line - 1, 0, {
            end_line = seg.position.start_line,
            hl_group = "FlemmaThinkingTag",
            priority = PRIORITY.THINKING_TAG,
          })
          -- Highlight closing tag text
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

---Show loading spinner
---@param bufnr integer
---@return integer timer_id
function M.start_loading_spinner(bufnr)
  local original_modifiable_initial = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true -- Allow plugin modifications for initial message

  local buffer_state = state.get_buffer_state(bufnr)
  local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local frame = 1
  local spinner_line_idx0 = nil
  local spinner_extmark_id = nil

  vim.schedule(function()
    -- Clear any existing virtual text
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, spinner_ns, 0, -1)

    -- Check if we need to add a blank line before the spinner
    vim.bo[bufnr].modifiable = true
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local last_line = line_count > 0 and vim.api.nvim_buf_get_lines(bufnr, line_count - 1, line_count, false)[1] or ""
    if last_line:match("%S") then
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "", "@Assistant: Thinking…" })
    else
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "@Assistant: Thinking…" })
    end

    -- Track the spinner line position and create the animated extmark
    -- hl_mode="combine" lets the spinner inherit line highlights (from apply_line_highlights, cursorline, etc.)
    spinner_line_idx0 = vim.api.nvim_buf_line_count(bufnr) - 1
    spinner_extmark_id = vim.api.nvim_buf_set_extmark(bufnr, spinner_ns, spinner_line_idx0, 0, {
      virt_text = { { " " .. spinner_frames[frame], "FlemmaAssistantSpinner" } },
      virt_text_pos = "eol",
      hl_mode = "combine",
      priority = PRIORITY.SPINNER,
      spell = false,
    })

    -- Expose extmark info so update_thinking_preview can update it
    buffer_state.spinner_extmark_id = spinner_extmark_id
    buffer_state.spinner_line_idx0 = spinner_line_idx0

    -- Immediately update UI after adding the thinking message
    M.update_ui(bufnr)
    -- Move to bottom and center the line so user sees the message
    M.move_to_bottom(bufnr)
    M.center_cursor(bufnr)
    vim.bo[bufnr].modifiable = original_modifiable_initial
  end)

  local timer = vim.fn.timer_start(100, function()
    if not buffer_state.current_request then
      return
    end

    -- Only update the extmark - no buffer modification needed
    if spinner_line_idx0 ~= nil and spinner_extmark_id ~= nil then
      frame = (frame % #spinner_frames) + 1
      vim.api.nvim_buf_set_extmark(bufnr, spinner_ns, spinner_line_idx0, 0, {
        id = spinner_extmark_id,
        virt_text = { { " " .. spinner_frames[frame], "FlemmaAssistantSpinner" } },
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

  local original_modifiable = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true -- Allow plugin modifications

  local buffer_state = state.get_buffer_state(bufnr)
  if buffer_state.spinner_timer then
    vim.fn.timer_stop(buffer_state.spinner_timer)
    buffer_state.spinner_timer = nil
  end

  -- Clear thinking preview extmark references
  buffer_state.spinner_extmark_id = nil
  buffer_state.spinner_line_idx0 = nil

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1) -- Clear rulers/virtual text
  vim.api.nvim_buf_clear_namespace(bufnr, spinner_ns, 0, -1) -- Remove spinner suppression

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    M.update_ui(bufnr) -- Ensure UI is clean even if buffer is empty
    vim.bo[bufnr].modifiable = original_modifiable -- Restore modifiable before return
    return
  end

  local last_line_content = vim.api.nvim_buf_get_lines(bufnr, line_count - 1, line_count, false)[1]

  -- Only modify lines if the last line is exactly the thinking message (spinner is now virtual text)
  if last_line_content and last_line_content == "@Assistant: Thinking…" then
    M.buffer_cmd(bufnr, "undojoin") -- Group changes for undo

    -- Get the line before the "Thinking…" message (if it exists)
    local prev_line_actual_content = nil
    if line_count > 1 then
      prev_line_actual_content = vim.api.nvim_buf_get_lines(bufnr, line_count - 2, line_count - 1, false)[1]
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
    log.debug("cleanup_spinner(): Last line is not the 'Thinking…' message, not modifying lines.")
  end

  M.update_ui(bufnr) -- Force UI update after cleaning up spinner
  vim.bo[bufnr].modifiable = original_modifiable -- Restore previous modifiable state
end

---Update the spinner extmark with a live thinking preview
---Replaces the spinning animation with a rolling snippet of thinking content
---@param bufnr integer
---@param preview_text string Truncated preview to display
function M.update_thinking_preview(bufnr, preview_text)
  local buffer_state = state.get_buffer_state(bufnr)
  local extmark_id = buffer_state.spinner_extmark_id
  local line_idx0 = buffer_state.spinner_line_idx0
  if not extmark_id or not line_idx0 then
    return
  end

  vim.api.nvim_buf_set_extmark(bufnr, spinner_ns, line_idx0, 0, {
    id = extmark_id,
    virt_text = { { " " .. config.spinner.thinking_char .. " (" .. preview_text .. ")", "FlemmaAssistantSpinner" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
    priority = PRIORITY.SPINNER,
    spell = false,
  })
end

---Fold the last thinking block in a buffer
---@param bufnr integer
function M.fold_last_thinking_block(bufnr)
  log.debug("fold_last_thinking_block(): Attempting to fold last thinking block in buffer " .. bufnr)

  local parser = require("flemma.parser")
  local doc = parser.get_parsed_document(bufnr)

  if #doc.messages == 0 then
    log.debug("fold_last_thinking_block(): No messages found in buffer.")
    return
  end

  local last_message = doc.messages[#doc.messages]

  if last_message.role ~= "You" then
    log.debug("fold_last_thinking_block(): Last message is not from @You:. Aborting.")
    return
  end

  if #doc.messages < 2 then
    log.debug("fold_last_thinking_block(): Not enough messages to have a thinking block before @You:.")
    return
  end

  local second_to_last = doc.messages[#doc.messages - 1]

  -- Find thinking segment in the second-to-last message's segments
  local thinking_segment = nil
  for _, segment in ipairs(second_to_last.segments) do
    if segment.kind == "thinking" then
      thinking_segment = segment
      break
    end
  end

  if not thinking_segment then
    log.debug("fold_last_thinking_block(): No thinking block found in the second-to-last message.")
    return
  end

  if not thinking_segment.position then
    log.debug("fold_last_thinking_block(): Thinking segment missing position information.")
    return
  end

  local start_lnum_1idx = thinking_segment.position.start_line
  local end_lnum_1idx = thinking_segment.position.end_line

  log.debug(
    string.format(
      "fold_last_thinking_block(): Found thinking block from line %d to %d (1-indexed). Closing fold.",
      start_lnum_1idx,
      end_lnum_1idx
    )
  )

  local winid = vim.fn.bufwinid(bufnr)
  if winid ~= -1 then
    local fold_exists = vim.fn.win_execute(winid, string.format("echo foldlevel(%d)", start_lnum_1idx))
    if tonumber(vim.trim(fold_exists)) and tonumber(vim.trim(fold_exists)) > 0 then
      -- Check if the fold is already closed (e.g. by foldlevel setting).
      -- Running foldclose on an already-closed nested fold escalates to closing the parent fold.
      local already_closed = vim.fn.win_execute(winid, string.format("echo foldclosed(%d)", start_lnum_1idx))
      if tonumber(vim.trim(already_closed)) ~= -1 then
        log.debug(
          "fold_last_thinking_block(): Fold already closed at line " .. start_lnum_1idx .. ". Skipping foldclose."
        )
      else
        vim.fn.win_execute(winid, string.format("%d,%d foldclose", start_lnum_1idx, end_lnum_1idx))
        log.debug("fold_last_thinking_block(): Executed foldclose command via win_execute.")
      end
    else
      log.debug("fold_last_thinking_block(): No fold exists at line " .. start_lnum_1idx .. ". Skipping foldclose.")
    end
  else
    log.debug("fold_last_thinking_block(): Buffer " .. bufnr .. " has no window. Cannot close fold.")
  end
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

  -- Map the display role ("You", "System", "Assistant") to the internal config key ("user", "system", "assistant")
  local internal_role_key = string.lower(role) -- Default to lowercase
  if role == "You" then
    internal_role_key = "user" -- Map "You" specifically to "user"
  end

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

  local line_count = vim.api.nvim_buf_line_count(bufnr)

  -- Highlight frontmatter if present
  if doc.frontmatter and doc.frontmatter.position then
    for lnum = doc.frontmatter.position.start_line, doc.frontmatter.position.end_line do
      local line_idx = lnum - 1
      if line_idx >= 0 and line_idx < line_count then
        vim.api.nvim_buf_set_extmark(bufnr, line_hl_ns, line_idx, 0, {
          line_hl_group = "FlemmaLineFrontmatter",
          priority = PRIORITY.LINE_HIGHLIGHT,
        })
      end
    end
  end

  -- Highlight messages
  for _, msg in ipairs(doc.messages) do
    -- Map the display role to internal config key
    local internal_role_key = string.lower(msg.role)
    if msg.role == "You" then
      internal_role_key = "user"
    end

    -- Construct highlight group name (e.g., "FlemmaLineUser")
    local hl_group = "FlemmaLine" .. internal_role_key:sub(1, 1):upper() .. internal_role_key:sub(2)

    -- Apply line highlight to each line in the message
    for lnum = msg.position.start_line, msg.position.end_line do
      local line_idx = lnum - 1 -- Convert to 0-indexed
      if line_idx >= 0 and line_idx < line_count then
        vim.api.nvim_buf_set_extmark(bufnr, line_hl_ns, line_idx, 0, {
          line_hl_group = hl_group,
          priority = PRIORITY.LINE_HIGHLIGHT,
        })
      end
    end
  end
end

---Set up folding expression for a buffer.
---If bufnr is provided, sets folding on the window displaying that buffer,
---otherwise sets folding on the current window.
---@param bufnr? integer
function M.setup_folding(bufnr)
  local winid

  if bufnr then
    winid = vim.fn.bufwinid(bufnr)
    if winid == -1 then
      -- Buffer not displayed in any window, skip
      return
    end
  else
    winid = vim.api.nvim_get_current_win()
  end

  -- Set window-local options on the correct window
  vim.wo[winid].foldmethod = "expr"
  vim.wo[winid].foldexpr = 'v:lua.require("flemma.ui.preview").get_fold_level(v:lnum)'
  vim.wo[winid].foldtext = 'v:lua.require("flemma.ui.preview").get_fold_text()'
  -- Set fold level from config (default 1 = thinking blocks collapsed)
  vim.wo[winid].foldlevel = config.editing.foldlevel
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

  M.setup_folding(bufnr)

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
    if msg.role == "You" then
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
  local parser = require("flemma.parser")
  local doc = parser.get_parsed_document(bufnr)

  M.add_rulers(bufnr, doc)
  M.highlight_thinking_tags(bufnr, doc)
  M.apply_line_highlights(bufnr, doc)
  M.add_tool_previews(bufnr, doc)
  -- Note: spinner extmark (with suppression) is managed by start_loading_spinner and its timer

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

  local key = indicator_key(bufnr, tool_id)
  local line_idx = header_line - 1

  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, tool_exec_ns, line_idx, 0, {
    virt_text = { { " ● Pending", "FlemmaToolPending" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
    priority = PRIORITY.TOOL_EXECUTION,
    spell = false,
  })

  tool_indicators[key] = {
    extmark_id = extmark_id,
    timer = nil,
    bufnr = bufnr,
    tool_id = tool_id,
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

  local key = indicator_key(bufnr, tool_id)
  local line_idx = header_line - 1
  local frame = 1

  local extmark_id = vim.api.nvim_buf_set_extmark(bufnr, tool_exec_ns, line_idx, 0, {
    virt_text = { { " " .. TOOL_SPINNER_FRAMES[frame] .. " Executing…", "FlemmaToolPending" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
    priority = PRIORITY.TOOL_EXECUTION,
    spell = false,
  })

  local timer = vim.fn.timer_start(100, function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      local ind = tool_indicators[key]
      if ind and ind.timer then
        vim.fn.timer_stop(ind.timer)
      end
      tool_indicators[key] = nil
      return
    end

    local ind = tool_indicators[key]
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

  tool_indicators[key] = {
    extmark_id = extmark_id,
    timer = timer,
    bufnr = bufnr,
    tool_id = tool_id,
  }
end

--- Update indicator to show completion/error state
--- Stops animation, shows final state
---@param bufnr integer
---@param tool_id string
---@param success boolean
function M.update_tool_indicator(bufnr, tool_id, success)
  local key = indicator_key(bufnr, tool_id)
  local ind = tool_indicators[key]
  if not ind then
    return
  end

  -- Stop animation timer
  if ind.timer then
    vim.fn.timer_stop(ind.timer)
    ind.timer = nil
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    tool_indicators[key] = nil
    return
  end

  -- Query extmark's current position (may have shifted due to buffer edits)
  local current_line = get_extmark_line(bufnr, ind.extmark_id)
  if not current_line then
    tool_indicators[key] = nil
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
  local key = indicator_key(bufnr, tool_id)
  local ind = tool_indicators[key]
  if not ind then
    return
  end

  if ind.timer then
    vim.fn.timer_stop(ind.timer)
  end

  -- Always delete from the buffer where the extmark actually lives (ind.bufnr),
  -- not the passed bufnr, to avoid leaking extmarks on cross-buffer tool_id collisions.
  if vim.api.nvim_buf_is_valid(ind.bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, ind.bufnr, tool_exec_ns, ind.extmark_id)
  end

  tool_indicators[key] = nil
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
  local parser = require("flemma.parser")
  local doc = parser.get_parsed_document(bufnr)
  local result_positions = {}
  for _, msg in ipairs(doc.messages) do
    if msg.role == "You" then
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "tool_result" then
          result_positions[seg.tool_use_id] = seg.position.start_line - 1 -- 0-based
        end
      end
    end
  end

  for _, ind in pairs(tool_indicators) do
    if ind.bufnr == bufnr then
      local target_line = result_positions[ind.tool_id]
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
  local key = indicator_key(bufnr, tool_id)
  local ind = tool_indicators[key]
  if not ind then
    return
  end
  local expected_extmark = ind.extmark_id
  local cleared = false

  local function do_clear()
    if cleared then
      return
    end
    local current = tool_indicators[key]
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
  local to_clear = {}
  for _, ind in pairs(tool_indicators) do
    if ind.bufnr == bufnr then
      table.insert(to_clear, ind.tool_id)
    end
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
      -- Use the new function for debounced updates
      require("flemma.core").update_ui(ev.buf)
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
