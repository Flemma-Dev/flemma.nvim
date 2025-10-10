local ast = require("flemma.ast")

local M = {}

-- Utilities
local function url_decode(str)
  if not str then return nil end
  str = string.gsub(str, "+", " ")
  str = string.gsub(str, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
  return str
end

-- Unified segment parser: parse text for {{ }} expressions and @./ file references
-- Returns array of AST segments (text, expression, file_reference)
-- Note: <thinking> tags are NOT parsed here - only in @Assistant messages
local function parse_segments(text)
  local segments = {}
  if text == "" or text == nil then return segments end
  local idx = 1
  local s = text

  local function emit_text(str) 
    if str and #str > 0 then 
      table.insert(segments, ast.text(str)) 
    end 
  end

  while idx <= #s do
    local expr_start, expr_end, expr_code = s:find("{{(.-)}}", idx)
    local file_start, file_end, file_full = s:find("@(%.%.?%/[%.%/]*%S+)", idx)

    local next_kind, next_start, next_end, payload = nil, nil, nil, nil

    -- Choose earliest match
    if expr_start and (not file_start or expr_start < file_start) then
      next_kind, next_start, next_end, payload = "expr", expr_start, expr_end, expr_code
    elseif file_start then
      next_kind, next_start, next_end, payload = "file", file_start, file_end, file_full
    end

    if not next_kind then
      emit_text(s:sub(idx))
      break
    end

    -- Emit preceding text
    emit_text(s:sub(idx, next_start - 1))

    if next_kind == "expr" then
      table.insert(segments, ast.expression(payload, { line = 0, col = next_start }))
    elseif next_kind == "file" then
      local raw_file_match, mime_with_punct = payload:match("^([^;]+);type=(.+)$")
      local mime_override = nil
      local trailing_punct = nil
      
      if not raw_file_match then
        raw_file_match = payload
        local filename_no_punct = raw_file_match:gsub("[%p]+$", "")
        trailing_punct = raw_file_match:sub(#filename_no_punct + 1)
        raw_file_match = filename_no_punct
      else
        local mime_no_punct = mime_with_punct:gsub("[%p]+$", "")
        trailing_punct = mime_with_punct:sub(#mime_no_punct + 1)
        mime_override = mime_no_punct
      end
      
      local cleaned_path = url_decode(raw_file_match)

      table.insert(segments, ast.file_reference(
        mime_override and (raw_file_match .. ";type=" .. mime_override) or raw_file_match,
        cleaned_path,
        mime_override,
        #trailing_punct > 0 and trailing_punct or nil,
        { line = 0, col = next_start }
      ))
    end
    idx = next_end + 1
  end

  return segments
end

-- Parse assistant messages - only extract <thinking> tags, treat rest as text
local function parse_assistant_segments(text)
  local segments = {}
  if text == "" or text == nil then return { ast.text("") } end
  local idx = 1
  local s = text
  
  local function emit_text(str)
    if str and #str > 0 then
      table.insert(segments, ast.text(str))
    end
  end
  
  while idx <= #s do
    local think_start, think_end, think_content = s:find("<thinking>(.-)</thinking>", idx)
    
    if not think_start then
      emit_text(s:sub(idx))
      break
    end
    
    -- Emit text before thinking tag
    emit_text(s:sub(idx, think_start - 1))
    
    -- Add thinking node
    table.insert(segments, ast.thinking(think_content, { line = 0, col = think_start }))
    
    idx = think_end + 1
  end
  
  return segments
end

-- Split into frontmatter and body lines. Frontmatter fence: ```language ... ```
local function parse_frontmatter(lines)
  if not lines[1] then return nil, nil, lines, 1 end
  local language = lines[1]:match("^```(%w+)%s*$")
  if not language then return nil, nil, lines, 1 end

  local fm_lines = {}
  local body_start = 2
  local closing_idx = nil
  for i=2,#lines do
    if lines[i]:match("^```%s*$") then
      closing_idx = i
      body_start = i + 1
      break
    end
    table.insert(fm_lines, lines[i])
  end
  if not closing_idx then
    return nil, nil, lines, 1
  end
  local body = {}
  for i = body_start, #lines do table.insert(body, lines[i]) end
  local fm = ast.frontmatter(language, table.concat(fm_lines, "\n"), { start_line = 1, end_line = closing_idx })
  return fm, fm_lines, body, body_start
end

-- Parse message role line: @Role:
-- line_offset: offset to add to line numbers (for frontmatter adjustment)
local function parse_message(lines, start_idx, line_offset)
  line_offset = line_offset or 0
  local line = lines[start_idx]
  if not line then return nil, start_idx end
  local role = line:match("^@([%w]+):")
  if not role then return nil, start_idx end

  local content_first = line:sub(#role + 3)
  local content_lines = {}
  if content_first and content_first:match("%S") then
    local trimmed = content_first:gsub("^%s*", "")
    table.insert(content_lines, trimmed)
  end

  local i = start_idx + 1
  while i <= #lines do
    local next_line = lines[i]
    if next_line:match("^@[%w]+:") then break end
    table.insert(content_lines, next_line)
    i = i + 1
  end

  local content = table.concat(content_lines, "\n")
  
  -- For @Assistant messages, only parse thinking tags (no expressions or file refs)
  local segments
  if role == "Assistant" then
    segments = parse_assistant_segments(content)
  else
    segments = parse_segments(content)
  end

  local msg = ast.message(role, segments, { 
    start_line = start_idx + line_offset, 
    end_line = (i - 1) + line_offset 
  })
  return msg, (i - 1)
end

function M.parse_lines(lines)
  lines = lines or {}
  local errors = {}
  local fm, _, body, body_start = parse_frontmatter(lines)
  local messages = {}
  local i = body and 1 or 1
  local content_lines = body or lines
  -- Calculate line offset: if frontmatter exists, messages start after it
  local line_offset = body and (body_start - 1) or 0

  while i <= #content_lines do
    local msg, last = parse_message(content_lines, i, line_offset)
    if msg then
      table.insert(messages, msg)
      i = last + 1
    else
      i = i + 1
    end
  end

  local doc = ast.document(fm, messages, errors, { start_line = 1, end_line = #lines })
  return doc
end

-- Parse inline content (for include() results) - no frontmatter, no message roles
-- Just scan for @./ file references and {{ }} expressions
function M.parse_inline_content(text)
  return parse_segments(text or "")
end

return M
