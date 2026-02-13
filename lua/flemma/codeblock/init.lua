--- Generic fenced code block utilities
--- Provides parsing and formatting for fenced blocks
---@class flemma.Codeblock
local M = {}

local parsers = require("flemma.codeblock.parsers")

M.register = parsers.register
M.get = parsers.get
M.has = parsers.has
M.parse = parsers.parse

---Determine fence length needed for content
---Scans for the longest backtick sequence and adds 1
---@param content string The content that will be fenced
---@return string fence The fence string (at least 3 backticks)
function M.get_fence(content)
  local max_ticks = 0
  for ticks in content:gmatch("`+") do
    max_ticks = math.max(max_ticks, #ticks)
  end
  return string.rep("`", math.max(3, max_ticks + 1))
end

---@class flemma.codeblock.FencedBlock
---@field language? string Language identifier (nil if omitted)
---@field content string Fenced block content lines joined by newline
---@field fence_length integer Backtick count of the opening fence

---Parse a fenced code block from lines
---@param lines string[] Array of lines
---@param start_idx number 1-based index to start parsing
---@return flemma.codeblock.FencedBlock|nil block
---@return number end_idx Index of the closing fence (or start_idx if no block)
function M.parse_fenced_block(lines, start_idx)
  local line = lines[start_idx]
  if not line then
    return nil, start_idx
  end

  local fence, lang = line:match("^(`+)([%w:._%-]*)%s*$")
  if not fence then
    return nil, start_idx
  end

  local fence_len = #fence
  local content_lines = {}
  local i = start_idx + 1

  while i <= #lines do
    local close_fence = lines[i]:match("^(`+)%s*$")
    if close_fence and #close_fence >= fence_len then
      return {
        language = lang ~= "" and lang or nil,
        content = table.concat(content_lines, "\n"),
        fence_length = fence_len,
      },
        i
    end
    table.insert(content_lines, lines[i])
    i = i + 1
  end

  return nil, start_idx
end

---Skip blank lines to find next non-empty line
---@param lines string[] Array of lines
---@param start_idx number 1-based index to start from
---@return number next_idx Index of first non-blank line (or past end if none)
function M.skip_blank_lines(lines, start_idx)
  local i = start_idx
  while i <= #lines and lines[i]:match("^%s*$") do
    i = i + 1
  end
  return i
end

return M
