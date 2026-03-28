---@class flemma.parser.scanner
---
--- Lexical scanner for finding closing delimiters in template expressions.
--- Understands Lua string literals, comments, and brace nesting so that
--- `}}` or `%}` inside strings/comments/tables is correctly skipped.
local M = {}

--- Check if position starts a long bracket (`[=*[`) and return its level.
---@param s string
---@param pos integer
---@return integer|nil level  Number of `=` signs, or nil if not a long bracket
local function long_bracket_level(s, pos)
  if s:sub(pos, pos) ~= "[" then
    return nil
  end
  local i = pos + 1
  local len = #s
  while i <= len and s:sub(i, i) == "=" do
    i = i + 1
  end
  if i <= len and s:sub(i, i) == "[" then
    return i - pos - 1 -- number of = signs
  end
  return nil
end

--- Skip past a long bracket close `]=*]` matching the given level.
---@param s string
---@param pos integer  Current position (first `]`)
---@param level integer  Number of `=` signs to match
---@return integer  Position after the closing long bracket, or #s + 1 if not found
local function skip_long_bracket_close(s, pos, level)
  local close = "]" .. ("="):rep(level) .. "]"
  local close_pos = s:find(close, pos, true)
  if close_pos then
    return close_pos + #close
  end
  return #s + 1 -- unterminated: consume rest
end

--- Skip past a quoted string (single or double).
---@param s string
---@param pos integer  Position of the opening quote character
---@return integer  Position after the closing quote, or #s + 1 if unterminated
local function skip_quoted_string(s, pos)
  local quote = s:sub(pos, pos)
  local i = pos + 1
  local len = #s
  while i <= len do
    local c = s:sub(i, i)
    if c == "\\" then
      i = i + 2 -- skip escape + next char
    elseif c == quote then
      return i + 1 -- past closing quote
    else
      i = i + 1
    end
  end
  return len + 1 -- unterminated
end

--- Skip past a single-line comment (from `--` to newline or EOF).
---@param s string
---@param pos integer  Position of the first `-`
---@return integer  Position after the newline, or #s + 1 if at EOF
local function skip_line_comment(s, pos)
  local nl = s:find("\n", pos, true)
  if nl then
    return nl + 1
  end
  return #s + 1
end

--- Find the closing delimiter for a template expression or code block.
---
--- Walks character-by-character from `start_pos`, skipping over Lua string
--- literals and comments, tracking brace depth (expression mode only).
--- Returns positions matching `string.find` semantics.
---
---@param s string         Full input string (may contain newlines)
---@param start_pos integer Position to start scanning (1-indexed)
---@param mode "expression"|"code"  Closing delimiter to find
---@return integer|nil close_start  Start of closing delimiter (includes trim dash)
---@return integer|nil close_end    End of closing delimiter
function M.find_closing(s, start_pos, mode)
  local len = #s
  local i = start_pos
  local depth = 0
  local is_expr = mode == "expression"

  while i <= len do
    local c = s:sub(i, i)

    -- Quoted strings
    if c == '"' or c == "'" then
      i = skip_quoted_string(s, i)

    -- Long strings: [=*[
    elseif c == "[" then
      local level = long_bracket_level(s, i)
      if level then
        i = skip_long_bracket_close(s, i + level + 2, level)
      else
        i = i + 1
      end

    -- Comments: -- (single-line or long)
    elseif c == "-" and s:sub(i + 1, i + 1) == "-" then
      local after_dashes = i + 2
      local level = long_bracket_level(s, after_dashes)
      if level then
        -- Long comment: --[=*[ ... ]=*]
        i = skip_long_bracket_close(s, after_dashes + level + 2, level)
      else
        -- Single-line comment: -- ... \n
        i = skip_line_comment(s, after_dashes)
      end

    -- Expression mode: brace tracking and }} detection
    elseif is_expr and c == "{" then
      depth = depth + 1
      i = i + 1
    elseif is_expr and c == "}" then
      if depth > 0 then
        depth = depth - 1
        i = i + 1
      else
        -- At depth 0: check for closing }}
        if i + 1 <= len and s:sub(i + 1, i + 1) == "}" then
          -- Check for trim dash before }}
          if i - 1 >= start_pos and s:sub(i - 1, i - 1) == "-" then
            return i - 1, i + 1 -- -}}
          end
          return i, i + 1 -- }}
        end
        i = i + 1 -- lone } at depth 0, keep scanning
      end

    -- Code mode: %} detection
    elseif not is_expr and c == "%" and i + 1 <= len and s:sub(i + 1, i + 1) == "}" then
      -- Check for trim dash before %}
      if i - 1 >= start_pos and s:sub(i - 1, i - 1) == "-" then
        return i - 1, i + 1 -- -%}
      end
      return i, i + 1 -- %}
    else
      i = i + 1
    end
  end

  return nil, nil
end

return M
