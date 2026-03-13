---@class flemma.secrets.resolvers.Keychain : flemma.secrets.Resolver
--- Resolves credentials from macOS Keychain. (Stub — full implementation in Task 6.)
local M = {}

M.name = "keychain"
M.priority = 50

---@param _self flemma.secrets.resolvers.Keychain
---@param _credential flemma.secrets.Credential
---@return boolean
function M.supports(_self, _credential)
  return false
end

---@param _self flemma.secrets.resolvers.Keychain
---@param _credential flemma.secrets.Credential
---@return flemma.secrets.Result|nil
function M.resolve(_self, _credential)
  return nil
end

return M
