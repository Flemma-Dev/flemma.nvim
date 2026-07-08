---Modeline / argument parsing utilities for Flemma
---@class flemma.utilities.Modeline
local M = {}

---Mixed-key table returned by modeline parsing: string keys for key=value tokens, integer keys for positionals.
---When `preserve_nil` is enabled, keyword values that resolve to nil are stored as `vim.NIL`
---so callers can distinguish "explicitly cleared" from "not specified."
---@alias flemma.utilities.modeline.ParsedTokens table<string|integer, any>

---@class flemma.utilities.modeline.ParseOpts
---@field preserve_nil? boolean Store vim.NIL for keyword nil values instead of dropping the key

---The single definition of what a key=value token looks like: identifier key
---(word characters and underscores), '=', raw value. Shared by the token
---parser and the matrix grammar so the key charset cannot drift.
local KEY_VALUE_PATTERN = "^([%w_]+)=(.*)$"

---Coerce a raw string value to its natural Lua type
---@param raw string
---@return boolean|number|string|nil
local function coerce_value(raw)
  if raw == "" then
    return nil
  end

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

---Try to unquote a value fully wrapped in matching quotes, processing escape sequences.
---Only `\` followed by the active delimiter or `\` itself is special; all other `\` sequences are literal.
---@param raw string
---@return string unquoted
---@return boolean was_quoted
local function try_unquote(raw)
  local len = #raw
  if len < 2 then
    return raw, false
  end

  local first = raw:sub(1, 1)
  if first ~= '"' and first ~= "'" then
    return raw, false
  end

  local result = {}
  local i = 2

  while i <= len do
    local ch = raw:sub(i, i)
    if ch == "\\" and i < len then
      local next_ch = raw:sub(i + 1, i + 1)
      if next_ch == first or next_ch == "\\" then
        result[#result + 1] = next_ch
        i = i + 2
      else
        result[#result + 1] = ch
        i = i + 1
      end
    elseif ch == first then
      if i == len then
        return table.concat(result), true
      end
      return raw, false
    else
      result[#result + 1] = ch
      i = i + 1
    end
  end

  return raw, false
end

---Split a raw value on a delimiter outside any quoted region
---@param raw string
---@param delimiter string Single-character delimiter (e.g. ";", ",")
---@return string[]|nil items List of raw items, or nil if no unquoted delimiter exists
local function split_on(raw, delimiter)
  local items = {}
  local start = 1
  local in_quotes = false
  local quote_char = nil
  local found_delimiter = false
  local i = 1
  local len = #raw

  while i <= len do
    local ch = raw:sub(i, i)
    if in_quotes then
      if ch == "\\" and i < len then
        local next_ch = raw:sub(i + 1, i + 1)
        if next_ch == quote_char or next_ch == "\\" then
          i = i + 2
        else
          i = i + 1
        end
      elseif ch == quote_char then
        in_quotes = false
        i = i + 1
      else
        i = i + 1
      end
    else
      if ch == '"' or ch == "'" then
        in_quotes = true
        quote_char = ch
        i = i + 1
      elseif ch == delimiter then
        found_delimiter = true
        items[#items + 1] = raw:sub(start, i - 1)
        start = i + 1
        i = i + 1
      else
        i = i + 1
      end
    end
  end

  if not found_delimiter then
    return nil
  end

  items[#items + 1] = raw:sub(start)
  return items
end

---Resolve a raw value: unquote, split comma lists, or coerce scalars
---@param raw string
---@return boolean|number|string|table|nil
local function resolve_value(raw)
  local unquoted, was_quoted = try_unquote(raw)
  if was_quoted then
    return unquoted
  end

  local items = split_on(raw, ",")
  if items then
    local result = {}
    for i, item in ipairs(items) do
      result[i] = resolve_value(item)
    end
    return result
  end

  return coerce_value(raw)
end

---Scan a string into tokens, respecting quoted regions and escape sequences.
---Quotes and backslashes are preserved in the token text for downstream processing.
---@param input string
---@return string[]
local function scan(input)
  local tokens = {}
  local current = {}
  local in_quotes = false
  local quote_char = nil
  local i = 1
  local len = #input

  while i <= len do
    local ch = input:sub(i, i)

    if in_quotes then
      if ch == "\\" and i < len then
        local next_ch = input:sub(i + 1, i + 1)
        if next_ch == quote_char or next_ch == "\\" then
          current[#current + 1] = ch
          current[#current + 1] = next_ch
          i = i + 1 -- skip escaped char; loop's i=i+1 advances past it
        else
          current[#current + 1] = ch
        end
      elseif ch == quote_char then
        in_quotes = false
        quote_char = nil
        current[#current + 1] = ch
      else
        current[#current + 1] = ch
      end
    else
      if ch == '"' or ch == "'" then
        in_quotes = true
        quote_char = ch
        current[#current + 1] = ch
      elseif ch:match("%s") then
        if #current > 0 then
          tokens[#tokens + 1] = table.concat(current)
          current = {}
        end
      else
        current[#current + 1] = ch
      end
    end

    i = i + 1
  end

  if #current > 0 then
    tokens[#tokens + 1] = table.concat(current)
  end

  return tokens
end

---Parse a list of tokens into a key=value / positional table.
---When opts.preserve_nil is true, keyword values that resolve to nil are stored
---as vim.NIL so callers can distinguish "explicitly cleared" from "not specified."
---Positional nils remain absent regardless of this option.
---@param tokens string[]
---@param opts? flemma.utilities.modeline.ParseOpts
---@return flemma.utilities.modeline.ParsedTokens
local function parse_tokens(tokens, opts)
  local preserve_nil = opts and opts.preserve_nil
  local result = {}
  local positional_index = 0

  for _, token in ipairs(tokens) do
    local key, raw = token:match(KEY_VALUE_PATTERN)
    if key then
      local value = resolve_value(raw)
      if value == nil and preserve_nil then
        result[key] = vim.NIL
      else
        result[key] = value
      end
    elseif token ~= "" then
      positional_index = positional_index + 1
      result[positional_index] = resolve_value(token)
    end
  end

  return result
end

---Parse a string array (e.g. command fargs) starting at a given index
---@param args string[]|any
---@param start_index? integer 1-based start index (default 1)
---@param opts? flemma.utilities.modeline.ParseOpts
---@return flemma.utilities.modeline.ParsedTokens
function M.parse_args(args, start_index, opts)
  if type(args) ~= "table" then
    return {}
  end

  local tokens = {}
  for i = start_index or 1, #args do
    tokens[#tokens + 1] = args[i]
  end

  return parse_tokens(tokens, opts)
end

---Parse a single string into key=value / positional table, with quote-aware tokenization
---@param line string|any
---@param opts? flemma.utilities.modeline.ParseOpts
---@return flemma.utilities.modeline.ParsedTokens
function M.parse(line, opts)
  if type(line) ~= "string" or line == "" then
    return {}
  end

  local tokens = scan(line)
  return parse_tokens(tokens, opts)
end

---Split a raw value on a single-character delimiter, respecting quoted regions.
---@param raw string
---@param delimiter string Single-character delimiter (e.g. ";", ",")
---@return string[]|nil items List of raw segments, or nil if no unquoted delimiter exists
function M.split_on(raw, delimiter)
  return split_on(raw, delimiter)
end

---Parse a "primary;key=value;key=value" matrix-parameter string (RFC 3986 §3.3 style).
---The primary is the first ';'-segment; the remaining segments run through the
---token grammar (parse_args), so quoting, coercion, comma lists, last-wins
---repeated keys, and preserve_nil are all inherited rather than re-implemented.
---Segments that do not parse as key=value are returned verbatim in `extras`
---for the caller to surface or ignore — they never become parameters.
---@param value string|any Non-string values pass through as the primary, untouched
---@param opts? flemma.utilities.modeline.ParseOpts
---@return string|any primary
---@return table<string, boolean|number|string|table> params
---@return string[] extras Raw segments after the primary that are not key=value pairs
function M.parse_matrix(value, opts)
  if type(value) ~= "string" or value == "" then
    return value, {}, {}
  end
  local segments = split_on(value, ";")
  if not segments then
    return value, {}, {}
  end
  local parsed = M.parse_args(segments, 2, opts)
  local params = {}
  for key, parameter_value in pairs(parsed) do
    if type(key) == "string" then
      params[key] = parameter_value
    end
  end
  local extras = {}
  for i = 2, #segments do
    if segments[i] ~= "" and not segments[i]:match(KEY_VALUE_PATTERN) then
      extras[#extras + 1] = segments[i]
    end
  end
  return segments[1], params, extras
end

return M
