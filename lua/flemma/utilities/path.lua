--- Centralized file-path utilities
--- Resolve, decompose, and canonicalize paths in one place so every
--- consumer handles paths consistently.
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

---Canonical absolute path with symlink resolution.
---Makes `path` absolute via `:p`, then resolves symlinks.
---Works for non-existent paths (returns the textual absolute form).
---@param path string
---@return string
function M.realpath(path)
  return vim.fn.resolve(vim.fn.fnamemodify(path, ":p"))
end

---Parent directory of a path.
---@param path string
---@return string
function M.dirname(path)
  return vim.fn.fnamemodify(path, ":h")
end

---Filename component of a path (tail).
---@param path string
---@return string
function M.basename(path)
  return vim.fn.fnamemodify(path, ":t")
end

---Make a path relative to a base directory.
---If `path` starts with `base_dir/`, the prefix is replaced with `./`.
---If `path` equals `base_dir`, returns `"."`.
---Otherwise returns `path` unchanged.
---@param path string Absolute path to relativize
---@param base_dir string Base directory to strip
---@return string
function M.relative(path, base_dir)
  if path == base_dir then
    return "."
  end
  local prefix = base_dir .. "/"
  if vim.startswith(path, prefix) then
    return "." .. path:sub(#base_dir + 1)
  end
  return path
end

---Flatten a path into a single filename-safe component.
---Normalizes, strips the leading separator, then replaces any character
---outside `[A-Za-z0-9._-]` with `--` (same escape rule as ID escaping).
---@param path string
---@return string
function M.flatten(path)
  local normalized = vim.fs.normalize(path)
  if normalized:sub(1, 1) == "/" then
    normalized = normalized:sub(2)
  end
  return (normalized:gsub("[^A-Za-z0-9._%-]", "--"))
end

return M
