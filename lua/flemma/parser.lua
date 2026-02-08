local ast = require("flemma.ast")
local codeblock = require("flemma.codeblock")

---@class flemma.Parser
local M = {}

local TOOL_USE_PATTERN = "^%*%*Tool Use:%*%*%s*`([^`]+)`%s*%(`([^)]+)`%)"
local TOOL_RESULT_PATTERN = "^%*%*Tool Result:%*%*%s*`([^`]+)`"
local TOOL_RESULT_ERROR_PATTERN = "%s*%(error%)%s*$"

---@param str string|nil
---@return string|nil
local function url_decode(str)
  if not str then
    return nil
  end
  str = string.gsub(str, "+", " ")
  str = string.gsub(str, "%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end)
  return str
end

--- Escape a string for use inside a Lua single-quoted string literal.
---@param str string
---@return string
local function lua_string_escape(str)
  str = str:gsub("\\", "\\\\")
  str = str:gsub("'", "\\'")
  str = str:gsub("\n", "\\n")
  return str
end

--- Unified segment parser: parse text for {{ }} expressions and @./ file references
--- Returns array of AST segments (text, expression)
--- Note: <thinking> tags are NOT parsed here - only in @Assistant messages
---@param text string|nil
---@param base_line integer|nil 1-indexed line number for accurate position tracking
---@return flemma.ast.Segment[]
local function parse_segments(text, base_line)
  local segments = {}
  if text == "" or text == nil then
    return segments
  end
  base_line = base_line or 0

  local idx = 1
  local s = text

  local function emit_text(str)
    if str and #str > 0 then
      table.insert(segments, ast.text(str))
    end
  end

  local function char_to_line_col(pos)
    -- Count newlines up to pos to determine line and column
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
      local line, col = char_to_line_col(next_start)
      table.insert(segments, ast.expression(payload --[[@as string]], { start_line = line, start_col = col }))
    elseif next_kind == "file" then
      ---@cast payload string
      local raw_file_match, mime_with_punct = payload:match("^([^;]+);type=(.+)$")
      local mime_override = nil
      local trailing_punct

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

      -- URL-decode and escape the path for use in a Lua string literal
      local cleaned_path = url_decode(raw_file_match)
      ---@cast cleaned_path string
      local escaped_path = lua_string_escape(cleaned_path)
      local line, col = char_to_line_col(next_start)

      -- Build the include() expression code
      local opts_parts = { "binary = true" }
      if mime_override then
        opts_parts[#opts_parts + 1] = "mime = '" .. lua_string_escape(mime_override) .. "'"
      end
      local code = "include('" .. escaped_path .. "', { " .. table.concat(opts_parts, ", ") .. " })"

      table.insert(segments, ast.expression(code, { start_line = line, start_col = col }))

      -- Emit trailing punctuation as a separate text segment
      if #trailing_punct > 0 then
        emit_text(trailing_punct)
      end
    end
    idx = next_end + 1
  end

  return segments
end

--- Parse user messages - handle **Tool Result:** blocks and regular content
---@param lines string[]|nil Content lines (without the @You: prefix)
---@param base_line_num integer Line number where the message content starts (1-indexed)
---@param diagnostics flemma.ast.Diagnostic[]|nil Optional table to collect parsing diagnostics
---@return flemma.ast.Segment[] segments
---@return flemma.ast.Diagnostic[] diagnostics
local function parse_user_segments(lines, base_line_num, diagnostics)
  local segments = {}
  diagnostics = diagnostics or {}
  if not lines or #lines == 0 then
    return { ast.text("") }, diagnostics
  end

  local function emit_text_with_parsing(text, line_num)
    if text and #text > 0 then
      local parsed = parse_segments(text, line_num)
      for _, seg in ipairs(parsed) do
        table.insert(segments, seg)
      end
    end
  end

  local i = 1
  while i <= #lines do
    local line = lines[i]
    local current_line_num = base_line_num + i - 1

    -- Check for **Tool Result:** marker
    local tool_use_id = line:match(TOOL_RESULT_PATTERN)
    if tool_use_id then
      local is_error = line:match(TOOL_RESULT_ERROR_PATTERN) ~= nil
      local result_start_line = current_line_num

      -- Skip blank lines to find content
      local content_start = codeblock.skip_blank_lines(lines, i + 1)

      -- Check if line starts with backticks (fence opener)
      local content_line = lines[content_start]
      local has_fence_opener = content_line and content_line:match("^`+")

      -- Try to parse a fenced code block
      local block, block_end = codeblock.parse_fenced_block(lines, content_start)

      if block then
        local result_content

        if block.language then
          -- Parse the content based on language
          local content, parse_err = codeblock.parse(block.language, block.content)

          if parse_err then
            table.insert(diagnostics, {
              type = "tool_result",
              severity = "warning",
              error = "Failed to parse tool result: " .. parse_err,
              position = { start_line = result_start_line },
            })
            -- Treat as plain text result
            result_content = block.content
          else
            -- If parsed to a simple value, convert to string for API
            if type(content) == "table" then
              result_content = vim.fn.json_encode(content)
            else
              result_content = tostring(content)
            end
          end
        else
          -- No language specified - treat as plain text
          result_content = block.content
        end

        table.insert(
          segments,
          ast.tool_result(tool_use_id, result_content, {
            is_error = is_error,
            start_line = result_start_line,
            end_line = base_line_num + block_end - 1,
          })
        )
        i = block_end + 1
      elseif has_fence_opener then
        -- Started a fence but didn't close it properly - this is an error
        table.insert(diagnostics, {
          type = "tool_result",
          severity = "warning",
          error = "Unclosed fenced code block in tool result (missing closing fence)",
          position = { start_line = result_start_line },
        })
        -- Skip to end of message (next @Role: marker) to avoid parsing garbage
        local j = content_start + 1
        while j <= #lines and not lines[j]:match("^@[%w]+:") do
          j = j + 1
        end
        i = j
      else
        -- No fence at all - tool results require a fenced code block
        table.insert(diagnostics, {
          type = "tool_result",
          severity = "warning",
          error = "Tool result requires a fenced code block",
          position = { start_line = result_start_line },
        })
        -- Skip to next line and continue
        i = content_start
      end
    else
      -- Regular content line - parse for expressions and file references
      emit_text_with_parsing(line, current_line_num)
      if i < #lines then
        table.insert(segments, ast.text("\n"))
      end
      i = i + 1
    end
  end

  return segments, diagnostics
end

--- Parse assistant messages - extract <thinking> tags and **Tool Use:** blocks, treat rest as text
---@param lines string[]|nil Content lines (without the @Assistant: prefix)
---@param base_line_num integer Line number where the message content starts (1-indexed)
---@param diagnostics flemma.ast.Diagnostic[]|nil Optional table to collect parsing diagnostics
---@return flemma.ast.Segment[] segments
---@return flemma.ast.Diagnostic[] diagnostics
local function parse_assistant_segments(lines, base_line_num, diagnostics)
  local segments = {}
  diagnostics = diagnostics or {}
  if not lines or #lines == 0 then
    return { ast.text("") }, diagnostics
  end

  local function emit_text(str)
    if str and #str > 0 then
      table.insert(segments, ast.text(str))
    end
  end

  local i = 1
  while i <= #lines do
    local line = lines[i]
    local current_line_num = base_line_num + i - 1

    -- Check for thinking tags on their own lines
    -- Patterns:
    --   <thinking> or <thinking provider:signature="..."> (opening tag)
    --   <thinking provider:signature="..."/> (self-closing tag)
    -- Supports any provider:signature attribute (e.g., vertex:signature, anthropic:signature)
    local self_closing_sig = line:match('^<thinking%s+%w+:signature="([^"]*)"%s*/>$')
    local open_tag_sig = line:match('^<thinking%s+%w+:signature="([^"]*)"%s*>$')
    local simple_open_tag = line:match("^<thinking>$")

    if self_closing_sig then
      -- Self-closing tag with signature, no content
      local thinking_line = current_line_num
      table.insert(
        segments,
        ast.thinking("", {
          start_line = thinking_line,
          end_line = thinking_line,
        }, self_closing_sig)
      )
      i = i + 1
    elseif open_tag_sig or simple_open_tag then
      local signature = open_tag_sig -- nil for simple open tag
      local thinking_start_line = current_line_num
      local thinking_content_lines = {}
      i = i + 1

      -- Collect thinking content until closing tag
      while i <= #lines do
        if lines[i]:match("^</thinking>$") then
          local thinking_end_line = base_line_num + i - 1
          local thinking_content = table.concat(thinking_content_lines, "\n")
          table.insert(
            segments,
            ast.thinking(thinking_content, {
              start_line = thinking_start_line,
              end_line = thinking_end_line,
            }, signature)
          )
          i = i + 1
          break
        else
          table.insert(thinking_content_lines, lines[i])
          i = i + 1
        end
      end
    elseif line:match(TOOL_USE_PATTERN) then
      local tool_name, tool_id = line:match(TOOL_USE_PATTERN)
      local tool_start_line = current_line_num

      -- Skip blank lines to find the code block
      local block_start = codeblock.skip_blank_lines(lines, i + 1)

      -- Check if line starts with backticks (fence opener)
      local content_line = lines[block_start]
      local has_fence_opener = content_line and content_line:match("^`+")

      local block, block_end = codeblock.parse_fenced_block(lines, block_start)

      if block then
        -- Parse the JSON content
        local input, parse_err = codeblock.parse(block.language or "json", block.content)

        if parse_err then
          table.insert(diagnostics, {
            type = "tool_use",
            severity = "warning",
            error = "Failed to parse tool input: " .. parse_err,
            position = { start_line = tool_start_line },
          })
          -- Skip to end of malformed block
          local j = block_start + 1
          while j <= #lines and not lines[j]:match("^@[%w]+:") do
            j = j + 1
          end
          i = j
        else
          table.insert(
            segments,
            ast.tool_use(tool_id, tool_name, input, {
              start_line = tool_start_line,
              end_line = base_line_num + block_end - 1,
            })
          )
          i = block_end + 1
        end
      elseif has_fence_opener then
        -- Started a fence but didn't close it properly
        table.insert(diagnostics, {
          type = "tool_use",
          severity = "warning",
          error = "Unclosed fenced code block in tool use (missing closing fence)",
          position = { start_line = tool_start_line },
        })
        -- Skip to end of message
        local j = block_start + 1
        while j <= #lines and not lines[j]:match("^@[%w]+:") do
          j = j + 1
        end
        i = j
      else
        -- No fence at all
        table.insert(diagnostics, {
          type = "tool_use",
          severity = "warning",
          error = "Tool use requires a fenced code block with JSON input",
          position = { start_line = tool_start_line },
        })
        i = block_start
      end
    else
      -- Regular text line
      emit_text(line)
      if i < #lines then
        emit_text("\n")
      end
      i = i + 1
    end
  end

  return segments, diagnostics
end

--- Split into frontmatter and body lines. Frontmatter fence: ```language ... ```
---@param lines string[]
---@return flemma.ast.FrontmatterNode|nil frontmatter
---@return string[]|nil fm_lines
---@return string[] body
---@return integer body_start
local function parse_frontmatter(lines)
  if not lines[1] then
    return nil, nil, lines, 1
  end
  local language = lines[1]:match("^```(%w+)%s*$")
  if not language then
    return nil, nil, lines, 1
  end

  local fm_lines = {}
  local body_start = 2
  local closing_idx = nil
  for i = 2, #lines do
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
  for i = body_start, #lines do
    table.insert(body, lines[i])
  end
  local fm = ast.frontmatter(language, table.concat(fm_lines, "\n"), { start_line = 1, end_line = closing_idx })
  return fm, fm_lines, body, body_start
end

--- Parse message role line: @Role:
---@param lines string[]
---@param start_idx integer
---@param line_offset integer|nil Offset to add to line numbers (for frontmatter adjustment)
---@param diagnostics flemma.ast.Diagnostic[]|nil Optional table to collect parsing diagnostics
---@return flemma.ast.MessageNode|nil message
---@return integer last_line_idx
---@return flemma.ast.Diagnostic[] diagnostics
local function parse_message(lines, start_idx, line_offset, diagnostics)
  line_offset = line_offset or 0
  diagnostics = diagnostics or {}
  local line = lines[start_idx]
  if not line then
    return nil, start_idx, diagnostics
  end
  local role = line:match("^@([%w]+):")
  if not role then
    return nil, start_idx, diagnostics
  end

  local content_first = line:sub(#role + 3)
  local content_lines = {}
  if content_first and content_first:match("%S") then
    local trimmed = content_first:gsub("^%s*", "")
    table.insert(content_lines, trimmed)
  end

  local i = start_idx + 1
  while i <= #lines do
    local next_line = lines[i]
    if next_line:match("^@[%w]+:") then
      break
    end
    table.insert(content_lines, next_line)
    i = i + 1
  end

  local segments
  local content_start_line = (content_first and content_first:match("%S")) and start_idx + line_offset
    or (start_idx + 1 + line_offset)

  if role == "Assistant" then
    -- Parse thinking tags and tool_use blocks
    local msg_diagnostics
    segments, msg_diagnostics = parse_assistant_segments(content_lines, content_start_line, {})
    for _, diag in ipairs(msg_diagnostics) do
      table.insert(diagnostics, diag)
    end
  elseif role == "You" then
    -- Parse tool_result blocks and regular content
    local msg_diagnostics
    segments, msg_diagnostics = parse_user_segments(content_lines, content_start_line, {})
    for _, diag in ipairs(msg_diagnostics) do
      table.insert(diagnostics, diag)
    end
  else
    -- Other roles (System, etc.) - parse expressions and file references
    local content = table.concat(content_lines, "\n")
    segments = parse_segments(content, content_start_line)
  end

  local msg = ast.message(role, segments, {
    start_line = start_idx + line_offset,
    end_line = (i - 1) + line_offset,
  })
  return msg, (i - 1), diagnostics
end

---@param lines string[]|nil
---@return flemma.ast.DocumentNode
function M.parse_lines(lines)
  lines = lines or {}
  local errors = {}
  local fm, _, body, body_start = parse_frontmatter(lines)
  local messages = {}
  local i = 1
  local content_lines = body or lines
  -- Calculate line offset: if frontmatter exists, messages start after it
  local line_offset = body and (body_start - 1) or 0

  while i <= #content_lines do
    local msg, last, diagnostics = parse_message(content_lines, i, line_offset, {})
    if msg then
      table.insert(messages, msg)
      for _, diag in ipairs(diagnostics) do
        table.insert(errors, diag)
      end
      i = last + 1
    else
      i = i + 1
    end
  end

  local doc = ast.document(fm, messages, errors, { start_line = 1, end_line = #lines })
  return doc
end

--- Parse inline content (for include() results) - no frontmatter, no message roles
--- Just scan for @./ file references and {{ }} expressions
---@param text string|nil
---@return flemma.ast.Segment[]
function M.parse_inline_content(text)
  return parse_segments(text or "")
end

--- Get parsed document with automatic caching based on buffer changedtick
--- Returns cached AST if buffer unchanged, otherwise parses and caches
---@param bufnr integer
---@return flemma.ast.DocumentNode
function M.get_parsed_document(bufnr)
  local state = require("flemma.state")
  local buffer_state = state.get_buffer_state(bufnr)
  local current_tick = vim.api.nvim_buf_get_changedtick(bufnr)

  -- Return cached if still valid
  if buffer_state.ast_cache and buffer_state.ast_cache.changedtick == current_tick then
    return buffer_state.ast_cache.document
  end

  -- Parse and cache
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local doc = M.parse_lines(lines)

  buffer_state.ast_cache = {
    changedtick = current_tick,
    document = doc,
  }

  return doc
end

return M
