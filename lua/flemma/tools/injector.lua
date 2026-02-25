--- Tool result injector
--- Handles inserting tool execution results into the buffer in the correct format
---@class flemma.tools.Injector
local M = {}

--- Error messages for tool status resolution
M.DENIED_MESSAGE = "The tool was denied by a policy."
M.REJECTED_MESSAGE = "This tool has been rejected by the user."

---Resolve the error message for a denied or rejected tool status.
---For rejected: uses user-provided content if non-empty, otherwise the default message.
---For denied: always uses the policy message.
---@param status "rejected"|"denied"
---@param content? string user content from the tool block
---@return string
function M.resolve_error_message(status, content)
  if status == "rejected" then
    return (content and content ~= "") and content or M.REJECTED_MESSAGE
  end
  return M.DENIED_MESSAGE
end

local codeblock = require("flemma.codeblock")
local json = require("flemma.json")

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

--- Get all tool_result segments in a message, in buffer position order
--- @param msg table Message AST node
--- @return table[] tool_result segments sorted by start_line
local function get_tool_results_in_message(msg)
  local results = {}
  for _, seg in ipairs(msg.segments) do
    if seg.kind == "tool_result" then
      table.insert(results, seg)
    end
  end
  return results
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
      content = json.encode(result.output)
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

--- Phase 1: Insert placeholder for a tool result
--- Called when execution starts. Creates the **Tool Result:** header + empty code block.
--- The empty code block ensures the parser recognizes it as a tool_result segment,
--- which is required for correct multi-tool ordering on subsequent injections.
--- @param bufnr integer
--- @param tool_id string
--- @param inject_opts? { status?: flemma.ast.ToolStatus } When status is set, uses ```flemma:tool status=X fence
--- @return integer|nil header_line 1-based line number where header was inserted, or nil on error
--- @return string|nil error message
--- @return { modified: boolean }|nil opts Metadata about the injection (e.g., whether buffer was modified)
function M.inject_placeholder(bufnr, tool_id, inject_opts)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil, "Buffer is no longer valid", { modified = false }
  end

  local parser = require("flemma.parser")
  local doc = parser.get_parsed_document(bufnr)

  -- Check if tool_result already exists for this tool_id
  local existing_result = find_existing_tool_result(doc, tool_id)
  if existing_result then
    -- Reuse existing - return its position
    return existing_result.position.start_line, nil, { modified = false }
  end

  -- Find the assistant message containing this tool_use
  local assistant_msg, assistant_idx = find_assistant_message_for_tool(doc, tool_id)
  if not assistant_msg or not assistant_idx then
    return nil, "Tool use block not found in buffer", { modified = false }
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
    return nil, "Tool use block not found in message segments", { modified = false }
  end

  -- Check for existing @You: message after the assistant message
  local you_msg = find_you_message_after(doc, assistant_idx)

  local header_text = ("**Tool Result:** `%s`"):format(tool_id)
  local fence_open
  if inject_opts and inject_opts.status then
    fence_open = "```flemma:tool status=" .. inject_opts.status
  else
    fence_open = "```"
  end

  if you_msg then
    -- @You: message exists - find where to insert our placeholder
    local existing_results = get_tool_results_in_message(you_msg)

    if #existing_results > 0 then
      -- Build tool_use index map for ordering
      local tool_use_index = {}
      for i, tu in ipairs(tool_uses) do
        tool_use_index[tu.id] = i
      end

      -- Find the last existing result whose tool_use comes before ours in order
      local predecessor = nil
      local predecessor_idx = -1
      for _, tr in ipairs(existing_results) do
        local tr_idx = tool_use_index[tr.tool_use_id] or 0
        if tr_idx < our_tool_idx and tr_idx > predecessor_idx then
          predecessor = tr
          predecessor_idx = tr_idx
        end
      end

      if predecessor then
        -- Insert after the predecessor result's block
        local insert_after = predecessor.position.end_line
        set_lines(bufnr, insert_after, insert_after, { "", header_text, "", fence_open, "```" })
        return insert_after + 2, nil, { modified = true } -- +1 for blank line, +1 for 1-based
      else
        -- Our tool comes before all existing results - insert before the first one
        local first_result = existing_results[1]
        local first_start = first_result.position.start_line
        local you_start = you_msg.position.start_line

        if first_start == you_start then
          -- First result header is inline with @You: line - split it
          local old_line = vim.api.nvim_buf_get_lines(bufnr, you_start - 1, you_start, false)[1]
          local old_header = old_line:match("^@You:%s*(.+)$")
          set_lines(bufnr, you_start - 1, you_start, {
            "@You: " .. header_text,
            "",
            fence_open,
            "```",
            "",
            old_header or "",
          })
          return you_start, nil, { modified = true }
        else
          -- First result is on a separate line - insert before it
          set_lines(bufnr, first_start - 1, first_start - 1, { header_text, "", fence_open, "```", "" })
          return first_start, nil, { modified = true }
        end
      end
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
          fence_open,
          "```",
          "",
          remaining_content,
        })
        return you_start, nil, { modified = true }
      else
        -- @You: line is empty or whitespace-only - replace it with header
        set_lines(bufnr, you_start - 1, you_start, { "@You: " .. header_text, "", fence_open, "```" })
        return you_start, nil, { modified = true }
      end
    end
  else
    -- No @You: message exists - create one after the assistant message
    local insert_after = assistant_msg.position.end_line
    set_lines(bufnr, insert_after, insert_after, { "", "@You: " .. header_text, "", fence_open, "```" })
    return insert_after + 2, nil, { modified = true } -- +1 for blank, +1 for 1-based
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

    -- Placeholder now includes an empty code block, so the parser will find it.
    -- Recursive call to replace placeholder content with actual result.
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

---Resolve a pending tool_result block that has user-provided content.
---Strips the `flemma:tool` modeline from the fence opener, converting the block
---into a normal resolved tool_result while preserving the user's content intact.
---@param bufnr integer
---@param tool_id string
---@return boolean success
---@return string|nil error_message
function M.resolve_user_content(bufnr, tool_id)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false, "Buffer is no longer valid"
  end

  local parser = require("flemma.parser")
  local doc = parser.get_parsed_document(bufnr)

  local seg = find_existing_tool_result(doc, tool_id)
  if not seg then
    return false, "Tool result not found: " .. tool_id
  end

  -- Scan the block's lines for the flemma:tool fence opener
  local start_0 = seg.position.start_line - 1
  local end_0 = seg.position.end_line
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_0, end_0, false)

  for i, line in ipairs(lines) do
    if line:match("^`+flemma:tool") then
      -- Replace with a plain fence (preserve the backtick count)
      local backticks = line:match("^(`+)")
      lines[i] = backticks
      set_lines(bufnr, start_0, end_0, lines)
      return true, nil
    end
  end

  return false, "Could not find flemma:tool fence in block for " .. tool_id
end

return M
