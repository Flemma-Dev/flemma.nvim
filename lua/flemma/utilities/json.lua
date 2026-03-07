--- Centralized JSON encode/decode for Flemma
--- Wraps vim.json with luanil options so JSON null always becomes Lua nil.
--- All Flemma code MUST use this module instead of vim.fn.json_* or vim.json.* directly.
---@class flemma.utilities.Json
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

---Encode a single JSON value recursively with sorted keys.
---@param value any
---@return string
local function encode_value(value)
  if value == vim.NIL then
    return "null"
  end

  local t = type(value)

  if value == nil then
    return "null"
  elseif t == "boolean" then
    return value and "true" or "false"
  elseif t == "number" then
    -- Use vim.json.encode for correct number formatting (integers, floats, special values)
    return vim.json.encode(value)
  elseif t == "string" then
    -- Use vim.json.encode for correct string escaping
    return vim.json.encode(value)
  elseif t == "table" then
    -- Detect array vs object: vim.empty_dict() marks explicit empty objects;
    -- otherwise, a table with consecutive integer keys starting at 1 is an array.
    local is_dict = vim.tbl_isempty(value) and getmetatable(value) ~= nil
    if not is_dict then
      -- Check if it's an array (sequential integer keys from 1)
      local count = 0
      for _ in pairs(value) do
        count = count + 1
      end
      is_dict = count > 0 and count ~= #value
    end

    if is_dict or (vim.tbl_isempty(value) and getmetatable(value) ~= nil) then
      -- Object: sort keys alphabetically
      local keys = {}
      for k in pairs(value) do
        table.insert(keys, k)
      end
      table.sort(keys)

      local parts = {}
      for _, k in ipairs(keys) do
        table.insert(parts, encode_value(k) .. ":" .. encode_value(value[k]))
      end
      return "{" .. table.concat(parts, ",") .. "}"
    else
      -- Array: preserve element order
      if #value == 0 and vim.tbl_isempty(value) then
        return "[]"
      end
      local parts = {}
      for _, v in ipairs(value) do
        table.insert(parts, encode_value(v))
      end
      return "[" .. table.concat(parts, ",") .. "]"
    end
  elseif t == "userdata" then
    -- Handle vim.NIL (already covered above, but as safety net)
    return "null"
  end

  -- Fallback: delegate to vim.json.encode
  return vim.json.encode(value)
end

---Encode a Lua value into a JSON string with deterministic key ordering.
---All object keys are sorted alphabetically at every nesting level.
---Optional `trailing_keys` moves specified keys to the end (in given order) at the top level only.
---@param value any Lua value to encode
---@param trailing_keys? string[] Keys to place at the end of the top-level object, in order
---@return string
function M.encode_ordered(value, trailing_keys)
  if value == nil then
    return "null"
  end

  -- If no trailing_keys or value is not a table, use the recursive encoder directly
  if not trailing_keys or #trailing_keys == 0 or type(value) ~= "table" then
    return encode_value(value)
  end

  -- Build a set of trailing keys for fast lookup
  local trailing_set = {}
  for _, k in ipairs(trailing_keys) do
    trailing_set[k] = true
  end

  -- Collect non-trailing keys and sort them
  local sorted_keys = {}
  for k in pairs(value) do
    if not trailing_set[k] then
      table.insert(sorted_keys, k)
    end
  end
  table.sort(sorted_keys)

  -- Build parts: sorted keys first, then trailing keys in specified order
  local parts = {}
  for _, k in ipairs(sorted_keys) do
    table.insert(parts, encode_value(k) .. ":" .. encode_value(value[k]))
  end
  for _, k in ipairs(trailing_keys) do
    if value[k] ~= nil then
      table.insert(parts, encode_value(k) .. ":" .. encode_value(value[k]))
    end
  end

  return "{" .. table.concat(parts, ",") .. "}"
end

return M
