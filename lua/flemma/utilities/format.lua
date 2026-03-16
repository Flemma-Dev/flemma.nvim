--- tmux-style format string expansion with conditionals and lazy evaluation.
---
--- Syntax (subset of tmux `#{...}` format language):
---   - `#{name}`                         — variable expansion (lazy-resolved from vars table)
---   - `#{?cond,true-value,false-value}` — ternary conditional (either branch may be empty)
---   - `#{==:a,b}` / `#{!=:a,b}`         — string comparison (returns "1" or "0")
---   - `#{&&:a,b}` / `#{||:a,b}`         — boolean operators (returns "1" or "0")
---   - `#,`                              — literal comma
---
--- Truthiness follows tmux rules: a value is **true** if it is non-empty and not
--- the string `"0"`. Everything else (empty string, `"0"`, `nil`) is false.
---
--- The `vars` table may use a `__index` metamethod for lazy evaluation — resolvers
--- are only called when the format string actually references the variable, and the
--- result is cached for repeated access within the same expansion.
---@class flemma.utilities.Format
local M = {}

---Check tmux-style truthiness: true if non-empty and not "0".
---@param value string
---@return boolean
local function is_truthy(value)
  return value ~= "" and value ~= "0"
end

---Split a format substring into arguments at depth-0 commas.
---Respects `#{` nesting so commas inside nested expressions are not treated as
---argument separators.  Handles `#,` escape sequences.
---@param text string The text to split (already inside a `#{...}`)
---@param count integer Expected number of parts (splits into at most `count`)
---@return string[] parts
local function split_args(text, count)
  local parts = {}
  local depth = 0
  local start = 1
  local i = 1
  while i <= #text do
    local char = text:sub(i, i)
    if text:sub(i, i + 1) == "#{" then
      depth = depth + 1
      i = i + 2
    elseif char == "}" and depth > 0 then
      depth = depth - 1
      i = i + 1
    elseif text:sub(i, i + 1) == "#," then
      -- Escaped comma — skip over, not a separator
      i = i + 2
    elseif char == "," and depth == 0 and #parts < count - 1 then
      parts[#parts + 1] = text:sub(start, i - 1)
      start = i + 1
      i = i + 1
    else
      i = i + 1
    end
  end
  parts[#parts + 1] = text:sub(start)
  return parts
end

---Find the matching closing `}` for a `#{` at position `open_pos`.
---@param text string
---@param open_pos integer Position of the `#` in `#{`
---@return integer|nil close_pos Position of the closing `}`
local function find_closing_brace(text, open_pos)
  local depth = 1
  local i = open_pos + 2 -- skip past `#{`
  while i <= #text do
    if text:sub(i, i + 1) == "#{" then
      depth = depth + 1
      i = i + 2
    elseif text:sub(i, i) == "}" then
      depth = depth - 1
      if depth == 0 then
        return i
      end
      i = i + 1
    else
      i = i + 1
    end
  end
  return nil
end

---Expand a single `#{...}` expression body (the content between `#{` and `}`).
---@param body string The expression body without the surrounding `#{` and `}`
---@param vars table Variable lookup table (may use `__index` for lazy resolution)
---@return string
local function expand_expression(body, vars)
  -- Ternary conditional: #{?cond,true,false}
  if body:sub(1, 1) == "?" then
    local args = split_args(body:sub(2), 3)
    local condition = M.expand(args[1] or "", vars)
    if is_truthy(condition) then
      return M.expand(args[2] or "", vars)
    else
      return M.expand(args[3] or "", vars)
    end
  end

  -- Comparison operators: #{==:a,b} #{!=:a,b}
  local cmp_op = body:match("^([=!]=):")
  if cmp_op then
    local args = split_args(body:sub(#cmp_op + 2), 2)
    local left = M.expand(args[1] or "", vars)
    local right = M.expand(args[2] or "", vars)
    if cmp_op == "==" then
      return left == right and "1" or "0"
    else
      return left ~= right and "1" or "0"
    end
  end

  -- Boolean operators: #{&&:a,b} #{||:a,b}
  local bool_op = body:match("^([&|][&|]):")
  if bool_op then
    local args = split_args(body:sub(4), 2)
    local left = M.expand(args[1] or "", vars)
    local right = M.expand(args[2] or "", vars)
    if bool_op == "&&" then
      return (is_truthy(left) and is_truthy(right)) and "1" or "0"
    else
      return (is_truthy(left) or is_truthy(right)) and "1" or "0"
    end
  end

  -- Variable lookup — expand the name first (allows nested references)
  local name = M.expand(body, vars)
  local value = vars[name]
  if value == nil then
    return ""
  end
  return tostring(value)
end

---Expand a tmux-style format string, resolving `#{...}` expressions and `#,` escapes.
---
---Example:
---```lua
---local vars = setmetatable({}, { __index = function(self, key)
---  local resolvers = { model = function() return "o3" end }
---  local fn = resolvers[key]
---  if not fn then return "" end
---  local v = fn() or ""
---  rawset(self, key, v)
---  return v
---end })
---
---format.expand("#{model}#{?#{thinking}, (#{thinking}),}", vars)
----- => "o3" (when thinking is empty)
----- => "o3 (high)" (when thinking is "high")
---```
---@param text string Format string
---@param vars table Variable lookup table
---@return string
function M.expand(text, vars)
  local result = {}
  local i = 1
  while i <= #text do
    if text:sub(i, i + 1) == "#{" then
      -- Find the matching closing brace
      local close = find_closing_brace(text, i)
      if close then
        local body = text:sub(i + 2, close - 1)
        result[#result + 1] = expand_expression(body, vars)
        i = close + 1
      else
        -- Unmatched #{, emit literally
        result[#result + 1] = "#{"
        i = i + 2
      end
    elseif text:sub(i, i + 1) == "#," then
      result[#result + 1] = ","
      i = i + 2
    else
      -- Collect plain text up to next `#` or end
      local next_hash = text:find("#", i + 1, true)
      if next_hash then
        result[#result + 1] = text:sub(i, next_hash - 1)
        i = next_hash
      else
        result[#result + 1] = text:sub(i)
        i = #text + 1
      end
    end
  end
  return table.concat(result)
end

return M
