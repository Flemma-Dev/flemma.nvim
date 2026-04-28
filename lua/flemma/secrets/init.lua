---@class flemma.secrets
--- Credential resolution module. Providers declare what credentials they need;
--- registered resolvers compete (in priority order) to fulfill them.
local M = {}

local cache = require("flemma.secrets.cache")
local context = require("flemma.secrets.context")
local log = require("flemma.logging")
local notify = require("flemma.notify")
local readiness = require("flemma.readiness")
local registry = require("flemma.secrets.registry")

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

---@param credential flemma.secrets.Credential
---@return flemma.secrets.Result
function M.resolve(credential)
  local key = cache_key(credential.kind, credential.service)

  local cached = cache.get(key)
  if cached then
    log.debug("secrets.resolve(): cache hit for " .. key)
    return cached
  end

  local boundary = readiness.get_or_create_boundary("secrets:" .. key, function(done)
    M.resolve_async(credential, function(result, diagnostics)
      if result then
        done({ ok = true })
      else
        done({ ok = false, diagnostics = diagnostics })
      end
    end)
  end)

  error(
    readiness.Suspense.new(
      "Resolving " .. (credential.description or (credential.kind .. " for " .. credential.service)) .. "\u{2026}",
      boundary
    )
  )
end

---@param credential flemma.secrets.Credential
---@param callback fun(result: flemma.secrets.Result|nil, diagnostics: flemma.secrets.ResolverDiagnostic[]|nil)
function M.resolve_async(credential, callback)
  local key = cache_key(credential.kind, credential.service)
  local cached = cache.get(key)
  if cached then
    vim.schedule(function()
      callback(cached, nil)
    end)
    return
  end
  local all_diagnostics = {}
  local sorted = registry.get_all_sorted()
  local index = 1

  local function try_next()
    while index <= #sorted do
      local resolver = sorted[index]
      index = index + 1
      local ctx = context.new(resolver.name)
      if resolver:supports(credential, ctx) then
        if type(resolver.resolve_async) == "function" then
          resolver:resolve_async(credential, ctx, function(result)
            vim.list_extend(all_diagnostics, ctx:get_diagnostics())
            if result then
              cache.set(key, result, credential)
              callback(result, nil)
            else
              try_next()
            end
          end)
          return
        end
        local result = resolver:resolve(credential, ctx)
        vim.list_extend(all_diagnostics, ctx:get_diagnostics())
        if result then
          cache.set(key, result, credential)
          callback(result, nil)
          return
        end
      else
        vim.list_extend(all_diagnostics, ctx:get_diagnostics())
      end
    end
    callback(nil, #all_diagnostics > 0 and all_diagnostics or nil)
  end

  try_next()
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
      notify.error("failed to load secrets resolver: " .. source)
      log.error("secrets.register(): " .. tostring(mod))
      return
    end
    ---@cast mod flemma.secrets.Resolver
    if not mod.name then
      notify.error("secrets resolver module missing 'name' field: " .. source)
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
