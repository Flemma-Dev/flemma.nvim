--- Centralized JSON encode/decode for Flemma
--- Wraps vim.json with luanil options so JSON null always becomes Lua nil.
--- All Flemma code MUST use this module instead of vim.fn.json_* or vim.json.* directly.
---@class flemma.Json
local M = {}

local DECODE_OPTS = { luanil = { object = true, array = true } }

---Decode a JSON string into a Lua value.
---JSON null becomes Lua nil (not vim.NIL).
---@param str string JSON string to decode
---@return any
function M.decode(str)
  return vim.json.decode(str, DECODE_OPTS)
end

---Encode a Lua value into a JSON string.
---@param value any Lua value to encode
---@return string
function M.encode(value)
  return vim.json.encode(value)
end

return M
