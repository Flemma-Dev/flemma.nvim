--- Navigation functions for Flemma chat interface
--- Provides cursor movement within chat buffers
---@class flemma.Navigation
local M = {}

local parser = require("flemma.parser")

---Get the 0-indexed column where content starts after a role prefix (@Role: )
---@param role string
---@return integer
local function content_col(role)
  return #("@" .. role .. ": ")
end

---Find the next message marker in the buffer and move cursor there
---@return boolean found True if a next message was found and cursor moved
function M.find_next_message()
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local bufnr = vim.api.nvim_get_current_buf()
  local doc = parser.get_parsed_document(bufnr)

  for _, msg in ipairs(doc.messages) do
    if msg.position.start_line > cur_line then
      vim.api.nvim_win_set_cursor(0, { msg.position.start_line, content_col(msg.role) })
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
    if msg.position.start_line < cur_line then
      vim.api.nvim_win_set_cursor(0, { msg.position.start_line, content_col(msg.role) })
      return true
    end
  end
  return false
end

return M
