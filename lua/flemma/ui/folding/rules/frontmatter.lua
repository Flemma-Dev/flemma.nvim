--- Fold rule for frontmatter fenced blocks
---@class flemma.ui.folding.rules.Frontmatter : flemma.ui.folding.FoldRule
local M = {}

local utils = require("flemma.ui.folding.merge")

M.name = "frontmatter"
M.auto_close = false

---Whether the current window's conceal setup would hide the frontmatter fence
---delimiter lines (`conceal_lines = ""` metadata on the `markdown` treesitter
---parser fires at `conceallevel >= 1`). Folding the frontmatter in that state
---anchors the fold placeholder on a concealed row, making the whole fold
---disappear — see docs/conceal.md "Folds and `conceal_lines`".
---@return boolean
local function fences_hidden_in_current_window()
  return vim.wo.conceallevel >= 1
end

---Populate fold map entries for frontmatter boundaries.
---Skipped entirely when fence delimiter lines would be concealed — letting the
---body render inline instead of collapsing into an invisible fold.
---@param doc flemma.ast.DocumentNode
---@param fold_map table<integer, string>
function M.populate(doc, fold_map)
  local fm = doc.frontmatter
  if not fm then
    return
  end
  if fences_hidden_in_current_window() then
    return
  end
  utils.set_fold(fold_map, fm.position.start_line, ">2")
  utils.set_fold(fold_map, fm.position.end_line, "<2")
end

---Get closeable ranges for auto-fold. Frontmatter is never auto-closed by default.
---Returns nothing when fence lines are concealed — there is no fold to close.
---@param doc flemma.ast.DocumentNode
---@return flemma.ui.folding.CloseableRange[]
function M.get_closeable_ranges(doc)
  local fm = doc.frontmatter
  if not fm then
    return {}
  end
  if fences_hidden_in_current_window() then
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
