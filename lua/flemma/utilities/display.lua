--- Shared display utilities for Flemma UI
---@class flemma.utilities.Display
local M = {}

local DEFAULT_NEWLINE_CHAR = "↵"
local DEFAULT_LEAD_CHAR = "·"
local DEFAULT_TRAIL_CHAR = "·"
local DEFAULT_TAB_CHAR = "→"

---Get the newline indicator character.
---Uses the `eol` value from `listchars` when defined, otherwise falls back to `↵`.
---@return string
function M.get_newline_char()
  local listchars = vim.opt.listchars:get()
  return listchars.eol or DEFAULT_NEWLINE_CHAR
end

---Get the leading space indicator character.
---Uses the `lead` value from `listchars` when defined, otherwise falls back to `·`.
---@return string
function M.get_lead_char()
  local listchars = vim.opt.listchars:get()
  return listchars.lead or DEFAULT_LEAD_CHAR
end

---Get the trailing space indicator character.
---Uses the `trail` value from `listchars` when defined, otherwise falls back to `·`.
---@return string
function M.get_trail_char()
  local listchars = vim.opt.listchars:get()
  return listchars.trail or DEFAULT_TRAIL_CHAR
end

---Get the tab indicator character.
---Uses the first character of the `tab` value from `listchars` when defined, otherwise falls back to `→`.
---@return string
function M.get_tab_char()
  local listchars = vim.opt.listchars:get()
  if listchars.tab then
    return listchars.tab:sub(1, 1)
  end
  return DEFAULT_TAB_CHAR
end

return M
