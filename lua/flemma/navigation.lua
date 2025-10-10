--- Navigation functions for Flemma chat interface
--- Provides cursor movement within chat buffers
local M = {}

local parser = require("flemma.parser")

-- Find the next message marker in the buffer and move cursor
function M.find_next_message()
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local doc = parser.parse_lines(lines)

  for _, msg in ipairs(doc.messages) do
    if msg.position.start_line > cur_line then
      -- Get the line and find position after the colon and whitespace
      local full_line = lines[msg.position.start_line]
      local col = full_line:find(":%s*") + 1
      while full_line:sub(col, col) == " " do
        col = col + 1
      end
      vim.api.nvim_win_set_cursor(0, { msg.position.start_line, col - 1 })
      return true
    end
  end
  return false
end

-- Find the previous message marker in the buffer and move cursor
function M.find_prev_message()
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local doc = parser.parse_lines(lines)

  -- Iterate in reverse to find the previous message
  for i = #doc.messages, 1, -1 do
    local msg = doc.messages[i]
    if msg.position.start_line < cur_line then
      -- Get the line and find position after the colon and whitespace
      local full_line = lines[msg.position.start_line]
      local col = full_line:find(":%s*") + 1
      while full_line:sub(col, col) == " " do
        col = col + 1
      end
      vim.api.nvim_win_set_cursor(0, { msg.position.start_line, col - 1 })
      return true
    end
  end
  return false
end

return M
