--- JSON parser for code blocks
--- Decodes JSON and returns a table
local M = {}

---Parse JSON code and return decoded table
---@param code string The JSON code to parse
---@param context table Optional context (not used for JSON but kept for interface consistency)
---@return table variables Table of variables from JSON
function M.parse(code, context)
  local ok, result = pcall(vim.fn.json_decode, code)

  if not ok then
    error(string.format("JSON parse error: %s", result))
  end

  return result
end

return M
