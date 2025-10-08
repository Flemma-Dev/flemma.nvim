--- Provider registry for Flemma
--- Manages available provider modules
local M = {}

local providers = {
  openai = "flemma.provider.openai",
  vertex = "flemma.provider.vertex",
  claude = "flemma.provider.claude",
}

---Get a provider module path for a specific provider name
---@param provider_name string The provider identifier (e.g., "openai", "vertex", "claude")
---@return string|nil module_path The provider module path, or nil if not found
function M.get(provider_name)
  return providers[provider_name]
end

---Check if a provider exists
---@param provider_name string The provider identifier
---@return boolean exists True if provider is registered
function M.has(provider_name)
  return providers[provider_name] ~= nil
end

---Get list of supported providers
---@return string[] providers Array of supported provider identifiers
function M.supported_providers()
  local provider_list = {}
  for provider_name in pairs(providers) do
    table.insert(provider_list, provider_name)
  end
  table.sort(provider_list)
  return provider_list
end

return M
