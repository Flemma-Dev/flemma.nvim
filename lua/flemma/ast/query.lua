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
    if lnum < msg_start or lnum > msg_end then
      goto continue_msg
    end

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

      -- Line matches. Refine with column if available.
      if lnum == seg_start and seg.position.start_col and seg.position.end_col then
        if col >= seg.position.start_col and col <= seg.position.end_col then
          return seg, msg
        end
        goto continue_seg
      end

      -- Multi-line hit beyond first line — definite match
      if lnum > seg_start then
        return seg, msg
      end

      -- Single-line segment without column info — save as fallback
      if not fallback_seg then
        fallback_seg = seg
      end

      ::continue_seg::
    end

    -- Return fallback if no column-specific match found
    if fallback_seg then
      return fallback_seg, msg
    end

    ::continue_msg::
  end
  return nil, nil
end

return M
