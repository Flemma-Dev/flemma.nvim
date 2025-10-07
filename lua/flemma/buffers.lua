--- Buffer state management for Flemma
local M = {}

local log = require("flemma.logging")
local state = require("flemma.state")

-- Store buffer-local state
local buffer_state = {}

-- Initialize state for a buffer
function M.init_buffer(bufnr)
  buffer_state[bufnr] = {
    current_request = nil,
    request_cancelled = false,
    spinner_timer = nil,
    current_usage = {
      input_tokens = 0,
      output_tokens = 0,
    },
  }
end

-- Clean up state when buffer is deleted
function M.cleanup_buffer(bufnr)
  if buffer_state[bufnr] then
    -- Cancel any ongoing request
    if buffer_state[bufnr].current_request then
      local job_id = buffer_state[bufnr].current_request
      vim.fn.jobstop(job_id)
    end
    -- Stop any running timer
    if buffer_state[bufnr].spinner_timer then
      vim.fn.timer_stop(buffer_state[bufnr].spinner_timer)
    end
    buffer_state[bufnr] = nil
  end
end

-- Get state for a buffer
function M.get_state(bufnr)
  if not buffer_state[bufnr] then
    M.init_buffer(bufnr)
  end
  return buffer_state[bufnr]
end

-- Set specific state value for a buffer
function M.set_state(bufnr, key, value)
  if not buffer_state[bufnr] then
    M.init_buffer(bufnr)
  end
  buffer_state[bufnr][key] = value
end

-- Parse a single message from lines
local function parse_message(bufnr, lines, start_idx, frontmatter_offset)
  local line = lines[start_idx]
  local msg_type = line:match("^@([%w]+):")
  if not msg_type then
    return nil, start_idx
  end

  local content = {}
  local i = start_idx
  -- Remove the role marker (e.g., @You:) from the first line
  local first_content = line:sub(#msg_type + 3)
  if first_content:match("%S") then
    content[#content + 1] = first_content:gsub("^%s*", "")
  end

  i = i + 1
  -- Collect lines until we hit another role marker or end of buffer
  while i <= #lines do
    local next_line = lines[i]
    if next_line:match("^@[%w]+:") then
      break
    end
    if next_line:match("%S") or #content > 0 then
      content[#content + 1] = next_line
    end
    i = i + 1
  end

  local result = {
    type = msg_type,
    content = table.concat(content, "\n"):gsub("%s+$", ""),
    start_line = start_idx,
    end_line = i - 1,
  }

  -- Place signs for the message, adjusting for frontmatter
  require("flemma.ui").place_signs(
    bufnr,
    result.start_line + frontmatter_offset,
    result.end_line + frontmatter_offset,
    msg_type
  )

  return result, i - 1
end

---Parse lines into a sequence of messages without executing frontmatter
---
---@param bufnr number The buffer number
---@param lines table The buffer lines
---@param frontmatter_offset number Line offset for sign placement (default 0)
---@return table[] messages The parsed messages
function M.parse_messages(bufnr, lines, frontmatter_offset)
  frontmatter_offset = frontmatter_offset or 0
  local messages = {}

  local i = 1
  while i <= #lines do
    local msg, last_idx = parse_message(bufnr, lines, i, frontmatter_offset)
    if msg then
      messages[#messages + 1] = msg
      i = last_idx + 1
    else
      i = i + 1
    end
  end

  return messages
end

---Parse the entire buffer into messages and execute frontmatter
---
---@param bufnr number The buffer number
---@param context Context The shared context object for frontmatter execution and file path resolution
---@return table[] messages The parsed messages
---@return string|nil frontmatter_code The frontmatter code if present
function M.parse_buffer(bufnr, context)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Handle frontmatter if present (using shared context)
  local frontmatter = require("flemma.frontmatter")
  local fm_code, content = frontmatter.parse(lines)

  -- Execute frontmatter if present (context is optional unless include() is used)
  if fm_code then
    frontmatter.execute(fm_code, context)
  end

  -- Calculate frontmatter offset for sign placement
  local frontmatter_offset = 0
  if fm_code then
    -- Count lines in frontmatter (code + delimiters)
    frontmatter_offset = #vim.split(fm_code, "\n", true) + 2
  end

  -- If no frontmatter was found, use all lines as content
  content = content or lines

  local messages = M.parse_messages(bufnr, content, frontmatter_offset)

  return messages, fm_code
end

-- Execute a command in the context of a specific buffer
function M.buffer_cmd(bufnr, cmd)
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    -- If buffer has no window, do nothing
    return
  end
  vim.fn.win_execute(winid, "noautocmd " .. cmd)
end

-- Helper function to auto-write the buffer if enabled
function M.auto_write_buffer(bufnr)
  if state.get_config().editing.auto_write and vim.bo[bufnr].modified then
    log.debug("auto_write_buffer(): bufnr = " .. bufnr)
    M.buffer_cmd(bufnr, "silent! write")
  end
end

return M
