--- Navigation functions for Flemma chat interface
--- Provides cursor movement within chat buffers
---@class flemma.Navigation
local M = {}

local parser = require("flemma.parser")

---Find the next message marker in the buffer and move cursor there
---@return boolean found True if a next message was found and cursor moved
function M.find_next_message()
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local bufnr = vim.api.nvim_get_current_buf()
  local doc = parser.get_parsed_document(bufnr)

  for _, msg in ipairs(doc.messages) do
    local content_line = msg.position.start_line + 1
    if content_line > cur_line then
      vim.api.nvim_win_set_cursor(0, { content_line, 0 })
      return true
    end
  end
  return false
end

---Find the previous message marker in the buffer and move cursor there
---@return boolean found True if a previous message was found and cursor moved
function M.find_prev_message()
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local bufnr = vim.api.nvim_get_current_buf()
  local doc = parser.get_parsed_document(bufnr)

  -- Iterate in reverse to find the previous message
  for i = #doc.messages, 1, -1 do
    local msg = doc.messages[i]
    local content_line = msg.position.start_line + 1
    if content_line < cur_line then
      vim.api.nvim_win_set_cursor(0, { content_line, 0 })
      return true
    end
  end
  return false
end

return M
