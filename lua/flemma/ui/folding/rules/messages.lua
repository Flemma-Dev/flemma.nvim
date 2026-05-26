--- Fold rule for message boundaries
---@class flemma.ui.folding.rules.Messages : flemma.ui.folding.FoldRule
local M = {}

local config_facade = require("flemma.config")
local utils = require("flemma.ui.folding.merge")

M.name = "messages"
M.auto_close = false

---Populate fold map entries for message start/end boundaries.
---When fold.gap is enabled and a message has trailing blank lines, the last
---blank line is marked as fold level 0 instead of receiving `<1`. This forces
---it outside all folds without colliding with any level-2 boundary (`<2`) on
---the preceding line.
---@param doc flemma.ast.DocumentNode
---@param fold_map table<integer, string>
function M.populate(doc, fold_map)
  local gap = config_facade.get().editing.fold.gap
  for _, msg in ipairs(doc.messages) do
    local end_line = msg.position.end_line --[[@as integer]]
    utils.set_fold(fold_map, msg.position.start_line, ">1")
    if gap and #msg.segments > 0 then
      local last_seg = msg.segments[#msg.segments]
      local seg_end = last_seg.position and last_seg.position.end_line
      if seg_end and seg_end < end_line then
        utils.set_fold(fold_map, end_line, "0")
      else
        utils.set_fold(fold_map, end_line, "<1")
      end
    else
      utils.set_fold(fold_map, end_line, "<1")
    end
  end
end

---Messages are never auto-closed.
---@param _doc flemma.ast.DocumentNode
---@return flemma.ui.folding.CloseableRange[]
function M.get_closeable_ranges(_doc)
  return {}
end

return M
