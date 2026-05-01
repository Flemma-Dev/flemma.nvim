--- Shared utilities for fold rule implementations
---@class flemma.ui.folding.Merge
local M = {}

---Extract the numeric fold level from a fold expression string.
---@param fold_expr string e.g. ">2", "<1"
---@return integer
local function extract_level(fold_expr)
  return tonumber(fold_expr:sub(2)) or 0
end

---Write a fold level into the fold map, letting the higher fold level win.
---When two rules claim the same line, the entry with the greater numeric level
---is kept, making rule evaluation order irrelevant for correctness.
---@param fold_map table<integer, string>
---@param lnum integer 1-indexed line number
---@param fold_expr string Fold expression in ">N" or "<N" format (e.g. ">2", "<1")
function M.set_fold(fold_map, lnum, fold_expr)
  local existing = fold_map[lnum]
  if not existing then
    fold_map[lnum] = fold_expr
    return
  end
  if extract_level(fold_expr) > extract_level(existing) then
    fold_map[lnum] = fold_expr
  end
end

return M
