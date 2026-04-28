---@class flemma.secrets.resolvers.Environment : flemma.secrets.Resolver
--- Resolves credentials from environment variables.
--- Convention: {SERVICE}_{KIND} uppercased. E.g., service="anthropic", kind="api_key" → ANTHROPIC_API_KEY.
--- If credential.aliases is set, checks each alias in order after the convention.
local M = {}

M.name = "environment"
M.priority = 100

--- Build the conventional env var name from service and kind.
---@param service string
---@param kind string
---@return string
local function convention_env_var(service, kind)
  return string.upper(service .. "_" .. kind)
end

--- Try to read a non-empty value from an environment variable.
---@param var_name string
---@return string|nil
local function try_env(var_name)
  local value = os.getenv(var_name)
  if value and #value > 0 then
    return value
  end
  return nil
end

---@param _self flemma.secrets.resolvers.Environment
---@param _credential flemma.secrets.Credential
---@param _ctx flemma.config.ConfigAware<table>
---@return boolean
function M.supports(_self, _credential, _ctx)
  return true
end

---@param _self flemma.secrets.resolvers.Environment
---@param credential flemma.secrets.Credential
---@param ctx flemma.secrets.Context
---@return flemma.secrets.Result|nil
function M.resolve(_self, credential, ctx)
  -- Try convention first
  local var_name = convention_env_var(credential.service, credential.kind)
  local value = try_env(var_name)
  if value then
    return { value = value }
  end

  -- Try aliases
  if credential.aliases then
    for _, alias in ipairs(credential.aliases) do
      value = try_env(alias)
      if value then
        return { value = value }
      end
    end
  end

  local msg = var_name .. " not set"
  if credential.aliases and #credential.aliases > 0 then
    msg = msg .. " (also tried: " .. table.concat(credential.aliases, ", ") .. ")"
  end
  ctx:diagnostic(msg)

  return nil
end

---@param self flemma.secrets.resolvers.Environment
---@param credential flemma.secrets.Credential
---@param ctx flemma.secrets.Context
---@param callback fun(result: flemma.secrets.Result|nil)
function M.resolve_async(self, credential, ctx, callback)
  callback(M.resolve(self, credential, ctx))
end

return M
