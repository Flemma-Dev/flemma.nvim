--- Shared module resolution infrastructure
--- Detects module paths (dot-notation), validates existence, and lazily loads modules.
---@class flemma.Loader
local M = {}

--- Check whether a string looks like a Lua module path (contains a dot).
---@param str string
---@return boolean
function M.is_module_path(str)
  return str:find(".", 1, true) ~= nil
end

--- Assert that a module can be found on package.path.
--- Throws with a descriptive error (including searched paths) on failure.
---@param path string Lua module path (e.g., "3rd.tools.todos")
function M.assert_exists(path)
  -- Check package.preload first (test fixtures and bundled modules)
  if package.preload[path] then
    return
  end
  local found = package.searchpath(path, package.path)
  if not found then
    error(string.format("flemma: module '%s' not found on package.path", path), 2)
  end
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
