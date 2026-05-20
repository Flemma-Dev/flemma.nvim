--- Glob pattern matching for tool names and config lists.
---@class flemma.utilities.glob
local M = {}

---Convert a glob pattern (with `*` wildcards) to a Lua pattern.
---@param glob string
---@return string
local function glob_to_pattern(glob)
  local escaped = glob:gsub("([%.%+%-%^%$%(%)%%'%[%]])", "%%%1")
  return "^" .. escaped:gsub("%*", ".*") .. "$"
end

---Check whether a string contains a wildcard.
---@param str string
---@return boolean
function M.is_glob(str)
  return str:find("*", 1, true) ~= nil
end

---Test whether a name matches a single glob pattern.
---@param name string
---@param glob string
---@return boolean
function M.match(name, glob)
  return name:find(glob_to_pattern(glob)) ~= nil
end

---Test whether a name matches any pattern in a list.
---Handles both exact strings and glob patterns.
---@param name string
---@param patterns string[]
---@return boolean
function M.matches_any(name, patterns)
  for _, pattern in ipairs(patterns) do
    if M.match(name, pattern) then
      return true
    end
  end
  return false
end

return M
