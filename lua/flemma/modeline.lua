local M = {}

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

local function parse_tokens(tokens)
  local result = {}

  for _, token in ipairs(tokens) do
    local key, raw = token:match("^([%w_]+)=(.+)$")
    if key and raw then
      result[key] = coerce_value(raw)
    end
  end

  return result
end

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

function M.parse(line)
  if type(line) ~= "string" or line == "" then
    return {}
  end

  local tokens = vim.split(line, "%s+", { trimempty = true })
  return parse_tokens(tokens)
end

return M
