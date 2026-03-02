--- Fold rule for thinking blocks
---@class flemma.ui.folding.rules.Thinking : flemma.ui.folding.FoldRule
local M = {}

local utils = require("flemma.ui.folding.utils")

M.name = "thinking"
M.auto_close = true

---Populate fold map entries for all thinking block boundaries.
---@param doc flemma.ast.DocumentNode
---@param fold_map table<integer, string>
function M.populate(doc, fold_map)
  for _, msg in ipairs(doc.messages) do
    for _, seg in ipairs(msg.segments) do
      if seg.kind == "thinking" and seg.position then
        utils.set_fold(fold_map, seg.position.start_line, ">2")
        utils.set_fold(fold_map, seg.position.end_line, "<2")
      end
    end
  end
end

---Get closeable ranges for auto-fold.
---Only returns thinking blocks from the second-to-last message when the
---last message is @You: (preserves existing behavior: don't fold thinking
---while the assistant is still the latest speaker).
---@param doc flemma.ast.DocumentNode
---@return flemma.ui.folding.CloseableRange[]
function M.get_closeable_ranges(doc)
  local ranges = {}

  if #doc.messages < 2 then
    return ranges
  end

  local last_message = doc.messages[#doc.messages]
  if last_message.role ~= "You" then
    return ranges
  end

  local second_to_last = doc.messages[#doc.messages - 1]
  local counter = 0
  for _, seg in ipairs(second_to_last.segments) do
    if seg.kind == "thinking" and seg.position then
      counter = counter + 1
      table.insert(ranges, {
        id = "thinking:" .. counter,
        start_line = seg.position.start_line,
        end_line = seg.position.end_line,
      })
    end
  end

  return ranges
end

return M
