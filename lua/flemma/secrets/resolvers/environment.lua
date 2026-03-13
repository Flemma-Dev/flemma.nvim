---@class flemma.secrets.resolvers.Environment : flemma.secrets.Resolver
--- Resolves credentials from environment variables. (Stub — full implementation in Task 4.)
local M = {}

M.name = "environment"
M.priority = 100

---@param _self flemma.secrets.resolvers.Environment
---@param _credential flemma.secrets.Credential
---@return boolean
function M.supports(_self, _credential)
  return true
end

---@param _self flemma.secrets.resolvers.Environment
---@param _credential flemma.secrets.Credential
---@return flemma.secrets.Result|nil
function M.resolve(_self, _credential)
  return nil
end

return M
