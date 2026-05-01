--- URL and Lua-literal encoding helpers
--- Provides URL percent-encoding/decoding and Lua string escaping used across
--- the preprocessor, templating compiler, and tool definitions.
---@class flemma.utilities.Encoding
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

---URL-encode characters that would break the file-reference `%S+` pattern.
---Only encodes whitespace, `#`, `%`, `?`, and `;` (the minimum needed for
---round-tripping through the preprocessor regex and options parser).
---@param str string
---@return string
function M.url_encode_subset(str)
  return (str:gsub("[%s#%%?;]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

return M
