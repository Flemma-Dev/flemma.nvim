---@class flemma.ui.folding.FoldRule
---@field name string
---@field level integer
---@field auto_close boolean
---@field populate fun(doc: flemma.ast.DocumentNode, fold_map: table<integer, string>)
---@field get_closeable_ranges fun(doc: flemma.ast.DocumentNode): flemma.ui.folding.CloseableRange[]

---@class flemma.ui.folding.CloseableRange
---@field id string
---@field start_line integer
---@field end_line integer

--- Fold rule for frontmatter fenced blocks
---@class flemma.ui.folding.rules.Frontmatter : flemma.ui.folding.FoldRule
local M = {}

M.name = "frontmatter"
M.level = 2
M.auto_close = false

---Populate fold map entries for frontmatter boundaries.
---@param doc flemma.ast.DocumentNode
---@param fold_map table<integer, string>
function M.populate(doc, fold_map)
  local fm = doc.frontmatter
  if not fm then
    return
  end
  if not fold_map[fm.position.start_line] then
    fold_map[fm.position.start_line] = ">2"
  end
  if not fold_map[fm.position.end_line] then
    fold_map[fm.position.end_line] = "<2"
  end
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
