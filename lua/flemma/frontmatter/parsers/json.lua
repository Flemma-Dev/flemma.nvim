--- JSON parser for frontmatter
--- Decodes JSON and returns a flat table of key-value pairs
local M = {}

---Parse JSON code and return decoded table
---@param code string The JSON code to parse
---@param context table Optional context (not used for JSON but kept for interface consistency)
---@return table variables Table of variables from JSON
function M.parse(code, context)
  -- Use Neovim's built-in JSON decoder
  local ok, result = pcall(vim.fn.json_decode, code)

  if not ok then
    error(string.format("JSON parse error: %s", result))
  end

  -- Ensure result is a table (JSON object)
  if type(result) ~= "table" then
    error(string.format("JSON frontmatter must be an object, got %s", type(result)))
  end

  return result
end

return M
