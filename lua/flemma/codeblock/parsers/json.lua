--- JSON parser for code blocks.
--- Decodes JSON and processes operator-aware config writes for frontmatter.
---
--- When bufnr is provided, the "flemma" key is interpreted as config operations
--- using MongoDB-style operators ($set, $append, $remove, $prepend). Plain values
--- and arrays default to $set. Non-flemma keys are returned as template variables.
---@class flemma.codeblock.parsers.Json
local M = {}

local config = require("flemma.config")
local json = require("flemma.utilities.json")

---Parse JSON code and return decoded table.
---When bufnr is provided, processes the `flemma` key as operator-aware config
---writes to the FRONTMATTER layer. Non-flemma keys are returned as template
---variables (same as the Lua parser's global variables).
---@param code string The JSON code to parse
---@param _context? table<string, any> Optional context (not used for JSON but kept for interface consistency)
---@param bufnr? integer Buffer number for config store writes
---@return table<string, any> variables Template variables (non-flemma keys)
---@return flemma.config.ValidationFailure[]? validation_failures Schema validation failures (nil when no bufnr)
function M.parse(code, _context, bufnr)
  local ok, decoded = pcall(json.decode, code)
  if not ok then
    error({ type = "frontmatter", error = string.format("JSON parse error: %s", decoded) })
  end

  if type(decoded) ~= "table" or vim.islist(decoded) then
    return decoded
  end

  local variables = {}
  local all_failures = {} ---@type flemma.config.ValidationFailure[]

  for k, v in pairs(decoded) do
    if k == "flemma" and bufnr then
      if type(v) ~= "table" or vim.islist(v) then
        error({ type = "frontmatter", error = '"flemma" must be an object' })
      end
      local op_failures = config.apply_operators(config.LAYERS.FRONTMATTER, bufnr, v)
      for _, failure in ipairs(op_failures) do
        table.insert(all_failures, failure)
      end
    else
      variables[k] = v
    end
  end

  -- Finalize: coerce transforms + deferred semantic validation
  if bufnr then
    local _, validation_failures = config.finalize(config.LAYERS.FRONTMATTER, nil, bufnr)
    if validation_failures then
      for _, failure in ipairs(validation_failures) do
        table.insert(all_failures, failure)
      end
    end
    return variables, #all_failures > 0 and all_failures or nil
  end

  return variables
end

return M
