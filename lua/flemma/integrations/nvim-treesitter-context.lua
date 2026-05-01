--- Optional nvim-treesitter-context integration — disables the sticky context
--- window for .chat buffers, which are role-delimited message sequences rather
--- than one long Markdown document.
---
--- Usage (one line in treesitter-context config):
---   on_attach = require("flemma.integrations.nvim-treesitter-context").on_attach
---
--- To compose with an existing on_attach callback:
---   on_attach = require("flemma.integrations.nvim-treesitter-context").wrap(my_on_attach)
---@class flemma.integrations.NvimTreesitterContext
local M = {}

---Drop-in on_attach callback for nvim-treesitter-context. Returns false for
---chat buffers (filetype == "chat"), true otherwise.
---@param bufnr integer
---@return boolean
function M.on_attach(bufnr)
  return vim.bo[bufnr].filetype ~= "chat"
end

---Compose with an existing on_attach callback. Returns false for chat buffers
---without invoking `user_on_attach`; otherwise delegates to it and normalizes
---a `nil` return to `true` (matching nvim-treesitter-context's own `~= false`
---attach check).
---@param user_on_attach fun(bufnr: integer): boolean|nil
---@return fun(bufnr: integer): boolean
function M.wrap(user_on_attach)
  return function(bufnr)
    if vim.bo[bufnr].filetype == "chat" then
      return false
    end
    return user_on_attach(bufnr) ~= false
  end
end

return M
