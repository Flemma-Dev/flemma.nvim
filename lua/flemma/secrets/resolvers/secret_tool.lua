---@class flemma.secrets.resolvers.SecretTool : flemma.secrets.Resolver
--- Resolves credentials from GNOME Keyring via secret-tool on Linux.
--- Convention: secret-tool lookup service <service> key <kind>.
--- Legacy fallback: tries key=api if the convention lookup fails, preserving
--- existing keyring entries stored under the previous scheme.
local M = {}

M.name = "secret_tool"
M.priority = 50

--- Legacy key name used by the previous auth implementation.
local LEGACY_KEY = "api"

--- Run a secret-tool lookup and return the trimmed value or nil.
---@param service string
---@param key string
---@return string|nil
local function try_lookup(service, key)
  local cmd = { "secret-tool", "lookup", "service", service, "key", key }
  local proc = vim.system(cmd, { text = true })
  local result = proc:wait()

  if result.code ~= 0 then
    return nil
  end

  local value = result.stdout
  if not value or #value == 0 then
    return nil
  end

  value = value:gsub("%s+$", "")
  if #value == 0 then
    return nil
  end

  return value
end

---@param _self flemma.secrets.resolvers.SecretTool
---@param _credential flemma.secrets.Credential
---@param ctx flemma.secrets.Context
---@return boolean
function M.supports(_self, _credential, ctx)
  if vim.fn.has("linux") ~= 1 then
    ctx:diagnostic("not available (requires Linux)")
    return false
  end
  if vim.fn.executable("secret-tool") ~= 1 then
    ctx:diagnostic("secret-tool not found in PATH")
    return false
  end
  return true
end

---@param _self flemma.secrets.resolvers.SecretTool
---@param credential flemma.secrets.Credential
---@param ctx flemma.secrets.Context
---@return flemma.secrets.Result|nil
function M.resolve(_self, credential, ctx)
  -- Try new convention first: service=<service> key=<kind>
  local value = try_lookup(credential.service, credential.kind)
  if value then
    return { value = value }
  end

  -- Legacy fallback: service=<service> key=api
  -- Skip for access_token kind: tokens are ephemeral and were never stored in
  -- keyrings — the legacy key=api entry holds static credentials (API keys or
  -- service account JSON), not access tokens. Letting gcloud resolve instead.
  if credential.kind ~= LEGACY_KEY and credential.kind ~= "access_token" then
    value = try_lookup(credential.service, LEGACY_KEY)
    if value then
      return { value = value }
    end
  end

  ctx:diagnostic("no entry found for service=" .. credential.service .. " key=" .. credential.kind)
  return nil
end

---@param service string
---@param key string
---@param callback fun(value: string|nil)
local function try_lookup_async(service, key, callback)
  vim.system({ "secret-tool", "lookup", "service", service, "key", key }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        callback(nil)
        return
      end
      local value = (result.stdout or ""):gsub("%s+$", "")
      if #value == 0 then
        callback(nil)
        return
      end
      callback(value)
    end)
  end)
end

---@param _self flemma.secrets.resolvers.SecretTool
---@param credential flemma.secrets.Credential
---@param ctx flemma.secrets.Context
---@param callback fun(result: flemma.secrets.Result|nil)
function M.resolve_async(_self, credential, ctx, callback)
  try_lookup_async(credential.service, credential.kind, function(value)
    if value then
      callback({ value = value })
      return
    end
    if credential.kind == LEGACY_KEY or credential.kind == "access_token" then
      ctx:diagnostic("no entry found for service=" .. credential.service .. " key=" .. credential.kind)
      callback(nil)
      return
    end
    try_lookup_async(credential.service, LEGACY_KEY, function(legacy_value)
      if legacy_value then
        callback({ value = legacy_value })
        return
      end
      ctx:diagnostic("no entry found for service=" .. credential.service .. " key=" .. credential.kind)
      callback(nil)
    end)
  end)
end

return M
