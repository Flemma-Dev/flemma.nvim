--- Tool context resolver
--- Given a cursor position, finds the tool_use block and extracts execution context
---@class flemma.tools.Context
local M = {}

local parser = require("flemma.parser")
local notify = require("flemma.notify")
local roles = require("flemma.utilities.roles")
local ast = require("flemma.ast")

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
  local doc = parser.get_parsed_document(bufnr)
  local siblings = ast.build_tool_sibling_table(doc)

  local pending = {}
  for tool_id, sibling in pairs(siblings) do
    if sibling.use and not sibling.result then
      local use_msg = sibling.use_message
      local aborted_message = use_msg and get_abort_message(use_msg) or nil
      table.insert(pending, {
        tool_id = tool_id,
        tool_name = sibling.use.name,
        input = sibling.use.input or {},
        node = sibling.use,
        start_line = sibling.use.position.start_line,
        end_line = sibling.use.position.end_line,
        aborted = aborted_message and true or nil,
        aborted_message = aborted_message,
      })
    end
  end

  return pending
end

---@class flemma.tools.ToolBlockContext : flemma.tools.ToolContext
---@field status flemma.ast.ToolStatus
---@field content string
---@field has_content boolean Whether the tool_result block contains non-empty user content
---@field tool_result { start_line: integer } Position of the matching tool_result block
---@field aborted_message? string The message from the abort marker (for aborted blocks)

---Find all tool_result segments awaiting lifecycle processing, grouped by status.
---Each entry pairs the tool_result metadata with its matching tool_use context.
---Results with status=approved that have non-empty content are excluded from the
---groups (content-overwrite protection) and warned about. Errored (status="error")
---and completed (status=nil) results are excluded — they are not actionable.
---@param bufnr integer Buffer number
---@return table<flemma.ast.ToolStatus, flemma.tools.ToolBlockContext[]> groups
function M.resolve_all_tool_blocks(bufnr)
  local doc = parser.get_parsed_document(bufnr)
  local siblings = ast.build_tool_sibling_table(doc)

  ---@type table<flemma.ast.ToolStatus, flemma.tools.ToolBlockContext[]>
  local groups = {}
  local conflict_count = 0

  for _, sibling in pairs(siblings) do
    if sibling.result and sibling.result.status and sibling.result.status ~= "error" and sibling.use then
      local tu = sibling.use
      ---@cast tu flemma.ast.ToolUseSegment
      local result = sibling.result
      ---@cast result flemma.ast.ToolResultSegment
      local result_status = result.status
      ---@cast result_status flemma.ast.ToolStatus
      local use_msg = sibling.use_message
      local aborted_message = use_msg and get_abort_message(use_msg) or nil

      ---@type flemma.tools.ToolBlockContext
      local block_context = {
        tool_id = tu.id,
        tool_name = tu.name,
        input = tu.input or {},
        node = tu,
        start_line = tu.position.start_line,
        end_line = tu.position.end_line,
        status = result_status,
        content = result.content,
        has_content = result.content ~= "",
        tool_result = { start_line = result.position.start_line },
        aborted_message = aborted_message,
      }

      if result_status == "approved" and block_context.has_content then
        conflict_count = conflict_count + 1
      else
        if not groups[result_status] then
          groups[result_status] = {}
        end
        table.insert(groups[result_status], block_context)
      end
    end
  end

  if conflict_count > 0 then
    notify.warn(
      conflict_count
        .. " tool result(s) have edited content inside an approved tool block – "
        .. "skipping execution to protect your edits. Remove the (approved) status from the header to send your content."
    )
  end

  -- Sort each group by start_line for deterministic document order
  for _, group in pairs(groups) do
    table.sort(group, function(a, b)
      return a.start_line < b.start_line
    end)
  end

  return groups
end

---Resolve tool context from cursor position
---@param bufnr integer Buffer number
---@param cursor_pos {row: integer, col: integer} 1-based cursor position
---@return flemma.tools.ToolContext|nil context, string|nil error_message
function M.resolve(bufnr, cursor_pos)
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
    if roles.is_user(msg.role) and msg_idx and msg_idx > 1 then
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
              -- Find corresponding tool_use by ID (document-wide, safe because IDs are unique)
              ---@cast seg flemma.ast.ToolResultSegment
              local tu, _ = ast.find_tool_sibling(doc, seg)
              if tu and tu.kind == "tool_use" then
                ---@cast tu flemma.ast.ToolUseSegment
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
            ---@cast nearest_result flemma.ast.ToolResultSegment
            local tu, _ = ast.find_tool_sibling(doc, nearest_result)
            if tu and tu.kind == "tool_use" then
              ---@cast tu flemma.ast.ToolUseSegment
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
