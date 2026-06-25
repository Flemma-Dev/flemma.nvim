--- HTTP utilities — helpers for working with parsed response headers.
---
--- Headers are stored as table<string, string[]> (lowercase name → values array),
--- matching the format produced by client.lua's header parser.
---@class flemma.utilities.Http
local M = {}

---Read a single header value as a string, or nil.
---@param headers table<string, string[]>
---@param name string Lowercase header name
---@return string|nil
function M.read_header(headers, name)
  local values = headers[name]
  if values and #values > 0 then
    return values[1]
  end
  return nil
end

---Read a single header value as a number, or nil.
---@param headers table<string, string[]>
---@param name string Lowercase header name
---@return number|nil
function M.read_header_number(headers, name)
  local raw = M.read_header(headers, name)
  if raw then
    return tonumber(raw)
  end
  return nil
end

return M
