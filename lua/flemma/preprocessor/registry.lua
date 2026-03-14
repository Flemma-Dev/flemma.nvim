--- Rewriter definition storage
--- Pure storage for preprocessor rewriter objects — no async or loading logic
---@class flemma.preprocessor.Registry
local M = {}

local loader = require("flemma.loader")
local registry_utils = require("flemma.registry")

---@type table<string, flemma.preprocessor.Rewriter>
local rewriters = {}

--- Register a rewriter under the given name.
--- Accepts three overloads:
---   (name, rewriter)        — register a rewriter under an explicit name
---   (module_path_string)    — register a rewriter from a module path (deferred load)
---   (rewriter_object)       — register a rewriter using its .name field
---@param source string|flemma.preprocessor.Rewriter
---@param definition? flemma.preprocessor.Rewriter
function M.register(source, definition)
  if definition then
    -- Overload: (name, rewriter)
    ---@cast source string
    if loader.is_module_path(source) then
      -- Module path registration — validate and store for deferred load
      loader.assert_exists(source)
      local mod = loader.load(source)
      local rewriter = mod.rewriter
      if not rewriter then
        error(string.format("flemma: module '%s' has no 'rewriter' export", source), 2)
      end
      rewriters[rewriter.name] = rewriter
    else
      registry_utils.validate_name(source, "rewriter")
      rewriters[source] = definition
    end
  elseif type(source) == "string" then
    -- Overload: (module_path_string)
    loader.assert_exists(source)
    local mod = loader.load(source)
    local rewriter = mod.rewriter
    if not rewriter then
      error(string.format("flemma: module '%s' has no 'rewriter' export", source), 2)
    end
    rewriters[rewriter.name] = rewriter
  else
    -- Overload: (rewriter_object)
    ---@cast source flemma.preprocessor.Rewriter
    local name = source.name
    registry_utils.validate_name(name, "rewriter")
    rewriters[name] = source
  end
end

--- Remove a rewriter by name.
---@param name string
---@return boolean removed
function M.unregister(name)
  if rewriters[name] then
    rewriters[name] = nil
    return true
  end
  return false
end

--- Get a rewriter by name.
---@param name string
---@return flemma.preprocessor.Rewriter|nil
function M.get(name)
  return rewriters[name]
end

--- Check whether a rewriter is registered.
---@param name string
---@return boolean
function M.has(name)
  return rewriters[name] ~= nil
end

--- Return all rewriters sorted by priority ascending (lower priority first).
---@return flemma.preprocessor.Rewriter[]
function M.get_all()
  local sorted = {}
  for _, rewriter in pairs(rewriters) do
    table.insert(sorted, rewriter)
  end
  table.sort(sorted, function(a, b)
    if a.priority == b.priority then
      return a.name < b.name
    end
    return a.priority < b.priority
  end)
  return sorted
end

--- Remove all rewriters.
function M.clear()
  rewriters = {}
end

--- Return the number of registered rewriters.
---@return integer
function M.count()
  local n = 0
  for _ in pairs(rewriters) do
    n = n + 1
  end
  return n
end

return M
