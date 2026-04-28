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

---@param _self flemma.secrets.resolvers.Keychain
---@param _credential flemma.secrets.Credential
---@param ctx flemma.secrets.Context
---@return boolean
function M.supports(_self, _credential, ctx)
  if vim.fn.has("mac") ~= 1 then
    ctx:diagnostic("not available (requires macOS)")
    return false
  end
  return true
end

---@param service string
---@param account string
---@param callback fun(value: string|nil)
local function try_lookup_async(service, account, callback)
  vim.system(
    { "security", "find-generic-password", "-s", service, "-a", account, "-w" },
    { text = true },
    function(result)
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
    end
  )
end

---@param _self flemma.secrets.resolvers.Keychain
---@param credential flemma.secrets.Credential
---@param ctx flemma.secrets.Context
---@param callback fun(result: flemma.secrets.Result|nil)
function M.resolve_async(_self, credential, ctx, callback)
  try_lookup_async(credential.service, credential.kind, function(value)
    if value then
      callback({ value = value })
      return
    end
    if credential.kind == LEGACY_ACCOUNT or credential.kind == "access_token" then
      ctx:diagnostic("no entry found for service=" .. credential.service .. " account=" .. credential.kind)
      callback(nil)
      return
    end
    try_lookup_async(credential.service, LEGACY_ACCOUNT, function(legacy_value)
      if legacy_value then
        callback({ value = legacy_value })
        return
      end
      ctx:diagnostic("no entry found for service=" .. credential.service .. " account=" .. credential.kind)
      callback(nil)
    end)
  end)
end

return M
