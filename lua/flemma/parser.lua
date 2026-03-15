local ast = require("flemma.ast")
local codeblock = require("flemma.codeblock")
local json = require("flemma.utilities.json")
local modeline = require("flemma.utilities.modeline")
local roles = require("flemma.utilities.roles")
local state = require("flemma.state")

---@class flemma.Parser
local M = {}

---@type (fun(doc: flemma.ast.DocumentNode, bufnr: integer): flemma.ast.DocumentNode)|nil
local post_parse_hook = nil

---@class flemma.parser.Snapshot
---@field frontmatter flemma.ast.FrontmatterNode|nil Frozen frontmatter node
---@field messages flemma.ast.MessageNode[] Frozen message nodes (all messages before resume point)
---@field errors flemma.ast.Diagnostic[] Diagnostics from frozen portion
---@field resume_line integer 1-indexed buffer line where incremental parsing resumes (first line NOT in snapshot)

local TOOL_USE_PATTERN = "^%*%*Tool Use:%*%*%s*`([^`]+)`%s*%(`([^)]+)`%)"
local TOOL_RESULT_PATTERN = "^%*%*Tool Result:%*%*%s*`([^`]+)`"
local TOOL_RESULT_ERROR_PATTERN = "%s*%(error%)%s*$"
local ABORTED_PATTERN = "^<!%-%-%s*flemma:aborted:%s*(.-)%s*%-%->$"

---@type table<string, flemma.ast.ToolStatus>
local TOOL_STATUS_MAP = {
  pending = "pending",
  approved = "approved",
  rejected = "rejected",
  denied = "denied",
  aborted = "aborted",
  reject = "rejected",
  deny = "denied",
}

--- Unified segment parser: parse text for {{ }} expressions
--- Returns array of AST segments (text, expression)
--- Note: <thinking> tags are NOT parsed here - only in @Assistant messages
--- Note: @./ file references are handled by the preprocessor rewriter, not here
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

  local function emit_text(str, char_start)
    if str and #str > 0 then
      local start_line, start_col = char_to_line_col(char_start)
      local end_line = start_line
      local end_col = start_col + #str - 1
      -- Count newlines to compute end position (matches runner convention:
      -- trailing \n means end_line is bumped, end_col is length after last \n)
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
    -- Find next opening delimiter: {{ or {%
    local expr_start = s:find("{{", idx, true)
    local code_start = s:find("{%%", idx) -- pattern mode: %% matches literal %

    -- Pick whichever comes first
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
      -- No more delimiters — emit remaining text
      emit_text(s:sub(idx), idx)
      break
    end

    -- Emit preceding text
    emit_text(s:sub(idx, next_start - 1), idx)

    -- Detect trim-before: {{- or {%-
    local trim_before = false
    local content_offset = 2 -- skip {{ or {%
    if s:sub(next_start + 2, next_start + 2) == "-" then
      trim_before = true
      content_offset = 3
    end

    -- Find closing delimiter
    local close_pattern = is_code and "%-?%%}" or "%-?}}"
    local close_start, close_end = s:find(close_pattern, next_start + content_offset)

    if not close_start then
      -- Unclosed delimiter — emit rest as text (graceful degradation)
      emit_text(s:sub(next_start), next_start)
      break
    end

    -- Detect trim-after: -%} or -}}
    local trim_after = s:sub(close_start, close_start) == "-"

    -- Extract content between delimiters
    local content_start = next_start + content_offset
    local content_end = close_start - 1
    local content = s:sub(content_start, content_end)

    -- Build position
    local start_line, start_col = char_to_line_col(next_start)
    local end_line, end_col = char_to_line_col(close_end)

    local pos = {
      start_line = start_line,
      start_col = start_col,
      end_line = end_line,
      end_col = end_col,
    }

    -- Build trim opts (only include if true to match nil-means-absent convention)
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

  -- Accumulator for consecutive plain-text lines to avoid per-line segment splitting
  local accum_lines = {} ---@type string[]
  local accum_start_line = base_line_num

  local function flush_accum()
    if #accum_lines == 0 then
      return
    end
    local text = table.concat(accum_lines, "\n")
    if #text > 0 then
      local parsed = parse_segments(text, accum_start_line)
      for _, seg in ipairs(parsed) do
        table.insert(segments, seg)
      end
    end
    accum_lines = {}
  end

  local i = 1
  while i <= #lines do
    local line = lines[i]
    local current_line_num = base_line_num + i - 1

    -- Check for **Tool Result:** marker
    local tool_use_id = line:match(TOOL_RESULT_PATTERN)
    if tool_use_id then
      flush_accum()
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
        if block.language == "flemma:tool" then
          -- Tool status placeholder — parse info string for status
          local parsed = modeline.parse(block.info or "")
          local tool_status = TOOL_STATUS_MAP[parsed.status] or "pending"

          table.insert(
            segments,
            ast.tool_result(tool_use_id, block.content, {
              is_error = is_error,
              status = tool_status,
              start_line = result_start_line,
              end_line = base_line_num + block_end - 1,
              fence_line = base_line_num + content_start - 1,
            })
          )
          i = block_end + 1
        else
          -- Regular fenced block: parse content by language or treat as plain text
          local result_content

          if block.language then
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
                result_content = json.encode(content)
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
        end
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
        while j <= #lines and not lines[j]:match("^@[%w]+:%s*$") do
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
      -- Regular content line — accumulate for batch parsing
      if #accum_lines == 0 then
        accum_start_line = current_line_num
      end
      table.insert(accum_lines, line)
      i = i + 1
    end
  end

  flush_accum()

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

  -- Accumulator for consecutive plain-text lines to avoid per-line segment splitting
  local accum_lines = {} ---@type string[]
  local accum_start_line = base_line_num

  local function flush_accum()
    if #accum_lines == 0 then
      return
    end
    local text = table.concat(accum_lines, "\n")
    if #text > 0 then
      local end_line = accum_start_line + #accum_lines - 1
      local end_col = #accum_lines[#accum_lines]
      table.insert(
        segments,
        ast.text(text, {
          start_line = accum_start_line,
          start_col = 1,
          end_line = end_line,
          end_col = end_col,
        })
      )
    end
    accum_lines = {}
  end

  local i = 1
  while i <= #lines do
    local line = lines[i]
    local current_line_num = base_line_num + i - 1

    -- Check for thinking tags on their own lines
    -- Patterns:
    --   <thinking> or <thinking provider:signature="..."> (opening tag)
    --   <thinking redacted> (opening tag for redacted thinking)
    --   <thinking provider:signature="..."/> (self-closing tag)
    -- Supports any provider:signature attribute (e.g., vertex:signature, anthropic:signature)
    local self_closing_provider, self_closing_sig = line:match('^<thinking%s+(%w+):signature="([^"]*)"%s*/>$')
    local open_tag_provider, open_tag_sig = line:match('^<thinking%s+(%w+):signature="([^"]*)"%s*>$')
    local simple_open_tag = line:match("^<thinking>$")
    local redacted_open_tag = line:match("^<thinking%s+redacted>$")

    if self_closing_sig then
      flush_accum()
      -- Self-closing tag with signature, no content
      local thinking_line = current_line_num
      table.insert(
        segments,
        ast.thinking("", {
          start_line = thinking_line,
          end_line = thinking_line,
        }, { signature = { value = self_closing_sig, provider = self_closing_provider } })
      )
      i = i + 1
    elseif open_tag_sig or simple_open_tag or redacted_open_tag then
      flush_accum()
      local signature = open_tag_sig and { value = open_tag_sig, provider = open_tag_provider } or nil
      local redacted = redacted_open_tag ~= nil
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
            }, { signature = signature, redacted = redacted or nil })
          )
          i = i + 1
          break
        else
          table.insert(thinking_content_lines, lines[i])
          i = i + 1
        end
      end
    elseif line:match(TOOL_USE_PATTERN) then
      flush_accum()
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
          while j <= #lines and not lines[j]:match("^@[%w]+:%s*$") do
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
        while j <= #lines and not lines[j]:match("^@[%w]+:%s*$") do
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
      local aborted_message = line:match(ABORTED_PATTERN)
      if aborted_message then
        flush_accum()
        table.insert(
          segments,
          ast.aborted(aborted_message, { start_line = current_line_num, end_line = current_line_num })
        )
        i = i + 1
      else
        -- Regular text line — accumulate for batch emission
        if #accum_lines == 0 then
          accum_start_line = current_line_num
        end
        table.insert(accum_lines, line)
        i = i + 1
      end
    end
  end

  flush_accum()

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
  local role = line:match("^@([%w]+):%s*$")
  if not role then
    return nil, start_idx, diagnostics
  end

  local content_lines = {}

  local i = start_idx + 1
  local active_fence_length = 0 -- 0 = not inside a fence; >0 = min backticks needed to close
  while i <= #lines do
    local next_line = lines[i]

    if active_fence_length > 0 then
      -- Inside a fenced code block — check for closing fence
      local close_ticks = next_line:match("^(`+)%s*$")
      if close_ticks and #close_ticks >= active_fence_length then
        active_fence_length = 0
      end
    else
      -- Outside a fence — check for role marker (message boundary)
      if next_line:match("^@[%w]+:%s*$") then
        break
      end
      -- Check for fence opener (CommonMark: backtick fence info string cannot contain backticks)
      local open_ticks = next_line:match("^(`+)")
      if open_ticks and #open_ticks >= 3 and not next_line:sub(#open_ticks + 1):find("`") then
        active_fence_length = #open_ticks
      end
    end

    table.insert(content_lines, next_line)
    i = i + 1
  end

  -- Strip trailing empty lines (inter-message whitespace before the next @Role: marker)
  while #content_lines > 0 and content_lines[#content_lines] == "" do
    table.remove(content_lines)
  end

  local segments
  local content_start_line = start_idx + 1 + line_offset

  if role == "Assistant" then
    -- Parse thinking tags and tool_use blocks
    local msg_diagnostics
    segments, msg_diagnostics = parse_assistant_segments(content_lines, content_start_line, {})
    for _, diag in ipairs(msg_diagnostics) do
      table.insert(diagnostics, diag)
    end
  elseif roles.is_user(role) then
    -- Parse tool_result blocks and regular content
    local msg_diagnostics
    segments, msg_diagnostics = parse_user_segments(content_lines, content_start_line, {})
    for _, diag in ipairs(msg_diagnostics) do
      table.insert(diagnostics, diag)
    end
  else
    -- Other roles (System, etc.) - parse {{ }} expressions
    local content = table.concat(content_lines, "\n")
    segments = parse_segments(content, content_start_line)
  end

  local msg = ast.message(role, segments, {
    start_line = start_idx + line_offset,
    end_line = (i - 1) + line_offset,
  })
  return msg, (i - 1), diagnostics
end

--- Parse message blocks from content lines with a line offset.
--- Shared by full parse and incremental (snapshot) parse paths.
---@param lines string[]
---@param line_offset integer Offset added to line indices for absolute positions
---@return flemma.ast.MessageNode[] messages
---@return flemma.ast.Diagnostic[] errors
local function parse_messages(lines, line_offset)
  local messages = {}
  local errors = {}
  local i = 1

  while i <= #lines do
    local msg, last, diagnostics = parse_message(lines, i, line_offset, {})
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

  return messages, errors
end

---@param lines string[]|nil
---@return flemma.ast.DocumentNode
function M.parse_lines(lines)
  lines = lines or {}
  local fm, _, body, body_start = parse_frontmatter(lines)
  local content_lines = body or lines
  local line_offset = body and (body_start - 1) or 0
  local messages, errors = parse_messages(content_lines, line_offset)
  local doc = ast.document(fm, messages, errors, { start_line = 1, end_line = #lines })
  return doc
end

--- Parse inline content (for include() results) - no frontmatter, no message roles
--- Scans for {{ }} expressions only; @./ file references are handled by the preprocessor
---@param text string|nil
---@return flemma.ast.Segment[]
function M.parse_inline_content(text)
  return parse_segments(text or "")
end

---Register a post-parse hook that transforms the AST after parsing.
---Used by the preprocessor to run rewriters on the parsed document.
---@param hook (fun(doc: flemma.ast.DocumentNode, bufnr: integer): flemma.ast.DocumentNode)|nil
function M.set_post_parse_hook(hook)
  post_parse_hook = hook
end

--- Get parsed document with automatic caching based on buffer changedtick
--- Returns cached AST if buffer unchanged, otherwise parses and caches
---@param bufnr integer
---@return flemma.ast.DocumentNode
function M.get_parsed_document(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  local current_tick = vim.api.nvim_buf_get_changedtick(bufnr)

  -- Return cached if still valid
  if buffer_state.ast_cache and buffer_state.ast_cache.changedtick == current_tick then
    return buffer_state.ast_cache.document
  end

  local doc
  local snapshot = buffer_state.ast_snapshot_before_send

  if snapshot then
    -- Incremental parse: read only lines from resume point onwards.
    -- resume_line is 1-indexed; nvim_buf_get_lines is 0-indexed, hence - 1.
    -- The same offset (resume_line - 1) is passed to parse_messages so that
    -- local index 1 in suffix_lines maps to absolute line resume_line:
    --   parse_message computes start_line = start_idx + line_offset = 1 + (resume_line - 1) = resume_line
    local total_lines = vim.api.nvim_buf_line_count(bufnr)
    local suffix_lines = vim.api.nvim_buf_get_lines(bufnr, snapshot.resume_line - 1, -1, false)
    local new_messages, new_errors = parse_messages(suffix_lines, snapshot.resume_line - 1)

    -- Merge frozen + new
    local all_messages = {}
    for i, msg in ipairs(snapshot.messages) do
      all_messages[i] = msg
    end
    for _, msg in ipairs(new_messages) do
      all_messages[#all_messages + 1] = msg
    end

    local all_errors = {}
    for i, err in ipairs(snapshot.errors) do
      all_errors[i] = err
    end
    for _, err in ipairs(new_errors) do
      all_errors[#all_errors + 1] = err
    end

    doc = ast.document(snapshot.frontmatter, all_messages, all_errors, {
      start_line = 1,
      end_line = total_lines,
    })
  else
    -- Full parse
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    doc = M.parse_lines(lines)
  end

  -- Store raw (pre-rewriter) AST
  buffer_state.raw_ast_cache = {
    changedtick = current_tick,
    document = doc,
  }

  -- Run post-parse hook (preprocessor rewriters in non-interactive mode)
  if post_parse_hook then
    local rewritten_doc = vim.deepcopy(doc)
    rewritten_doc = post_parse_hook(rewritten_doc, bufnr)
    doc = rewritten_doc
  end

  buffer_state.ast_cache = {
    changedtick = current_tick,
    document = doc,
  }

  return doc
end

---Get the raw (pre-rewriter) parsed document.
---Used by the send flow to start a fresh interactive rewriter pass.
---@param bufnr integer
---@return flemma.ast.DocumentNode
function M.get_raw_document(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  local current_tick = vim.api.nvim_buf_get_changedtick(bufnr)

  if buffer_state.raw_ast_cache and buffer_state.raw_ast_cache.changedtick == current_tick then
    return buffer_state.raw_ast_cache.document
  end

  -- Calling get_parsed_document populates raw_ast_cache as a side effect
  M.get_parsed_document(bufnr)
  return buffer_state.raw_ast_cache.document
end

--- Snapshot the current AST for incremental parsing during streaming.
--- Call this before writing the @Assistant: placeholder. The snapshot
--- captures all messages up to the current buffer end, so only content
--- appended after this point needs re-parsing.
---@param bufnr integer
function M.create_ast_snapshot_before_send(bufnr)
  local doc = M.get_parsed_document(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)

  -- Shallow-copy arrays so the snapshot is independent of the cached doc
  local messages = {}
  for i, msg in ipairs(doc.messages) do
    messages[i] = msg
  end
  local errors = {}
  for i, err in ipairs(doc.errors) do
    errors[i] = err
  end

  buffer_state.ast_snapshot_before_send = {
    frontmatter = doc.frontmatter,
    messages = messages,
    errors = errors,
    resume_line = doc.position.end_line + 1,
  }
end

--- Clear the AST snapshot, restoring full-parse behavior.
--- Must be called on every request exit path (success, error, cancel, job failure).
---@param bufnr integer
function M.clear_ast_snapshot_before_send(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)
  buffer_state.ast_snapshot_before_send = nil
end

return M
