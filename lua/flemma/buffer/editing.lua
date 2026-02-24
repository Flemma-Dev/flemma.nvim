--- Buffer editing utilities
--- Shared operations that modify buffer content or trigger writes
---@class flemma.buffer.Editing
local M = {}

local state = require("flemma.state")
local ui = require("flemma.ui")

---Auto-write buffer if configured and modified.
---Used by core.lua (request lifecycle) and executor.lua (tool completion) to
---ensure the buffer is written to disk after any content-modifying operation.
---@param bufnr integer
function M.auto_write(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local config = state.get_config()
  if config.editing and config.editing.auto_write and vim.bo[bufnr].modified then
    ui.buffer_cmd(bufnr, "silent! write")
  end
end

return M
