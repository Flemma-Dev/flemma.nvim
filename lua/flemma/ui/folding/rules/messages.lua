--- Fold rule for message boundaries
---@class flemma.ui.folding.rules.Messages : flemma.ui.folding.FoldRule
local M = {}

local utils = require("flemma.ui.folding.merge")

M.name = "messages"
M.auto_close = false

---Populate fold map entries for message start/end boundaries.
---@param doc flemma.ast.DocumentNode
---@param fold_map table<integer, string>
function M.populate(doc, fold_map)
  for _, msg in ipairs(doc.messages) do
    utils.set_fold(fold_map, msg.position.start_line, ">1")
    utils.set_fold(fold_map, msg.position.end_line, "<1")
  end
end

---Messages are never auto-closed.
---@param _doc flemma.ast.DocumentNode
---@return flemma.ui.folding.CloseableRange[]
function M.get_closeable_ranges(_doc)
  return {}
end

return M
