--- Buffer editing utilities
--- Shared operations that modify buffer content or trigger writes
---@class flemma.buffer.Editing
local M = {}

local bridge = require("flemma.bridge")
local config_facade = require("flemma.config")
local buffer_utils = require("flemma.utilities.buffer")
local log = require("flemma.logging")

---Auto-write buffer if configured and modified.
---Used by core.lua (request lifecycle) and executor.lua (tool completion) to
---ensure the buffer is written to disk after any content-modifying operation.
---Uses `write!` to force-write even when the file has been modified on disk by
---an external process (the buffer is the source of truth). Wrapped in pcall so
---a write failure can never crash the request lifecycle.
---@param bufnr integer
function M.auto_write(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local config = config_facade.get(bufnr)
  if config.editing and config.editing.auto_write and vim.bo[bufnr].modified then
    local ok, err = pcall(buffer_utils.buffer_cmd, bufnr, "silent! write!")
    if not ok then
      log.warn("auto_write: write failed: " .. tostring(err))
    end
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
  local config = config_facade.get(bufnr)
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
