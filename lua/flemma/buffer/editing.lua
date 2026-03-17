--- Buffer editing utilities
--- Shared operations that modify buffer content or trigger writes
---@class flemma.buffer.Editing
local M = {}

local bridge = require("flemma.bridge")
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

---Prepend `@You:\n` to an empty (or whitespace-only) buffer.
---Gated behind `config.editing.auto_prompt` (default true).
---Called from the BufRead/BufNewFile autocmd for .chat files.
---@param bufnr integer
function M.auto_prompt(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local config = state.get_config()
  if not (config.editing and config.editing.auto_prompt) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, line in ipairs(lines) do
    if line:match("%S") then
      return
    end
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "" })
  -- Place cursor on line 2 if buffer is displayed in the current window
  local winid = vim.fn.bufwinid(bufnr)
  if winid ~= -1 then
    vim.api.nvim_win_set_cursor(winid, { 2, 0 })
  end
end

-- Register bridge for modules that cannot require editing directly (circular dep)
bridge.register("auto_prompt", M.auto_prompt)

return M
