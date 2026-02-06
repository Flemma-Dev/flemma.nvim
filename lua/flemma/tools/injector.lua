--- Tool result injector
--- Handles inserting tool execution results into the buffer in the correct format
local M = {}

local codeblock = require("flemma.codeblock")

--- Find the assistant message containing a tool_use with the given ID
--- @param doc table Parsed document AST
--- @param tool_id string Tool use ID
--- @return table|nil assistant_msg, integer|nil msg_index
local function find_assistant_message_for_tool(doc, tool_id)
  for i, msg in ipairs(doc.messages) do
    if msg.role == "Assistant" then
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "tool_use" and seg.id == tool_id then
          return msg, i
        end
      end
    end
  end
  return nil, nil
end

--- Find existing tool_result segment for a tool_id in the document
--- @param doc table Parsed document AST
--- @param tool_id string Tool use ID
--- @return table|nil segment, table|nil message
local function find_existing_tool_result(doc, tool_id)
  for _, msg in ipairs(doc.messages) do
    if msg.role == "You" then
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "tool_result" and seg.tool_use_id == tool_id then
          return seg, msg
        end
      end
    end
  end
  return nil, nil
end

--- Find the @You: message immediately following a given message index
--- @param doc table Parsed document AST
--- @param after_msg_idx integer Message index to look after
--- @return table|nil you_message, integer|nil msg_index
local function find_you_message_after(doc, after_msg_idx)
  if after_msg_idx < #doc.messages then
    local next_msg = doc.messages[after_msg_idx + 1]
    if next_msg.role == "You" then
      return next_msg, after_msg_idx + 1
    end
  end
  return nil, nil
end

--- Find the last tool_result segment in a message
--- @param msg table Message AST node
--- @return table|nil last_tool_result segment
local function find_last_tool_result_in_message(msg)
  local last = nil
  for _, seg in ipairs(msg.segments) do
    if seg.kind == "tool_result" then
      last = seg
    end
  end
  return last
end

--- Format result content into lines for buffer insertion
--- @param result table ExecutionResult {success, output, error}
--- @return string[] lines, boolean is_error
local function format_result_lines(result)
  local is_error = not result.success
  local content

  if is_error then
    content = result.error or "Unknown error"
    if result.output and result.output ~= "" then
      content = content .. "\n\nPartial output:\n" .. result.output
    end
  else
    if type(result.output) == "table" then
      content = vim.fn.json_encode(result.output)
    else
      content = tostring(result.output or "")
    end
  end

  -- Determine fence and language tag
  local fence = codeblock.get_fence(content)
  local lang_tag = ""
  if not is_error and type(result.output) == "table" then
    lang_tag = "json"
  end

  local lines = {}
  table.insert(lines, "") -- blank line before fence
  table.insert(lines, fence .. lang_tag)
  for _, line in ipairs(vim.split(content, "\n", { plain = true })) do
    table.insert(lines, line)
  end
  table.insert(lines, fence)

  return lines, is_error
end

--- Set buffer lines with modifiable handling
--- @param bufnr integer
--- @param start_idx integer 0-based start line
--- @param end_idx integer 0-based end line (exclusive)
--- @param lines string[]
local function set_lines(bufnr, start_idx, end_idx, lines)
  local was_modifiable = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, start_idx, end_idx, false, lines)
  vim.bo[bufnr].modifiable = was_modifiable
end

--- Phase 1: Insert placeholder header for a tool result
--- Called when execution starts. Creates the **Tool Result:** line.
--- @param bufnr integer
--- @param tool_id string
--- @return integer|nil header_line 1-based line number where header was inserted, or nil on error
--- @return string|nil error message
function M.inject_placeholder(bufnr, tool_id)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil, "Buffer is no longer valid"
  end

  local parser = require("flemma.parser")
  local doc = parser.get_parsed_document(bufnr)

  -- Check if tool_result already exists for this tool_id
  local existing_result = find_existing_tool_result(doc, tool_id)
  if existing_result then
    -- Reuse existing - return its position
    return existing_result.position.start_line, nil
  end

  -- Find the assistant message containing this tool_use
  local assistant_msg, assistant_idx = find_assistant_message_for_tool(doc, tool_id)
  if not assistant_msg then
    return nil, "Tool use block not found in buffer"
  end

  -- Get all tool_use segments from this message (ordered by position)
  local tool_uses = {}
  for _, seg in ipairs(assistant_msg.segments) do
    if seg.kind == "tool_use" then
      table.insert(tool_uses, seg)
    end
  end

  -- Find the index of our tool in the tool_uses list
  local our_tool_idx = nil
  for i, tu in ipairs(tool_uses) do
    if tu.id == tool_id then
      our_tool_idx = i
      break
    end
  end

  if not our_tool_idx then
    return nil, "Tool use block not found in message segments"
  end

  -- Check for existing @You: message after the assistant message
  local you_msg = find_you_message_after(doc, assistant_idx)

  local header_text = ("**Tool Result:** `%s`"):format(tool_id)

  if you_msg then
    -- @You: message exists - find where to insert our placeholder
    local last_result = find_last_tool_result_in_message(you_msg)

    if last_result then
      -- Append after the last tool_result's end line
      local insert_after = last_result.position.end_line
      set_lines(bufnr, insert_after, insert_after, { "", header_text })
      return insert_after + 2, nil -- +1 for blank line, +1 for 1-based
    else
      -- @You: exists but has no tool results - insert at start of content
      -- The @You: role line is at you_msg.position.start_line
      local you_start = you_msg.position.start_line
      -- Insert header right after the @You: line marker, shifting content down
      -- Get the current @You: line text
      local you_line = vim.api.nvim_buf_get_lines(bufnr, you_start - 1, you_start, false)[1]
      -- Extract the content after "@You: " or "@You:"
      local role_prefix = you_line:match("^@You:%s*")
      local remaining_content = you_line:sub(#role_prefix + 1)

      if remaining_content and remaining_content:match("%S") then
        -- @You: has inline content - replace with header + move content down
        set_lines(bufnr, you_start - 1, you_start, {
          "@You: " .. header_text,
          "",
          remaining_content,
        })
        return you_start, nil
      else
        -- @You: line is empty or whitespace-only - replace it with header
        set_lines(bufnr, you_start - 1, you_start, { "@You: " .. header_text })
        return you_start, nil
      end
    end
  else
    -- No @You: message exists - create one after the assistant message
    local insert_after = assistant_msg.position.end_line
    set_lines(bufnr, insert_after, insert_after, { "", "@You: " .. header_text })
    return insert_after + 2, nil -- +1 for blank, +1 for 1-based
  end
end

--- Phase 2: Insert result content below existing tool_result header
--- Called when execution completes.
--- @param bufnr integer
--- @param tool_id string
--- @param result table ExecutionResult {success, output, error}
--- @return boolean success
--- @return string|nil error message
function M.inject_result(bufnr, tool_id, result)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false, "Buffer is no longer valid"
  end

  local parser = require("flemma.parser")
  local doc = parser.get_parsed_document(bufnr)

  -- Find existing tool_result placeholder
  local existing_seg = find_existing_tool_result(doc, tool_id)

  local content_lines, is_error = format_result_lines(result)

  if existing_seg then
    -- Update existing: replace content from header line to end of block
    local header_line = existing_seg.position.start_line
    local end_line = existing_seg.position.end_line

    -- Rebuild header with optional (error) suffix
    local header_text = ("**Tool Result:** `%s`"):format(tool_id)
    if is_error then
      header_text = header_text .. " (error)"
    end

    -- Check if header is on a @You: line
    local current_header = vim.api.nvim_buf_get_lines(bufnr, header_line - 1, header_line, false)[1]
    if current_header:match("^@You:") then
      header_text = "@You: " .. header_text
    end

    -- Replace from header to end of existing block
    local new_lines = { header_text }
    for _, line in ipairs(content_lines) do
      table.insert(new_lines, line)
    end

    set_lines(bufnr, header_line - 1, end_line, new_lines)
    return true, nil
  else
    -- No placeholder exists - inject full result (shouldn't happen normally)
    -- Re-inject placeholder + content
    local header_line, err = M.inject_placeholder(bufnr, tool_id)
    if not header_line then
      return false, err
    end

    -- Re-parse after placeholder injection
    doc = parser.get_parsed_document(bufnr)
    existing_seg = find_existing_tool_result(doc, tool_id)

    if not existing_seg then
      -- Placeholder was just a header line with no content block.
      -- The parser won't find a tool_result without a fenced code block.
      -- Insert content directly after the header line.
      if is_error then
        -- Update header to include (error)
        local current_line = vim.api.nvim_buf_get_lines(bufnr, header_line - 1, header_line, false)[1]
        if not current_line:match("%(error%)") then
          local updated = current_line .. " (error)"
          set_lines(bufnr, header_line - 1, header_line, { updated })
        end
      end

      set_lines(bufnr, header_line, header_line, content_lines)
      return true, nil
    end

    -- Recursive call now that placeholder exists
    return M.inject_result(bufnr, tool_id, result)
  end
end

--- Combined: Replace entire tool result (header + content)
--- Used for re-execution or when placeholder doesn't exist
--- @param bufnr integer
--- @param tool_id string
--- @param result table ExecutionResult {success, output, error}
--- @return boolean success
--- @return string|nil error message
function M.inject_or_replace(bufnr, tool_id, result)
  return M.inject_result(bufnr, tool_id, result)
end

return M
