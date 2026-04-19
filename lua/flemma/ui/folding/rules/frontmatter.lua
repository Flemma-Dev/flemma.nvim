--- Fold rule for frontmatter fenced blocks
---@class flemma.ui.folding.rules.Frontmatter : flemma.ui.folding.FoldRule
local M = {}

local utils = require("flemma.ui.folding.merge")

M.name = "frontmatter"
M.auto_close = false

---Populate fold map entries for frontmatter boundaries.
---@param doc flemma.ast.DocumentNode
---@param fold_map table<integer, string>
function M.populate(doc, fold_map)
  local fm = doc.frontmatter
  if not fm then
    return
  end
  utils.set_fold(fold_map, fm.position.start_line, ">2")
  utils.set_fold(fold_map, fm.position.end_line, "<2")
end

---Get closeable ranges for auto-fold. Frontmatter is never auto-closed by default.
---@param doc flemma.ast.DocumentNode
---@return flemma.ui.folding.CloseableRange[]
function M.get_closeable_ranges(doc)
  local fm = doc.frontmatter
  if not fm then
    return {}
  end
  return {
    {
      id = "frontmatter",
      start_line = fm.position.start_line,
      end_line = fm.position.end_line,
    },
  }
end

return M
