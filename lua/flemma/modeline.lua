---Modeline / argument parsing utilities for Flemma
---@class flemma.Modeline
local M = {}

---Mixed-key table returned by modeline parsing: string keys for key=value tokens, integer keys for positionals
---@alias flemma.modeline.ParsedTokens table<string|integer, any>

---Coerce a raw string value to its natural Lua type
---@param raw string
---@return boolean|number|string|nil
local function coerce_value(raw)
  if raw == "true" then
    return true
  end

  if raw == "false" then
    return false
  end

  if raw == "nil" or raw == "null" then
    return nil
  end

  local number_value = tonumber(raw)
  if number_value ~= nil then
    return number_value
  end

  return raw
end

---Parse a list of tokens into a key=value / positional table
---@param tokens string[]
---@return flemma.modeline.ParsedTokens
local function parse_tokens(tokens)
  local result = {}
  local positional_index = 0

  for _, token in ipairs(tokens) do
    local key, raw = token:match("^([%w_]+)=(.+)$")
    if key and raw then
      result[key] = coerce_value(raw)
    elseif token ~= "" then
      positional_index = positional_index + 1
      result[positional_index] = token
    end
  end

  return result
end

---Parse a string array (e.g. command fargs) starting at a given index
---@param args string[]|any
---@param start_index? integer 1-based start index (default 1)
---@return flemma.modeline.ParsedTokens
function M.parse_args(args, start_index)
  if type(args) ~= "table" then
    return {}
  end

  local tokens = {}
  for i = start_index or 1, #args do
    tokens[#tokens + 1] = args[i]
  end

  return parse_tokens(tokens)
end

---Parse a single whitespace-separated line into key=value / positional table
---@param line string|any
---@return flemma.modeline.ParsedTokens
function M.parse(line)
  if type(line) ~= "string" or line == "" then
    return {}
  end

  local tokens = vim.split(line, "%s+", { trimempty = true })
  return parse_tokens(tokens)
end

return M
