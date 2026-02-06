--- Tool context resolver
--- Given a cursor position, finds the tool_use block and extracts execution context
local M = {}

--- @class ToolContext
--- @field tool_id string The unique ID of the tool call
--- @field tool_name string The name of the tool to execute
--- @field input table The parsed input arguments
--- @field node table The AST segment reference (from parser)
--- @field start_line integer 1-based start line of the tool_use block
--- @field end_line integer 1-based end line of the tool_use block

--- Find the message containing a given line number
--- @param doc table Parsed document AST
--- @param line integer 1-based line number
--- @return table|nil message, integer|nil message_index
local function find_message_at_line(doc, line)
  for i, msg in ipairs(doc.messages) do
    if line >= msg.position.start_line and line <= msg.position.end_line then
      return msg, i
    end
  end
  return nil, nil
end

--- Find all tool_use segments in a message
--- @param msg table Message AST node
--- @return table[] tool_use segments
local function get_tool_use_segments(msg)
  local tool_uses = {}
  for _, seg in ipairs(msg.segments) do
    if seg.kind == "tool_use" then
      table.insert(tool_uses, seg)
    end
  end
  return tool_uses
end

--- Find the tool_use segment containing or nearest to the cursor line
--- @param tool_uses table[] Array of tool_use segments
--- @param cursor_line integer 1-based cursor line
--- @return table|nil tool_use segment
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

--- Resolve tool context from cursor position
--- @param bufnr integer Buffer number
--- @param cursor_pos {row: integer, col: integer} 1-based cursor position
--- @return ToolContext|nil context, string|nil error_message
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
