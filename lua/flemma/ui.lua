--- UI module for Flemma plugin
--- Handles visual presentation: rulers, spinners, folding, and signs
local M = {}

local log = require("flemma.logging")
local state = require("flemma.state")
local config = require("flemma.config")

-- Constants for fold text preview
local MAX_CONTENT_PREVIEW_LINES = 10
local MAX_CONTENT_PREVIEW_LENGTH = 72
local CONTENT_PREVIEW_NEWLINE_CHAR = "⤶"
local CONTENT_PREVIEW_TRUNCATION_MARKER = "..."

-- Helper function to generate content preview for folds
local function get_fold_content_preview(fold_start_lnum, fold_end_lnum)
  local content_lines = {}
  local num_content_lines_in_fold = fold_end_lnum - fold_start_lnum - 1

  if num_content_lines_in_fold <= 0 then
    return ""
  end

  local lines_to_fetch = math.min(num_content_lines_in_fold, MAX_CONTENT_PREVIEW_LINES)

  for i = 1, lines_to_fetch do
    local current_content_line_num = fold_start_lnum + i
    local line_text = vim.fn.getline(current_content_line_num)
    table.insert(content_lines, vim.fn.trim(line_text))
  end

  local preview_str = table.concat(content_lines, CONTENT_PREVIEW_NEWLINE_CHAR)
  preview_str = vim.fn.trim(preview_str)

  if #preview_str > MAX_CONTENT_PREVIEW_LENGTH then
    local truncated_length = MAX_CONTENT_PREVIEW_LENGTH - #CONTENT_PREVIEW_TRUNCATION_MARKER
    if truncated_length < 0 then
      truncated_length = 0
    end

    preview_str = preview_str:sub(1, truncated_length)
    preview_str = preview_str .. CONTENT_PREVIEW_TRUNCATION_MARKER
  end

  return preview_str
end

-- Folding functions
function M.get_fold_level(lnum)
  local line = vim.fn.getline(lnum)
  local next_line_num = lnum + 1
  local last_buf_line = vim.fn.line("$")

  -- Level 3 folds: ```<language> ... ``` (only if on the first line)
  if lnum == 1 and line:match("^```%w+$") then
    return ">3"
  elseif line:match("^```$") then
    return "<3"
  end

  -- Level 2 folds: <thinking>...</thinking>
  -- Match opening tags: <thinking> or <thinking signature="..."> (but not self-closing />)
  -- Pattern [^/>] excludes both / and > so the final > can match
  if line:match("^<thinking>$") or line:match("^<thinking%s.+[^/>]>$") then
    return ">2"
  elseif line:match("^</thinking>$") then
    return "<2"
  end

  -- Level 1 folds: @Role:...
  if line:match("^@[%w]+:") then
    return ">1"
  end

  -- Check for end of level 1 fold
  if next_line_num <= last_buf_line then
    local next_line_content = vim.fn.getline(next_line_num)
    if next_line_content:match("^@[%w]+:") then
      return "<1"
    end
  elseif lnum == last_buf_line then
    return "<1"
  end

  return "="
end

function M.get_fold_text()
  local foldstart_lnum = vim.v.foldstart
  local foldend_lnum = vim.v.foldend
  local first_line_content = vim.fn.getline(foldstart_lnum)
  local total_fold_lines = foldend_lnum - foldstart_lnum + 1

  -- Check for frontmatter fold (level 3) - only if it started on line 1
  local fm_language = first_line_content:match("^```(%w+)$")
  if foldstart_lnum == 1 and fm_language then
    local preview = get_fold_content_preview(foldstart_lnum, foldend_lnum)
    if preview ~= "" then
      return string.format("```%s %s ``` (%d lines)", fm_language, preview, total_fold_lines)
    else
      return string.format("```%s (%d lines)", fm_language, total_fold_lines)
    end
  end

  -- Check if this is a thinking fold (level 2)
  -- Match opening tags: <thinking> or <thinking signature="...">
  if first_line_content:match("^<thinking>$") or first_line_content:match("^<thinking%s.+[^/>]>$") then
    local preview = get_fold_content_preview(foldstart_lnum, foldend_lnum)
    if preview ~= "" then
      return string.format("<thinking> %s </thinking> (%d lines)", preview, total_fold_lines)
    else
      return string.format("<thinking> (%d lines)", total_fold_lines)
    end
  end

  -- Message folds (level 1)
  local role_type = first_line_content:match("^(@[%w]+:)")
  if not role_type then
    return first_line_content
  end

  local content_preview_for_message = first_line_content:sub(#role_type + 1):gsub("^%s*", "")
  return string.format("%s %s... (%d lines)", role_type, content_preview_for_message:sub(1, 50), total_fold_lines)
end

-- Define namespace for our extmarks
local ns_id = vim.api.nvim_create_namespace("flemma")
local spinner_ns = vim.api.nvim_create_namespace("flemma_spinner")

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

local function apply_spinner_suppression(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    vim.api.nvim_buf_clear_namespace(bufnr, spinner_ns, 0, -1)
    return
  end

  local spinner_line_idx0 = line_count - 1
  local lines = vim.api.nvim_buf_get_lines(bufnr, spinner_line_idx0, line_count, false)
  local spinner_line = lines[1]

  if not spinner_line or not spinner_line:match("^@Assistant: .*Thinking%.%.%.$") then
    vim.api.nvim_buf_clear_namespace(bufnr, spinner_ns, 0, -1)
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, spinner_ns, spinner_line_idx0, spinner_line_idx0 + 1)

  local extmark_opts = {
    end_line = spinner_line_idx0 + 1,
    hl_group = "FlemmaAssistantSpinner",
    priority = 300, -- Higher than Treesitter spell layer
    spell = false,
  }

  vim.api.nvim_buf_set_extmark(bufnr, spinner_ns, spinner_line_idx0, 0, extmark_opts)
end

-- Add rulers between messages
function M.add_rulers(bufnr, doc)
  -- Clear existing extmarks
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  for i, msg in ipairs(doc.messages) do
    -- Add a ruler before each message after the first, and before the first if frontmatter exists
    if i > 1 or (i == 1 and doc.frontmatter ~= nil) then
      local line_idx = msg.position.start_line - 1
      if line_idx >= 0 and line_idx < vim.api.nvim_buf_line_count(bufnr) then
        -- Create virtual line with ruler using the FlemmaRuler highlight group
        local ruler_text = string.rep(state.get_config().ruler.char, math.floor(vim.api.nvim_win_get_width(0) * 1))
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_idx, 0, {
          virt_lines = { { { ruler_text, "FlemmaRuler" } } }, -- Use defined group
          virt_lines_above = true,
        })
      end
    end
  end
end

-- Highlight thinking tags using extmarks (higher priority than Treesitter)
function M.highlight_thinking_tags(bufnr, doc)
  local thinking_ns = vim.api.nvim_create_namespace("flemma_thinking_tags")

  -- Clear existing thinking tag highlights
  vim.api.nvim_buf_clear_namespace(bufnr, thinking_ns, 0, -1)

  -- Iterate through messages and their segments to find thinking blocks
  for _, msg in ipairs(doc.messages) do
    if msg.segments then
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "thinking" and seg.position then
          -- Highlight opening tag
          vim.api.nvim_buf_set_extmark(bufnr, thinking_ns, seg.position.start_line - 1, 0, {
            end_line = seg.position.start_line,
            hl_group = "FlemmaThinkingTag",
            priority = 200, -- Higher than Treesitter (100)
          })
          -- Highlight closing tag
          vim.api.nvim_buf_set_extmark(bufnr, thinking_ns, seg.position.end_line - 1, 0, {
            end_line = seg.position.end_line,
            hl_group = "FlemmaThinkingTag",
            priority = 200,
          })
        end
      end
    end
  end
end

-- Show loading spinner
function M.start_loading_spinner(bufnr)
  local original_modifiable_initial = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true -- Allow plugin modifications for initial message

  local buffer_state = state.get_buffer_state(bufnr)
  local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local frame = 1

  vim.schedule(function()
    -- Clear any existing virtual text
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

    -- Check if we need to add a blank line
    vim.bo[bufnr].modifiable = true
    local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    if #buffer_lines > 0 and buffer_lines[#buffer_lines]:match("%S") then
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "", "@Assistant: Thinking..." })
    else
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "@Assistant: Thinking..." })
    end
    -- Immediately update UI after adding the thinking message
    M.update_ui(bufnr)
    apply_spinner_suppression(bufnr)
    -- Move to bottom and center the line so user sees the message
    M.move_to_bottom()
    M.center_cursor()
    vim.bo[bufnr].modifiable = original_modifiable_initial
  end)

  local timer = vim.fn.timer_start(100, function()
    if not buffer_state.current_request then
      return
    end

    local original_modifiable_timer = vim.bo[bufnr].modifiable
    vim.bo[bufnr].modifiable = true -- Allow plugin modifications for spinner update

    frame = (frame % #spinner_frames) + 1
    local text = "@Assistant: " .. spinner_frames[frame] .. " Thinking..."
    local last_line = vim.api.nvim_buf_line_count(bufnr)
    M.buffer_cmd(bufnr, "undojoin")
    vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, { text })
    -- Force UI update during spinner animation
    M.update_ui(bufnr)
    apply_spinner_suppression(bufnr)

    vim.bo[bufnr].modifiable = original_modifiable_timer -- Restore state after spinner update
  end, { ["repeat"] = -1 })

  buffer_state.spinner_timer = timer
  return timer
end

-- Clean up spinner and prepare for response
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

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1) -- Clear rulers/virtual text
  vim.api.nvim_buf_clear_namespace(bufnr, spinner_ns, 0, -1) -- Remove spinner suppression

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    M.update_ui(bufnr) -- Ensure UI is clean even if buffer is empty
    vim.bo[bufnr].modifiable = original_modifiable -- Restore modifiable before return
    return
  end

  local last_line_content = vim.api.nvim_buf_get_lines(bufnr, line_count - 1, line_count, false)[1]

  -- Only modify lines if the last line is actually the spinner message
  if last_line_content and last_line_content:match("^@Assistant: .*Thinking%.%.%.$") then
    M.buffer_cmd(bufnr, "undojoin") -- Group changes for undo

    -- Get the line before the "Thinking..." message (if it exists)
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
    log.debug("cleanup_spinner(): Last line is not the 'Thinking...' message, not modifying lines.")
  end

  M.update_ui(bufnr) -- Force UI update after cleaning up spinner
  vim.bo[bufnr].modifiable = original_modifiable -- Restore previous modifiable state
end

-- Helper function to fold the last thinking block in a buffer
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
      vim.fn.win_execute(winid, string.format("%d,%d foldclose", start_lnum_1idx, end_lnum_1idx))
      log.debug("fold_last_thinking_block(): Executed foldclose command via win_execute.")
    else
      log.debug("fold_last_thinking_block(): No fold exists at line " .. start_lnum_1idx .. ". Skipping foldclose.")
    end
  else
    log.debug("fold_last_thinking_block(): Buffer " .. bufnr .. " has no window. Cannot close fold.")
  end
end

-- Place signs for a message
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

-- Set up folding expression
function M.setup_folding()
  vim.wo.foldmethod = "expr"
  vim.wo.foldexpr = 'v:lua.require("flemma.ui").get_fold_level(v:lnum)'
  vim.wo.foldtext = 'v:lua.require("flemma.ui").get_fold_text()'
  -- Start with all folds open
  vim.wo.foldlevel = 99
end

-- Store original updatetime per-session (global for all buffers)
local original_updatetime = nil

-- Set up chat filetype autocmds
function M.setup_chat_filetype_autocmds()
  -- Handle .chat file detection
  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    pattern = "*.chat",
    callback = function()
      vim.bo.filetype = "chat"
      M.setup_folding()

      if config.editing.disable_textwidth then
        vim.bo.textwidth = 0
      end

      if config.editing.auto_write then
        vim.opt_local.autowrite = true
      end
    end,
  })

  -- Handle manual filetype changes to 'chat'
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "chat",
    callback = function()
      M.setup_folding()
      if config.editing.disable_textwidth then
        vim.bo.textwidth = 0
      end
      if config.editing.auto_write then
        vim.opt_local.autowrite = true
      end
    end,
  })

  -- Handle updatetime management for chat buffers
  if config.editing.manage_updatetime then
    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = "*.chat",
      callback = function()
        if original_updatetime == nil then
          original_updatetime = vim.o.updatetime
        end
        vim.o.updatetime = 100
      end,
    })

    vim.api.nvim_create_autocmd("BufLeave", {
      pattern = "*.chat",
      callback = function()
        local next_bufnr = vim.fn.bufnr("#")
        local is_next_chat = false
        if next_bufnr ~= -1 and vim.api.nvim_buf_is_valid(next_bufnr) then
          local next_bufname = vim.api.nvim_buf_get_name(next_bufnr)
          is_next_chat = vim.bo[next_bufnr].filetype == "chat" or next_bufname:match("%.chat$")
        end

        if not is_next_chat and original_updatetime ~= nil then
          vim.o.updatetime = original_updatetime
          original_updatetime = nil
        end
      end,
    })
  end
end

-- Helper function to force UI update (rulers and signs)
function M.update_ui(bufnr)
  -- Ensure buffer is valid before proceeding
  if not vim.api.nvim_buf_is_valid(bufnr) then
    log.debug("update_ui(): Invalid buffer: " .. bufnr)
    return
  end

  -- Parse messages using AST
  local parser = require("flemma.parser")
  local doc = parser.get_parsed_document(bufnr)

  M.add_rulers(bufnr, doc)
  M.highlight_thinking_tags(bufnr, doc)
  apply_spinner_suppression(bufnr)

  -- Clear and reapply all signs
  vim.fn.sign_unplace("flemma_ns", { buffer = bufnr })

  -- Place signs for each message based on AST positions
  for _, msg in ipairs(doc.messages) do
    M.place_signs(bufnr, msg.position.start_line, msg.position.end_line, msg.role)
  end
end

-- Move cursor to end of buffer
function M.move_to_bottom()
  vim.cmd("normal! G")
end

-- Center cursor line in window
function M.center_cursor()
  vim.cmd("normal! zz")
end

-- Move cursor to specific position
function M.set_cursor(line, col)
  if vim.api.nvim_get_current_buf() then
    vim.api.nvim_win_set_cursor(0, { line, col })
  end
end

-- Set up UI-related autocmds and initialization
function M.setup()
  -- Add autocmd for updating rulers and signs (debounced via CursorHold)
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "VimResized", "CursorHold", "CursorHoldI" }, {
    pattern = "*.chat",
    callback = function(ev)
      -- Use the new function for debounced updates
      require("flemma.core").update_ui(ev.buf)
    end,
  })

  -- Ensure buffer-local state gets cleaned up when chat buffers are removed.
  -- This prevents leaking timers or jobs if a buffer is deleted while a request/spinner is active.
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload", "BufDelete" }, {
    pattern = "*",
    callback = function(ev)
      if vim.bo[ev.buf].filetype == "chat" or string.match(vim.api.nvim_buf_get_name(ev.buf), "%.chat$") then
        M.cleanup_spinner(ev.buf)
        state.cleanup_buffer_state(ev.buf)
      end
    end,
  })
end

return M
