--- Shared utilities for the preprocessor subsystem
--- Provides URL decoding and Lua string escaping helpers used by both
--- the parser and preprocessor rewriters.
---@class flemma.preprocessor.Utilities
local M = {}

---URL-decode a percent-encoded string (e.g., %20 -> space).
---@param str string|nil
---@return string|nil
function M.url_decode(str)
  if not str then
    return nil
  end
  str = string.gsub(str, "+", " ")
  str = string.gsub(str, "%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end)
  return str
end

---Escape a string for use inside a Lua single-quoted string literal.
---@param str string
---@return string
function M.lua_string_escape(str)
  str = str:gsub("\\", "\\\\")
  str = str:gsub("'", "\\'")
  str = str:gsub("\n", "\\n")
  str = str:gsub("\r", "\\r")
  str = str:gsub("\t", "\\t")
  str = str:gsub("%z", "\\0")
  return str
end

return M
