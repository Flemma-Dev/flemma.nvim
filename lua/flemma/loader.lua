--- Shared module resolution infrastructure
--- Detects module paths (dot-notation), validates existence, and lazily loads modules.
---@class flemma.Loader
local M = {}

local URN_PREFIX = "urn:flemma:"

--- Check whether a string looks like a Lua module path (contains a dot).
--- Flemma URNs (urn:flemma:...) are never module paths, even when they embed dotted segments.
---@param str string
---@return boolean
function M.is_module_path(str)
  if str:sub(1, #URN_PREFIX) == URN_PREFIX then
    return false
  end
  return str:find(".", 1, true) ~= nil
end

--- Assert that a module can be found via require().
--- Checks package.loaded, package.preload, package.searchpath, and Neovim's
--- runtime path (lua/ directories), which package.searchpath alone does not cover.
--- Throws with a descriptive error on failure.
---@param path string Lua module path (e.g., "3rd.tools.todos")
function M.assert_exists(path)
  -- Already loaded or preloaded — definitely exists
  if package.loaded[path] or package.preload[path] then
    return
  end
  -- Standard Lua package.path
  if package.searchpath(path, package.path) then
    return
  end
  -- Neovim rtp: lua/<module_path>.lua
  local rtp_relpath = "lua/" .. path:gsub("%.", "/") .. ".lua"
  if vim.api.nvim_get_runtime_file(rtp_relpath, false)[1] then
    return
  end
  error(string.format("flemma: module '%s' not found on package.path", path), 2)
end

--- Load a module via require() with clear error attribution.
---@param path string Lua module path
---@return table module The loaded module table
function M.load(path)
  local ok, result = pcall(require, path)
  if not ok then
    error(string.format("flemma: failed to load module '%s': %s", path, tostring(result)), 2)
  end
  if type(result) ~= "table" then
    error(string.format("flemma: module '%s' returned %s, expected table", path, type(result)), 2)
  end
  return result
end

--- Load a module and extract a specific field from it.
--- Throws if the module doesn't export the expected field.
---@param path string Lua module path
---@param field string The field name to extract
---@param description string Human-readable description of what kind of module was expected (for error messages)
---@return any value The extracted field value
function M.load_select(path, field, description)
  local mod = M.load(path)
  local value = mod[field]
  if value == nil then
    error(string.format("flemma: module '%s' has no '%s' export (expected %s)", path, field, description), 2)
  end
  return value
end

return M
