---@class flemma.secrets.resolvers.Gcloud : flemma.secrets.Resolver
--- Resolves credentials from Google Cloud (gcloud CLI). (Stub — full implementation in Task 7.)
local M = {}

M.name = "gcloud"
M.priority = 25

---@param _self flemma.secrets.resolvers.Gcloud
---@param _credential flemma.secrets.Credential
---@return boolean
function M.supports(_self, _credential)
  return false
end

---@param _self flemma.secrets.resolvers.Gcloud
---@param _credential flemma.secrets.Credential
---@return flemma.secrets.Result|nil
function M.resolve(_self, _credential)
  return nil
end

return M
