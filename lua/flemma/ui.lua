--- UI module for Flemma plugin
--- Handles visual presentation: rulers, spinners, folding, and signs
local M = {}

local log = require("flemma.logging")
local state = require("flemma.state")
local buffers = require("flemma.buffers")

-- Define namespace for our extmarks
local ns_id = vim.api.nvim_create_namespace("flemma")

-- Add rulers between messages
function M.add_rulers(bufnr)
  -- Clear existing extmarks
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  -- Get buffer lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  for i, line in ipairs(lines) do
    if line:match("^@[%w]+:") then
      -- If this isn't the first line, add a ruler before it
      if i > 1 then
        -- Create virtual line with ruler using the FlemmaRuler highlight group
        local ruler_text = string.rep(state.get_config().ruler.char, math.floor(vim.api.nvim_win_get_width(0) * 1))
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, i - 1, 0, {
          virt_lines = { { { ruler_text, "FlemmaRuler" } } }, -- Use defined group
          virt_lines_above = true,
        })
      end
    end
  end
end

-- Show loading spinner
function M.start_loading_spinner(bufnr)
  local original_modifiable_initial = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true -- Allow plugin modifications for initial message

  local buffer_state = buffers.get_state(bufnr)
  local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local frame = 1

  -- Clear any existing virtual text
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  -- Check if we need to add a blank line
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #buffer_lines > 0 and buffer_lines[#buffer_lines]:match("%S") then
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "", "@Assistant: Thinking..." })
  else
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "@Assistant: Thinking..." })
  end
  -- Immediately update UI after adding the thinking message
  M.update_ui(bufnr)
  vim.bo[bufnr].modifiable = original_modifiable_initial -- Restore state after initial message

  local timer = vim.fn.timer_start(100, function()
    if not buffer_state.current_request then
      return
    end

    local original_modifiable_timer = vim.bo[bufnr].modifiable
    vim.bo[bufnr].modifiable = true -- Allow plugin modifications for spinner update

    frame = (frame % #spinner_frames) + 1
    local text = "@Assistant: " .. spinner_frames[frame] .. " Thinking..."
    local last_line = vim.api.nvim_buf_line_count(bufnr)
    buffers.buffer_cmd(bufnr, "undojoin")
    vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, { text })
    -- Force UI update during spinner animation
    M.update_ui(bufnr)

    vim.bo[bufnr].modifiable = original_modifiable_timer -- Restore state after spinner update
  end, { ["repeat"] = -1 })

  buffer_state.spinner_timer = timer
  return timer
end

-- Clean up spinner and prepare for response
function M.cleanup_spinner(bufnr)
  local original_modifiable = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true -- Allow plugin modifications

  local buffer_state = buffers.get_state(bufnr)
  if buffer_state.spinner_timer then
    vim.fn.timer_stop(buffer_state.spinner_timer)
    buffer_state.spinner_timer = nil
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1) -- Clear rulers/virtual text

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    M.update_ui(bufnr) -- Ensure UI is clean even if buffer is empty
    return
  end

  local last_line_content = vim.api.nvim_buf_get_lines(bufnr, line_count - 1, line_count, false)[1]

  -- Only modify lines if the last line is actually the spinner message
  if last_line_content and last_line_content:match("^@Assistant: .*Thinking%.%.%.$") then
    buffers.buffer_cmd(bufnr, "undojoin") -- Group changes for undo

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
  local num_lines = vim.api.nvim_buf_line_count(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) -- 0-indexed lines

  -- Find the line number of the last @You: prompt to define the search boundary.
  -- We search upwards from this prompt.
  local last_you_prompt_lnum_0idx = -1
  for l = num_lines - 1, 0, -1 do -- Iterate 0-indexed line numbers
    if lines[l + 1]:match("^@You:%s*") then -- lines table is 1-indexed
      last_you_prompt_lnum_0idx = l
      break
    end
  end

  if last_you_prompt_lnum_0idx == -1 then
    log.debug("fold_last_thinking_block(): Could not find the last @You: prompt. Aborting.")
    return
  end

  local end_think_lnum_0idx = -1
  -- Search for </thinking> upwards from just before the last @You: prompt.
  -- Stop if we hit another message type, ensuring we're in the last message block.
  for l = last_you_prompt_lnum_0idx - 1, 0, -1 do
    if lines[l + 1]:match("^</thinking>$") then
      end_think_lnum_0idx = l
      break
    end
    -- If we encounter another role marker before finding </thinking>,
    -- it means the last message block didn't have a thinking tag.
    if lines[l + 1]:match("^@[%w]+:") then
      log.debug(
        "fold_last_thinking_block(): Encountered another role marker before </thinking> in the last message segment."
      )
      return
    end
  end

  if end_think_lnum_0idx == -1 then
    log.debug("fold_last_thinking_block(): No </thinking> tag found in the last message segment.")
    return
  end

  local start_think_lnum_0idx = -1
  -- Search for <thinking> upwards from just before the found </thinking> tag.
  -- Stop if we hit another message type.
  for l = end_think_lnum_0idx - 1, 0, -1 do
    if lines[l + 1]:match("^<thinking>$") then
      start_think_lnum_0idx = l
      break
    end
    if lines[l + 1]:match("^@[%w]+:") then
      log.debug("fold_last_thinking_block(): Encountered another role marker before finding matching <thinking> tag.")
      return
    end
  end

  if start_think_lnum_0idx ~= -1 and start_think_lnum_0idx < end_think_lnum_0idx then
    log.debug(
      string.format(
        "fold_last_thinking_block(): Found thinking block from line %d to %d (1-indexed). Closing fold.",
        start_think_lnum_0idx + 1,
        end_think_lnum_0idx + 1
      )
    )
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      -- vim.cmd uses 1-based line numbers
      vim.fn.win_execute(
        winid,
        string.format("%d,%d foldclose", start_think_lnum_0idx + 1, end_think_lnum_0idx + 1) -- Corrected to foldclose and added space
      )
      log.debug("fold_last_thinking_block(): Executed foldclose command via win_execute.")
    else
      log.debug("fold_last_thinking_block(): Buffer " .. bufnr .. " has no window. Cannot close fold.")
    end
  else
    log.debug(
      "fold_last_thinking_block(): No matching <thinking> tag found for the last </thinking> tag, or order is incorrect."
    )
  end
end

-- Place signs for a message
function M.place_signs(bufnr, start_line, end_line, role)
  local config = state.get_config()
  if not config.signs.enabled then
    return
  end

  -- Map the display role ("You", "System", "Assistant") to the internal config key ("user", "system", "assistant")
  local internal_role_key = string.lower(role) -- Default to lowercase
  if role == "You" then
    internal_role_key = "user" -- Map "You" specifically to "user"
  end

  local sign_name = "flemma_" .. internal_role_key -- Construct sign name like "flemma_user"
  local sign_config = config.signs[internal_role_key] -- Look up config using "user", "system", etc.

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
  vim.wo.foldexpr = 'v:lua.require("flemma.buffers").get_fold_level(v:lnum)'
  vim.wo.foldtext = 'v:lua.require("flemma.buffers").get_fold_text()'
  -- Start with all folds open
  vim.wo.foldlevel = 99
end

-- Helper function to force UI update (rulers and signs)
function M.update_ui(bufnr)
  -- Ensure buffer is valid before proceeding
  if not vim.api.nvim_buf_is_valid(bufnr) then
    log.debug("update_ui(): Invalid buffer: " .. bufnr)
    return
  end
  M.add_rulers(bufnr)
  -- Clear and reapply all signs
  vim.fn.sign_unplace("flemma_ns", { buffer = bufnr })
  -- We need access to the parse_buffer function from init.lua
  require("flemma.buffers").parse_buffer(bufnr) -- This will reapply signs
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
end

return M
