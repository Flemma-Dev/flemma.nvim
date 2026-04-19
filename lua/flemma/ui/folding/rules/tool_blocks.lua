--- Fold rule for tool_use and tool_result blocks
---@class flemma.ui.folding.rules.ToolBlocks : flemma.ui.folding.FoldRule
local M = {}

local utils = require("flemma.ui.folding.merge")
local ast = require("flemma.ast")

M.name = "tool_blocks"
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

---Check if a tool segment should be folded.
---@param seg flemma.ast.Segment
---@param completed table<string, boolean>
---@return boolean
local function is_foldable_tool(seg, completed)
  if seg.kind == "tool_use" then
    ---@cast seg flemma.ast.ToolUseSegment
    return completed[seg.id] == true
  elseif seg.kind == "tool_result" then
    ---@cast seg flemma.ast.ToolResultSegment
    return is_tool_result_terminal(seg)
  end
  return false
end

---Compute the fold end_line for a tool segment, extending past trailing blank
---lines when the next adjacent segment is also a foldable tool block.
---Two tool segments are "adjacent" if only whitespace text separates them.
---@param seg_index integer Current segment index in msg.segments
---@param msg flemma.ast.MessageNode
---@param base_end_line integer The segment's own position.end_line
---@param completed table<string, boolean>
---@return integer end_line Possibly-extended fold end
local function compute_fold_end(seg_index, msg, base_end_line, completed)
  for j = seg_index + 1, #msg.segments do
    local next_seg = msg.segments[j]
    if next_seg.kind == "tool_use" or next_seg.kind == "tool_result" then
      if
        next_seg.position
        and next_seg.position.start_line
        and next_seg.position.start_line ~= msg.position.start_line
        and is_foldable_tool(next_seg, completed)
      then
        return next_seg.position.start_line - 1
      end
      return base_end_line
    end
    if next_seg.kind == "text" then
      ---@cast next_seg flemma.ast.TextSegment
      if next_seg.value:match("%S") then
        return base_end_line
      end
    else
      return base_end_line
    end
  end
  return base_end_line
end

---Build a tool_use_id -> terminal boolean lookup using the sibling table.
---@param doc flemma.ast.DocumentNode
---@return table<string, boolean>
local function build_completion_map(doc)
  local siblings = ast.build_tool_sibling_table(doc)
  local completed = {}
  for tool_id, sibling in pairs(siblings) do
    if sibling.result then
      completed[tool_id] = is_tool_result_terminal(sibling.result)
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
    for seg_index, seg in ipairs(msg.segments) do
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
          local end_line = compute_fold_end(seg_index, msg, seg.position.end_line, completed)
          utils.set_fold(fold_map, seg.position.start_line, ">2")
          utils.set_fold(fold_map, end_line, "<2")
        end
      elseif seg.kind == "tool_result" then
        ---@cast seg flemma.ast.ToolResultSegment
        if is_tool_result_terminal(seg) then
          local end_line = compute_fold_end(seg_index, msg, seg.position.end_line, completed)
          utils.set_fold(fold_map, seg.position.start_line, ">2")
          utils.set_fold(fold_map, end_line, "<2")
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
    for seg_index, seg in ipairs(msg.segments) do
      if not seg.position or not seg.position.start_line or not seg.position.end_line then
        goto continue
      end

      if seg.position.start_line == msg.position.start_line then
        goto continue
      end

      if seg.kind == "tool_use" then
        ---@cast seg flemma.ast.ToolUseSegment
        if completed[seg.id] then
          local end_line = compute_fold_end(seg_index, msg, seg.position.end_line, completed)
          table.insert(ranges, {
            id = "tool_use:" .. seg.id,
            start_line = seg.position.start_line,
            end_line = end_line,
            config_key = "tool_use",
          })
        end
      elseif seg.kind == "tool_result" then
        ---@cast seg flemma.ast.ToolResultSegment
        if is_tool_result_terminal(seg) then
          local end_line = compute_fold_end(seg_index, msg, seg.position.end_line, completed)
          table.insert(ranges, {
            id = "tool_result:" .. seg.tool_use_id,
            start_line = seg.position.start_line,
            end_line = end_line,
            config_key = "tool_result",
          })
        end
      end

      ::continue::
    end
  end

  return ranges
end

return M
