--- Fold rule for thinking blocks
---@class flemma.ui.folding.rules.Thinking : flemma.ui.folding.FoldRule
local M = {}

local utils = require("flemma.ui.folding.merge")

M.name = "thinking"
M.auto_close = true

---Populate fold map entries for all thinking block boundaries.
---Self-closing tags (start_line == end_line) are skipped because a single-line
---fold has nothing to hide, and set_fold would keep ">2" while dropping "<2"
---(same numeric level), leaving an unclosed fold that swallows subsequent lines.
---@param doc flemma.ast.DocumentNode
---@param fold_map table<integer, string>
function M.populate(doc, fold_map)
  for _, msg in ipairs(doc.messages) do
    for _, seg in ipairs(msg.segments) do
      if seg.kind == "thinking" and seg.position and seg.position.start_line ~= seg.position.end_line then
        utils.set_fold(fold_map, seg.position.start_line, ">2")
        utils.set_fold(fold_map, seg.position.end_line, "<2")
      end
    end
  end
end

---Get closeable ranges for auto-fold.
---Returns thinking blocks from all assistant messages that are no longer the
---active speaker (i.e., a subsequent message exists). This ensures thinking
---blocks are closeable even if the initial auto-close attempt failed during
---the narrow window when they were in the second-to-last message.
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

  for message_index, msg in ipairs(doc.messages) do
    if message_index == #doc.messages then
      break
    end
    for _, seg in ipairs(msg.segments) do
      if seg.kind == "thinking" and seg.position and seg.position.start_line ~= seg.position.end_line then
        table.insert(ranges, {
          id = "thinking:" .. message_index .. ":" .. seg.position.start_line,
          start_line = seg.position.start_line,
          end_line = seg.position.end_line,
        })
      end
    end
  end

  return ranges
end

return M
