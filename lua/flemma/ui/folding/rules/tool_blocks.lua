--- Fold rule for tool_use and tool_result blocks
---@class flemma.ui.folding.rules.ToolBlocks : flemma.ui.folding.FoldRule
local M = {}

M.name = "tool_blocks"
M.level = 2
M.auto_close = true

---Determine if a tool_result segment is in a terminal (foldable) state.
---Terminal: no status with content (completed), denied, rejected, aborted.
---In-flight: pending, approved, no status with empty content (executing).
---@param seg flemma.ast.ToolResultSegment
---@return boolean
local function is_tool_result_terminal(seg)
  if seg.status then
    return seg.status == "denied" or seg.status == "rejected" or seg.status == "aborted"
  end
  return seg.content ~= ""
end

---Build a tool_use_id -> terminal boolean lookup from all @You messages.
---Single O(M*S) pass eliminates the nested-loop bottleneck.
---@param doc flemma.ast.DocumentNode
---@return table<string, boolean>
local function build_completion_map(doc)
  local completed = {}
  for _, msg in ipairs(doc.messages) do
    if msg.role == "You" then
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "tool_result" then
          ---@cast seg flemma.ast.ToolResultSegment
          completed[seg.tool_use_id] = is_tool_result_terminal(seg)
        end
      end
    end
  end
  return completed
end

---Populate fold map entries for completed tool_use and terminal tool_result blocks.
---@param doc flemma.ast.DocumentNode
---@param fold_map table<integer, string>
function M.populate(doc, fold_map)
  local completed = build_completion_map(doc)

  for _, msg in ipairs(doc.messages) do
    for _, seg in ipairs(msg.segments) do
      if not seg.position or not seg.position.start_line or not seg.position.end_line then
        goto continue
      end

      -- Skip inline headers (segment starts on same line as message)
      if seg.position.start_line == msg.position.start_line then
        goto continue
      end

      if seg.kind == "tool_use" then
        ---@cast seg flemma.ast.ToolUseSegment
        if completed[seg.id] then
          if not fold_map[seg.position.start_line] then
            fold_map[seg.position.start_line] = ">2"
          end
          if not fold_map[seg.position.end_line] then
            fold_map[seg.position.end_line] = "<2"
          end
        end
      elseif seg.kind == "tool_result" then
        ---@cast seg flemma.ast.ToolResultSegment
        if is_tool_result_terminal(seg) then
          if not fold_map[seg.position.start_line] then
            fold_map[seg.position.start_line] = ">2"
          end
          if not fold_map[seg.position.end_line] then
            fold_map[seg.position.end_line] = "<2"
          end
        end
      end

      ::continue::
    end
  end
end

---Get closeable ranges for auto-fold.
---Returns all completed tool_use blocks and terminal tool_result blocks.
---@param doc flemma.ast.DocumentNode
---@return flemma.ui.folding.CloseableRange[]
function M.get_closeable_ranges(doc)
  local completed = build_completion_map(doc)
  local ranges = {}

  for _, msg in ipairs(doc.messages) do
    for _, seg in ipairs(msg.segments) do
      if not seg.position or not seg.position.start_line or not seg.position.end_line then
        goto continue
      end

      if seg.position.start_line == msg.position.start_line then
        goto continue
      end

      if seg.kind == "tool_use" then
        ---@cast seg flemma.ast.ToolUseSegment
        if completed[seg.id] then
          table.insert(ranges, {
            id = "tool_use:" .. seg.id,
            start_line = seg.position.start_line,
            end_line = seg.position.end_line,
          })
        end
      elseif seg.kind == "tool_result" then
        ---@cast seg flemma.ast.ToolResultSegment
        if is_tool_result_terminal(seg) then
          table.insert(ranges, {
            id = "tool_result:" .. seg.tool_use_id,
            start_line = seg.position.start_line,
            end_line = seg.position.end_line,
          })
        end
      end

      ::continue::
    end
  end

  return ranges
end

return M
