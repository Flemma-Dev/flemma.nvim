---@class flemma.secrets
--- Credential resolution module. Providers declare what credentials they need;
--- registered resolvers compete (in priority order) to fulfill them.
local M = {}

local registry = require("flemma.secrets.registry")
local cache = require("flemma.secrets.cache")
local log = require("flemma.logging")
local context = require("flemma.secrets.context")

---@class flemma.secrets.Credential
---@field kind string
---@field service string
---@field description? string
---@field ttl? integer
---@field ttl_scale? number
---@field aliases? string[]

local BUILTIN_RESOLVERS = {
  "flemma.secrets.resolvers.environment",
  "flemma.secrets.resolvers.secret_tool",
  "flemma.secrets.resolvers.keychain",
  "flemma.secrets.resolvers.gcloud",
}

--- Build the cache key for a credential.
---@param kind string
---@param service string
---@return string
local function cache_key(kind, service)
  return kind .. ":" .. service
end

--- Resolve a credential. Checks cache first, then tries resolvers in priority order.
---@param credential flemma.secrets.Credential
---@return flemma.secrets.Result|nil result, flemma.secrets.ResolverDiagnostic[]|nil diagnostics
function M.resolve(credential)
  local key = cache_key(credential.kind, credential.service)

  local cached = cache.get(key)
  if cached then
    log.debug("secrets.resolve(): cache hit for " .. key)
    return cached
  end

  local all_diagnostics = {}
  local sorted = registry.get_all_sorted()
  for _, resolver in ipairs(sorted) do
    local ctx = context.new(resolver.name)
    if resolver:supports(credential, ctx) then
      log.debug("secrets.resolve(): trying resolver " .. resolver.name .. " for " .. key)
      local result = resolver:resolve(credential, ctx)
      if result then
        log.debug("secrets.resolve(): resolved by " .. resolver.name)
        cache.set(key, result, credential)
        return result
      end
    end
    vim.list_extend(all_diagnostics, ctx:get_diagnostics())
  end

  local description = credential.description or (credential.kind .. " for " .. credential.service)
  log.debug("secrets.resolve(): no resolver could fulfill: " .. description)

  local msg = "Flemma: could not resolve credential: " .. description
  if #all_diagnostics > 0 then
    for _, d in ipairs(all_diagnostics) do
      msg = msg .. "\n  [" .. d.resolver .. "] " .. d.message
    end
  end
  vim.notify(msg, vim.log.levels.WARN)

  return nil, #all_diagnostics > 0 and all_diagnostics or nil
end

--- Invalidate a specific cached credential.
---@param kind string
---@param service string
function M.invalidate(kind, service)
  cache.invalidate(cache_key(kind, service))
end

--- Invalidate all cached credentials.
function M.invalidate_all()
  cache.invalidate_all()
end

--- Register a resolver.
--- Single-arg form: loads a module path and registers the module under its name field.
--- Two-arg form: registers a resolver table directly under the given name.
---@param source string
---@param resolver? flemma.secrets.Resolver
function M.register(source, resolver)
  if resolver then
    registry.register(source, resolver)
  else
    local ok, mod = pcall(require, source)
    if not ok then
      vim.notify("Flemma: failed to load secrets resolver: " .. source, vim.log.levels.ERROR)
      log.error("secrets.register(): " .. tostring(mod))
      return
    end
    ---@cast mod flemma.secrets.Resolver
    if not mod.name then
      vim.notify("Flemma: secrets resolver module missing 'name' field: " .. source, vim.log.levels.ERROR)
      return
    end
    registry.register(mod.name, mod)
  end
end

--- Load all builtin resolvers. Called during plugin setup.
function M.setup()
  for _, module_path in ipairs(BUILTIN_RESOLVERS) do
    M.register(module_path)
  end
end

return M
