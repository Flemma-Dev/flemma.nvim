--- Parse Lua template strings into AST segments.
---@class flemma.templating.Parser
local M = {}

local ast = require("flemma.ast")
local scanner = require("flemma.templating.scanner")

--- Parse text for {{ }} expressions and {% %} code blocks.
---@param text string|nil
---@param base_line integer|nil 1-indexed line number for accurate position tracking
---@return flemma.ast.Segment[]
function M.parse_segments(text, base_line)
  local segments = {}
  if text == "" or text == nil then
    return segments
  end
  base_line = base_line or 0

  local idx = 1
  local s = text

  ---@param pos integer
  ---@return integer line
  ---@return integer col
  local function char_to_line_col(pos)
    local line = base_line
    local last_newline = 0
    for i = 1, pos - 1 do
      if s:sub(i, i) == "\n" then
        line = line + 1
        last_newline = i
      end
    end
    local col = pos - last_newline
    return line, col
  end

  ---@param str string
  ---@param char_start integer
  local function emit_text(str, char_start)
    if str and #str > 0 then
      local start_line, start_col = char_to_line_col(char_start)
      local end_line = start_line
      local end_col = start_col + #str - 1
      for i = 1, #str do
        if str:sub(i, i) == "\n" then
          end_line = end_line + 1
        end
      end
      if end_line > start_line then
        local last_newline = str:find("\n[^\n]*$")
        end_col = #str - last_newline
      end
      table.insert(
        segments,
        ast.text(str, {
          start_line = start_line,
          start_col = start_col,
          end_line = end_line,
          end_col = end_col,
        })
      )
    end
  end

  while idx <= #s do
    local expr_start = s:find("{{", idx, true)
    local code_start = s:find("{%%", idx)

    local next_start, is_code
    if expr_start and code_start then
      if code_start < expr_start then
        next_start = code_start
        is_code = true
      else
        next_start = expr_start
        is_code = false
      end
    elseif code_start then
      next_start = code_start
      is_code = true
    elseif expr_start then
      next_start = expr_start
      is_code = false
    else
      emit_text(s:sub(idx), idx)
      break
    end

    emit_text(s:sub(idx, next_start - 1), idx)

    local trim_before = false
    local content_offset = 2
    if s:sub(next_start + 2, next_start + 2) == "-" then
      trim_before = true
      content_offset = 3
    end

    local close_mode = is_code and "code" or "expression"
    local close_start, close_end = scanner.find_closing(s, next_start + content_offset, close_mode)

    if not close_start then
      emit_text(s:sub(next_start), next_start)
      break
    end
    ---@cast close_end integer

    local trim_after = s:sub(close_start, close_start) == "-"
    local content_start = next_start + content_offset
    local content_end = close_start - 1
    local content = s:sub(content_start, content_end)

    local start_line, start_col = char_to_line_col(next_start)
    local end_line, end_col = char_to_line_col(close_end)

    local pos = {
      start_line = start_line,
      start_col = start_col,
      end_line = end_line,
      end_col = end_col,
    }

    local opts = nil
    if trim_before or trim_after then
      opts = {
        trim_before = trim_before or nil,
        trim_after = trim_after or nil,
      }
    end

    if is_code then
      table.insert(segments, ast.code(content, pos, opts))
    else
      table.insert(segments, ast.expression(content, pos, opts))
    end

    idx = close_end + 1
  end

  return segments
end

return M
