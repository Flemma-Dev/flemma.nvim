---@class flemma.secrets.registry
--- Registry for credential resolvers. Resolvers are tried in priority order
--- (highest first) during credential resolution.
local M = {}

local registry_utils = require("flemma.utilities.registry")

---@class flemma.secrets.Resolver
---@field name string
---@field priority integer
---@field supports fun(self: flemma.secrets.Resolver, credential: flemma.secrets.Credential, ctx: flemma.config.ConfigAware<table>): boolean
---@field resolve fun(self: flemma.secrets.Resolver, credential: flemma.secrets.Credential, ctx: flemma.config.ConfigAware<table>): flemma.secrets.Result|nil

---@type table<string, flemma.secrets.Resolver>
local resolvers = {}

--- Register a resolver under the given name.
---@param name string
---@param resolver flemma.secrets.Resolver
function M.register(name, resolver)
  registry_utils.validate_name(name, "secrets resolver")
  resolvers[name] = resolver
end

--- Remove a resolver by name.
---@param name string
---@return boolean removed
function M.unregister(name)
  if resolvers[name] then
    resolvers[name] = nil
    return true
  end
  return false
end

--- Get a resolver by name.
---@param name string
---@return flemma.secrets.Resolver|nil
function M.get(name)
  return resolvers[name]
end

--- Check whether a resolver is registered.
---@param name string
---@return boolean
function M.has(name)
  return resolvers[name] ~= nil
end

--- Return all resolvers sorted by priority descending.
---@return flemma.secrets.Resolver[]
function M.get_all_sorted()
  local sorted = {}
  for _, resolver in pairs(resolvers) do
    table.insert(sorted, resolver)
  end
  table.sort(sorted, function(a, b)
    return a.priority > b.priority
  end)
  return sorted
end

--- Remove all resolvers.
function M.clear()
  resolvers = {}
end

--- Return the number of registered resolvers.
---@return integer
function M.count()
  local n = 0
  for _ in pairs(resolvers) do
    n = n + 1
  end
  return n
end

return M
