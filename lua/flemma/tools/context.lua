--- Tool context resolver
--- Given a cursor position, finds the tool_use block and extracts execution context
---@class flemma.tools.Context
local M = {}

---@class flemma.tools.ToolContext
---@field tool_id string The unique ID of the tool call
---@field tool_name string The name of the tool to execute
---@field input table<string, any> The parsed input arguments
---@field node flemma.ast.ToolUseSegment The AST segment reference (from parser)
---@field start_line integer 1-based start line of the tool_use block
---@field end_line integer 1-based end line of the tool_use block
---@field aborted? boolean True when the tool_use is in an aborted assistant message
---@field aborted_message? string The message from the abort marker

---Find the message containing a given line number
---@param doc flemma.ast.DocumentNode Parsed document AST
---@param line integer 1-based line number
---@return flemma.ast.MessageNode|nil message, integer|nil message_index
local function find_message_at_line(doc, line)
  for i, msg in ipairs(doc.messages) do
    if line >= msg.position.start_line and line <= msg.position.end_line then
      return msg, i
    end
  end
  return nil, nil
end

---Find all tool_use segments in a message
---@param msg flemma.ast.MessageNode Message AST node
---@return flemma.ast.ToolUseSegment[]
local function get_tool_use_segments(msg)
  local tool_uses = {}
  for _, seg in ipairs(msg.segments) do
    if seg.kind == "tool_use" then
      table.insert(tool_uses, seg)
    end
  end
  return tool_uses
end

---Find the tool_use segment containing or nearest to the cursor line
---@param tool_uses flemma.ast.ToolUseSegment[] Array of tool_use segments
---@param cursor_line integer 1-based cursor line
---@return flemma.ast.ToolUseSegment|nil
local function find_nearest_tool_use(tool_uses, cursor_line)
  if #tool_uses == 0 then
    return nil
  end

  -- Check if cursor is within any tool_use block
  for _, seg in ipairs(tool_uses) do
    if cursor_line >= seg.position.start_line and cursor_line <= seg.position.end_line then
      return seg
    end
  end

  -- Cursor is not inside a tool_use block - find the nearest one
  -- Prefer the tool above the cursor, then below
  local best = nil
  local best_distance = math.huge

  for _, seg in ipairs(tool_uses) do
    -- Distance: prefer tool_use blocks that end at or before cursor
    local distance
    if seg.position.end_line <= cursor_line then
      distance = cursor_line - seg.position.end_line
    else
      distance = seg.position.start_line - cursor_line
    end

    if distance < best_distance then
      best_distance = distance
      best = seg
    end
  end

  return best
end

---Check whether an assistant message ends with an abort marker.
---Scans segments backwards, skipping trailing whitespace-only text.
---@param msg flemma.ast.MessageNode
---@return string|nil message The abort message, or nil if not aborted
local function get_abort_message(msg)
  for i = #msg.segments, 1, -1 do
    local seg = msg.segments[i]
    if seg.kind == "aborted" then
      return seg.message
    elseif seg.kind ~= "text" or not seg.value:match("^%s*$") then
      return nil
    end
    -- whitespace-only text segment — continue scanning backwards
  end
  return nil
end

---Find all tool_use blocks in the buffer that lack a corresponding tool_result
---@param bufnr integer Buffer number
---@return flemma.tools.ToolContext[] pending_contexts
function M.resolve_all_pending(bufnr)
  local parser = require("flemma.parser")
  local doc = parser.get_parsed_document(bufnr)

  -- Collect all tool_result IDs across the entire document
  local result_ids = {}
  for _, msg in ipairs(doc.messages) do
    if msg.role == "You" then
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "tool_result" then
          result_ids[seg.tool_use_id] = true
        end
      end
    end
  end

  -- Collect tool_use segments that have no matching tool_result
  local pending = {}
  for _, msg in ipairs(doc.messages) do
    if msg.role == "Assistant" then
      local aborted_message = get_abort_message(msg)
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "tool_use" and not result_ids[seg.id] then
          table.insert(pending, {
            tool_id = seg.id,
            tool_name = seg.name,
            input = seg.input or {},
            node = seg,
            start_line = seg.position.start_line,
            end_line = seg.position.end_line,
            aborted = aborted_message and true or nil,
            aborted_message = aborted_message,
          })
        end
      end
    end
  end

  return pending
end

---@class flemma.tools.ToolBlockContext : flemma.tools.ToolContext
---@field status flemma.ast.ToolStatus
---@field content string
---@field is_error boolean
---@field tool_result { start_line: integer, fence_line?: integer } Position of the matching tool_result block
---@field aborted_message? string The message from the abort marker (for aborted blocks)

---Find all tool_result segments with a `flemma:tool` status, grouped by status.
---Each entry pairs the tool_result metadata with its matching tool_use context.
---Results with status=approved that have non-empty content are excluded from the
---main groups (content-overwrite protection) and warned about. Pending blocks with
---user-filled content are returned separately so callers can resolve them
---(strip the flemma:tool fence, keeping the user's content as a normal tool_result).
---@param bufnr integer Buffer number
---@return table<flemma.ast.ToolStatus, flemma.tools.ToolBlockContext[]> groups
---@return flemma.tools.ToolBlockContext[] user_filled Pending blocks with user-filled content
function M.resolve_all_tool_blocks(bufnr)
  local parser = require("flemma.parser")
  local doc = parser.get_parsed_document(bufnr)

  -- Collect tool_result segments with status, keyed by tool_use_id
  ---@type table<string, { status: flemma.ast.ToolStatus, content: string, is_error: boolean, tool_result_start_line: integer, fence_line?: integer }>
  local status_results = {}
  for _, msg in ipairs(doc.messages) do
    if msg.role == "You" then
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "tool_result" and seg.status then
          status_results[seg.tool_use_id] = {
            status = seg.status,
            content = seg.content,
            is_error = seg.is_error,
            tool_result_start_line = seg.position.start_line,
            fence_line = seg.fence_line,
          }
        end
      end
    end
  end

  if vim.tbl_isempty(status_results) then
    return {}, {}
  end

  -- Build tool_use lookup and abort message map for matching
  ---@type table<string, flemma.ast.ToolUseSegment>
  local tool_use_map = {}
  ---@type table<string, string>
  local abort_message_map = {}
  for _, msg in ipairs(doc.messages) do
    if msg.role == "Assistant" then
      local aborted_message = get_abort_message(msg)
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "tool_use" then
          tool_use_map[seg.id] = seg --[[@as flemma.ast.ToolUseSegment]]
          if aborted_message then
            abort_message_map[seg.id] = aborted_message
          end
        end
      end
    end
  end

  -- Group by status, applying content-overwrite protection
  ---@type table<flemma.ast.ToolStatus, flemma.tools.ToolBlockContext[]>
  local groups = {}
  local conflict_count = 0
  ---@type flemma.tools.ToolBlockContext[]
  local user_filled = {}

  for tool_use_id, info in pairs(status_results) do
    local tu = tool_use_map[tool_use_id]
    if tu then
      ---@type flemma.tools.ToolBlockContext
      local block_context = {
        tool_id = tu.id,
        tool_name = tu.name,
        input = tu.input or {},
        node = tu,
        start_line = tu.position.start_line,
        end_line = tu.position.end_line,
        status = info.status,
        content = info.content,
        is_error = info.is_error,
        tool_result = { start_line = info.tool_result_start_line, fence_line = info.fence_line },
        aborted_message = abort_message_map[tu.id],
      }

      if info.status == "approved" and info.content ~= "" then
        -- Content-overwrite protection: approved with user-edited content.
        -- Execution would overwrite the user's edits.
        conflict_count = conflict_count + 1
      elseif info.status == "pending" and info.content ~= "" then
        -- User provided content for a pending tool — collect for resolution.
        -- The caller will strip the flemma:tool fence, keeping the content
        -- as a normal resolved tool_result.
        table.insert(user_filled, block_context)
      else
        if not groups[info.status] then
          groups[info.status] = {}
        end
        table.insert(groups[info.status], block_context)
      end
    end
  end

  if conflict_count > 0 then
    vim.notify(
      "Flemma: "
        .. conflict_count
        .. " tool result(s) have edited content inside an approved flemma:tool block – "
        .. "skipping execution to protect your edits. Remove the flemma:tool fence to send your content.",
      vim.log.levels.WARN
    )
  end

  -- Sort each group by start_line for deterministic document order
  for _, group in pairs(groups) do
    table.sort(group, function(a, b)
      return a.start_line < b.start_line
    end)
  end
  table.sort(user_filled, function(a, b)
    return a.start_line < b.start_line
  end)

  return groups, user_filled
end

---Resolve tool context from cursor position
---@param bufnr integer Buffer number
---@param cursor_pos {row: integer, col: integer} 1-based cursor position
---@return flemma.tools.ToolContext|nil context, string|nil error_message
function M.resolve(bufnr, cursor_pos)
  local parser = require("flemma.parser")
  local doc = parser.get_parsed_document(bufnr)

  local cursor_line = cursor_pos.row

  -- Check if cursor is in frontmatter
  if doc.frontmatter and doc.frontmatter.position then
    if cursor_line >= doc.frontmatter.position.start_line and cursor_line <= doc.frontmatter.position.end_line then
      return nil, "No tool call at cursor position"
    end
  end

  -- Find the message containing the cursor
  local msg, msg_idx = find_message_at_line(doc, cursor_line)
  if not msg then
    return nil, "No tool call at cursor position"
  end

  -- Tool calls only exist in assistant messages
  if msg.role ~= "Assistant" then
    -- If cursor is in a user message, check if the previous message is an assistant with tools
    if msg.role == "You" and msg_idx and msg_idx > 1 then
      local prev_msg = doc.messages[msg_idx - 1]
      if prev_msg.role == "Assistant" then
        local tool_uses = get_tool_use_segments(prev_msg)
        if #tool_uses > 0 then
          -- Try to match cursor to a specific tool_result in the @You: message
          for _, seg in ipairs(msg.segments) do
            if
              seg.kind == "tool_result"
              and cursor_line >= seg.position.start_line
              and cursor_line <= seg.position.end_line
            then
              -- Find corresponding tool_use by ID
              for _, tu in ipairs(tool_uses) do
                if tu.id == seg.tool_use_id then
                  return {
                    tool_id = tu.id,
                    tool_name = tu.name,
                    input = tu.input or {},
                    node = tu,
                    start_line = tu.position.start_line,
                    end_line = tu.position.end_line,
                  },
                    nil
                end
              end
            end
          end
          -- Fallback: find nearest tool_result, then last tool_use
          local nearest_result = nil
          local nearest_distance = math.huge
          for _, seg in ipairs(msg.segments) do
            if seg.kind == "tool_result" then
              local distance
              if seg.position.end_line <= cursor_line then
                distance = cursor_line - seg.position.end_line
              else
                distance = seg.position.start_line - cursor_line
              end
              if distance < nearest_distance then
                nearest_distance = distance
                nearest_result = seg
              end
            end
          end
          if nearest_result then
            for _, tu in ipairs(tool_uses) do
              if tu.id == nearest_result.tool_use_id then
                return {
                  tool_id = tu.id,
                  tool_name = tu.name,
                  input = tu.input or {},
                  node = tu,
                  start_line = tu.position.start_line,
                  end_line = tu.position.end_line,
                },
                  nil
              end
            end
          end
          -- Final fallback: last tool_use
          local seg = tool_uses[#tool_uses]
          return {
            tool_id = seg.id,
            tool_name = seg.name,
            input = seg.input or {},
            node = seg,
            start_line = seg.position.start_line,
            end_line = seg.position.end_line,
          },
            nil
        end
      end
    end
    return nil, "No tool call found in message"
  end

  -- Find tool_use segments in the assistant message
  local tool_uses = get_tool_use_segments(msg)
  if #tool_uses == 0 then
    return nil, "No tool call found in message"
  end

  -- Find the nearest tool_use to cursor
  local seg = find_nearest_tool_use(tool_uses, cursor_line)
  if not seg then
    return nil, "No tool call found near cursor"
  end

  return {
    tool_id = seg.id,
    tool_name = seg.name,
    input = seg.input or {},
    node = seg,
    start_line = seg.position.start_line,
    end_line = seg.position.end_line,
  },
    nil
end

return M
