--- Tool result store — durable materialization of tool output.
---
--- Owns path resolution (preset expansion + template rendering), ID escaping,
--- namespace collapse, file writes with pluggable backup strategies, and
--- store-directory derivation. Replaces $TMPDIR truncation-overflow paths
--- with co-located durable storage.
---@class flemma.tools.Store
local M = {}

---Escape a tool/job ID for use in filenames.
---Any character outside [A-Za-z0-9._-] becomes `--` (double dash).
---Double underscore (`__`) from wire-encoded tool names is preserved.
---@param id string
---@return string
function M.escape_id(id)
  return (id:gsub("[^A-Za-z0-9._%-]", "--"))
end

---Collapse doubled `flemma` namespace segments in a rendered store path.
---Segment-anchored: only collapses when a segment exactly equal to `flemma`
---immediately follows a segment exactly equal to `flemma` or `.flemma`.
---Repeats to fixed point.
---@param path string
---@return string
function M.collapse_namespace(path)
  local segments = vim.split(path, "/", { plain = true })
  local prev
  repeat
    prev = vim.deepcopy(segments)
    local result = {}
    local i = 1
    while i <= #segments do
      local seg = segments[i]
      if seg == "flemma" and i > 1 and (result[#result] == "flemma" or result[#result] == ".flemma") then
        i = i + 1
      else
        result[#result + 1] = seg
        i = i + 1
      end
    end
    segments = result
  until #segments == #prev
  return table.concat(segments, "/")
end

return M
