--- Shared display utilities for Flemma UI
---@class flemma.ui.Display
local M = {}

local DEFAULT_NEWLINE_CHAR = "↵"

---Get the newline indicator character.
---Uses the `eol` value from `listchars` when defined, otherwise falls back to `↵`.
---@return string
function M.get_newline_char()
  local listchars = vim.opt.listchars:get()
  return listchars.eol or DEFAULT_NEWLINE_CHAR
end

return M
