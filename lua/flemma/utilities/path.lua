--- Centralized file-path resolution
--- Tilde expansion, absolute passthrough, relative joining, and normalization
--- in one place so every consumer resolves paths consistently.
---@class flemma.utilities.Path
local M = {}

---Resolve a file path against an optional base directory.
---
---  - `~/…` and bare `~` are expanded via `vim.fn.expand`
---  - Absolute paths are normalized and returned
---  - Relative paths are joined to `base_dir` (when supplied) and normalized
---  - Relative paths without a `base_dir` are returned as-is
---
---@param path string The input path
---@param base_dir? string Base directory for relative paths (nil ⇒ path returned as-is)
---@return string
function M.resolve(path, base_dir)
  if vim.startswith(path, "~/") or path == "~" then
    path = vim.fn.expand(path)
  end
  if vim.startswith(path, "/") then
    return vim.fs.normalize(path)
  end
  if base_dir then
    return vim.fs.normalize(base_dir .. "/" .. path)
  end
  return path
end

return M
