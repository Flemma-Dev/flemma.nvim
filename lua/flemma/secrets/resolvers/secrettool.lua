---@class flemma.secrets.resolvers.Secrettool : flemma.secrets.Resolver
--- Resolves credentials from GNOME Keyring via secret-tool. (Stub — full implementation in Task 5.)
local M = {}

M.name = "secrettool"
M.priority = 50

---@param _self flemma.secrets.resolvers.Secrettool
---@param _credential flemma.secrets.Credential
---@return boolean
function M.supports(_self, _credential)
  return false
end

---@param _self flemma.secrets.resolvers.Secrettool
---@param _credential flemma.secrets.Credential
---@return flemma.secrets.Result|nil
function M.resolve(_self, _credential)
  return nil
end

return M
