--- Fold rule for message boundaries
---@class flemma.ui.folding.rules.Messages : flemma.ui.folding.FoldRule
local M = {}

M.name = "messages"
M.level = 1
M.auto_close = false

---Populate fold map entries for message start/end boundaries.
---@param doc flemma.ast.DocumentNode
---@param fold_map table<integer, string>
function M.populate(doc, fold_map)
  for _, msg in ipairs(doc.messages) do
    if not fold_map[msg.position.start_line] then
      fold_map[msg.position.start_line] = ">1"
    end
    if not fold_map[msg.position.end_line] then
      fold_map[msg.position.end_line] = "<1"
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
