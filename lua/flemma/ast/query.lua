--- Stateless AST traversal helpers
--- All functions take a DocumentNode and return results without side effects.
---@class flemma.ast.Query
local M = {}

---Find a thinking segment whose start line matches the given line number.
---@param doc flemma.ast.DocumentNode
---@param lnum integer 1-indexed line number
---@return flemma.ast.ThinkingSegment|nil segment
function M.find_thinking_at_line(doc, lnum)
  for _, msg in ipairs(doc.messages) do
    for _, seg in ipairs(msg.segments) do
      if seg.kind == "thinking" and seg.position then
        ---@cast seg flemma.ast.ThinkingSegment
        if seg.position.start_line == lnum then
          return seg
        end
      end
    end
  end
  return nil
end

---Find a tool_use or tool_result segment starting at the given line number.
---@param doc flemma.ast.DocumentNode
---@param lnum integer 1-indexed line number
---@return flemma.ast.ToolUseSegment|flemma.ast.ToolResultSegment|nil segment
---@return "tool_use"|"tool_result"|nil kind
function M.find_tool_segment_at_line(doc, lnum)
  for _, msg in ipairs(doc.messages) do
    for _, seg in ipairs(msg.segments) do
      if seg.position and seg.position.start_line == lnum then
        if seg.kind == "tool_use" then
          ---@cast seg flemma.ast.ToolUseSegment
          return seg, "tool_use"
        elseif seg.kind == "tool_result" then
          ---@cast seg flemma.ast.ToolResultSegment
          return seg, "tool_result"
        end
      end
    end
  end
  return nil, nil
end

---Find a message whose start line matches the given line number.
---@param doc flemma.ast.DocumentNode
---@param lnum integer 1-indexed line number
---@return flemma.ast.MessageNode|nil message
function M.find_message_at_line(doc, lnum)
  for _, msg in ipairs(doc.messages) do
    if msg.position.start_line == lnum then
      return msg
    end
  end
  return nil
end

---Build a tool_use_id -> tool_name lookup from all Assistant messages in a document.
---@param doc flemma.ast.DocumentNode
---@return table<string, string>
function M.build_tool_name_map(doc)
  local map = {}
  for _, msg in ipairs(doc.messages) do
    if msg.role == "Assistant" then
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "tool_use" then
          local tool_seg = seg --[[@as flemma.ast.ToolUseSegment]]
          map[tool_seg.id] = tool_seg.name
        end
      end
    end
  end
  return map
end

---Build a tool_use_id -> label lookup from all tool_use segments in a document.
---Only includes entries where the tool_use input has a string "label" field.
---@param doc flemma.ast.DocumentNode
---@return table<string, string>
function M.build_tool_label_map(doc)
  local map = {}
  for _, msg in ipairs(doc.messages) do
    for _, seg in ipairs(msg.segments) do
      if seg.kind == "tool_use" then
        local tool_seg = seg --[[@as flemma.ast.ToolUseSegment]]
        if type(tool_seg.input.label) == "string" then
          map[tool_seg.id] = tool_seg.input.label
        end
      end
    end
  end
  return map
end

---@class flemma.ast.ToolSibling
---@field use? flemma.ast.ToolUseSegment
---@field use_message? flemma.ast.MessageNode
---@field result? flemma.ast.ToolResultSegment
---@field result_message? flemma.ast.MessageNode

---Find the counterpart of a tool_use or tool_result segment.
---Given a tool_use, returns the matching tool_result and its parent message.
---Given a tool_result, returns the matching tool_use and its parent message.
---Returns first match in document order for duplicates.
---@param doc flemma.ast.DocumentNode
---@param segment flemma.ast.ToolUseSegment|flemma.ast.ToolResultSegment
---@return flemma.ast.ToolUseSegment|flemma.ast.ToolResultSegment|nil counterpart
---@return flemma.ast.MessageNode|nil counterpart_message
function M.find_tool_sibling(doc, segment)
  if segment.kind == "tool_use" then
    ---@cast segment flemma.ast.ToolUseSegment
    local target_id = segment.id
    for _, msg in ipairs(doc.messages) do
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "tool_result" and seg.tool_use_id == target_id then
          ---@cast seg flemma.ast.ToolResultSegment
          return seg, msg
        end
      end
    end
  elseif segment.kind == "tool_result" then
    ---@cast segment flemma.ast.ToolResultSegment
    local target_id = segment.tool_use_id
    for _, msg in ipairs(doc.messages) do
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "tool_use" and seg.id == target_id then
          ---@cast seg flemma.ast.ToolUseSegment
          return seg, msg
        end
      end
    end
  end
  return nil, nil
end

---Build a complete index of all tool pairs in the document, keyed by tool ID.
---For duplicate tool_result segments with the same tool_use_id, the last one
---in document order wins (most recent result is the current one).
---@param doc flemma.ast.DocumentNode
---@return table<string, flemma.ast.ToolSibling>
function M.build_tool_sibling_table(doc)
  ---@type table<string, flemma.ast.ToolSibling>
  local index = {}
  for _, msg in ipairs(doc.messages) do
    for _, seg in ipairs(msg.segments) do
      if seg.kind == "tool_use" then
        ---@cast seg flemma.ast.ToolUseSegment
        if not index[seg.id] then
          index[seg.id] = {}
        end
        index[seg.id].use = seg
        index[seg.id].use_message = msg
      elseif seg.kind == "tool_result" then
        ---@cast seg flemma.ast.ToolResultSegment
        if not index[seg.tool_use_id] then
          index[seg.tool_use_id] = {}
        end
        index[seg.tool_use_id].result = seg
        index[seg.tool_use_id].result_message = msg
      end
    end
  end
  return index
end

---Find the segment and its parent message at a given cursor position.
---All parameters are 1-indexed (matching Neovim cursor conventions and AST position conventions).
---@param doc flemma.ast.DocumentNode
---@param lnum integer 1-indexed line number
---@param col integer 1-indexed column number
---@return flemma.ast.Segment|nil segment
---@return flemma.ast.MessageNode|nil message
function M.find_segment_at_position(doc, lnum, col)
  for _, msg in ipairs(doc.messages) do
    local msg_start = msg.position.start_line
    local msg_end = msg.position.end_line or msg_start

    if lnum >= msg_start and lnum <= msg_end then
      ---@type flemma.ast.Segment|nil
      local fallback_seg = nil
      for _, seg in ipairs(msg.segments) do
        if not seg.position then
          goto continue_seg
        end

        local seg_start = seg.position.start_line
        local seg_end = seg.position.end_line or seg_start

        if lnum < seg_start or lnum > seg_end then
          goto continue_seg
        end

        -- Line matches. Refine with column info when available.
        if seg.position.start_col then
          if lnum == seg_start and lnum == seg_end and seg.position.end_col then
            -- Single-line segment: check full column range
            if col >= seg.position.start_col and col <= seg.position.end_col then
              return seg, msg
            end
            goto continue_seg
          elseif lnum == seg_start then
            -- Start line of multi-line segment: only check start_col
            if col >= seg.position.start_col then
              return seg, msg
            end
            goto continue_seg
          elseif lnum == seg_end and seg.position.end_col then
            -- End line of multi-line segment: only check end_col
            if col <= seg.position.end_col then
              return seg, msg
            end
            goto continue_seg
          else
            -- Interior line of multi-line segment: always matches
            return seg, msg
          end
        end

        -- No column info — multi-line hit beyond first line is a definite match
        if lnum > seg_start then
          return seg, msg
        end

        -- Segment on correct line but missing full column range — save as fallback
        -- so column-aware segments on the same line get a chance to match first.
        -- For segments with start_col only (e.g., from preprocessor rewriters),
        -- use the cursor position relative to start_col for a better guess.
        if seg.position.start_col then
          -- Has start_col but no end_col: use as fallback if cursor is at or after start
          if col >= seg.position.start_col then
            fallback_seg = seg
          end
        else
          -- No column info at all: always use as fallback
          fallback_seg = seg
        end

        ::continue_seg::
      end

      -- Return fallback if no column-specific match found
      if fallback_seg then
        return fallback_seg, msg
      end

      -- Cursor is within the message range but no segment matched
      -- (e.g., on the @Role: marker line). Return the message itself.
      return nil, msg
    end
  end
  return nil, nil
end

return M
