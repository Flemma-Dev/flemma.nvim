---@class flemma.secrets.resolvers.Keychain : flemma.secrets.Resolver
--- Resolves credentials from macOS Keychain via the security command.
--- Convention: security find-generic-password -s <service> -a <kind> -w.
--- Legacy fallback: tries -a api if the convention lookup fails, preserving
--- existing keychain entries stored under the previous scheme.
local M = {}

M.name = "keychain"
M.priority = 50

--- Legacy account name used by the previous auth implementation.
local LEGACY_ACCOUNT = "api"

--- Run a security find-generic-password lookup and return the trimmed value or nil.
---@param service string
---@param account string
---@return string|nil
local function try_lookup(service, account)
  local cmd = { "security", "find-generic-password", "-s", service, "-a", account, "-w" }
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

---@param _self flemma.secrets.resolvers.Keychain
---@param _credential flemma.secrets.Credential
---@param _ctx flemma.config.ConfigAware<table>
---@return boolean
function M.supports(_self, _credential, _ctx)
  return vim.fn.has("mac") == 1
end

---@param _self flemma.secrets.resolvers.Keychain
---@param credential flemma.secrets.Credential
---@param _ctx flemma.config.ConfigAware<table>
---@return flemma.secrets.Result|nil
function M.resolve(_self, credential, _ctx)
  -- Try new convention first: -s <service> -a <kind>
  local value = try_lookup(credential.service, credential.kind)
  if value then
    return { value = value }
  end

  -- Legacy fallback: -s <service> -a api
  -- Skip for access_token kind: tokens are ephemeral and were never stored in
  -- keychains — the legacy account=api holds static credentials (API keys or
  -- service account JSON), not access tokens. Letting gcloud resolve instead.
  if credential.kind ~= LEGACY_ACCOUNT and credential.kind ~= "access_token" then
    value = try_lookup(credential.service, LEGACY_ACCOUNT)
    if value then
      return { value = value }
    end
  end

  return nil
end

return M
