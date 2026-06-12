--- Version backup strategy for the tool result store.
---
--- Before overwriting an existing store file, renames it to the next free
--- `<stem>.<n>.<ext>` version. Canonical path always holds the latest run.
---@class flemma.tools.store.backups.Version
local M = {}

---Compute the next version path for a file.
---@param path string Canonical file path
---@return string version_path
local function next_version_path(path)
  local stem = path:match("^(.+)%.[^./]+$") or path
  local ext = path:match("%.([^./]+)$") or ""
  local n = 1
  while true do
    local candidate = stem .. "." .. n .. (ext ~= "" and ("." .. ext) or "")
    if vim.fn.filereadable(candidate) == 0 then
      return candidate
    end
    n = n + 1
  end
end

---Back up an existing file by renaming it to the next version.
---No-op if the file does not exist.
---@param path string Path to back up
---@return boolean success
---@return string|nil error
function M.backup(path)
  if vim.fn.filereadable(path) == 0 then
    return true, nil
  end
  local version_path = next_version_path(path)
  local ok = os.rename(path, version_path)
  if not ok then
    return false, ("Failed to rename '%s' to '%s'"):format(path, version_path)
  end
  return true, nil
end

return M
