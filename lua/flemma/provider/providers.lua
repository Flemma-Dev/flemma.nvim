--- Provider registry for Flemma
--- Manages available provider modules and their capabilities
local M = {}

local providers = {
  openai = {
    module = "flemma.provider.providers.openai",
    capabilities = {
      supports_reasoning = true,
      supports_thinking_budget = false,
      outputs_thinking = false,
    },
    display_name = "OpenAI",
  },
  vertex = {
    module = "flemma.provider.providers.vertex",
    capabilities = {
      supports_reasoning = false,
      supports_thinking_budget = true,
      outputs_thinking = true,
    },
    display_name = "Vertex AI",
  },
  claude = {
    module = "flemma.provider.providers.claude",
    capabilities = {
      supports_reasoning = false,
      supports_thinking_budget = false,
      outputs_thinking = false,
    },
    display_name = "Claude",
  },
}

---Get a provider module path for a specific provider name
---@param provider_name string The provider identifier (e.g., "openai", "vertex", "claude")
---@return string|nil module_path The provider module path, or nil if not found
function M.get(provider_name)
  local provider = providers[provider_name]
  return provider and provider.module or nil
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

---Get provider capabilities
---@param provider_name string The provider identifier
---@return table|nil capabilities Provider capabilities table, or nil if not found
function M.get_capabilities(provider_name)
  local provider = providers[provider_name]
  return provider and provider.capabilities or nil
end

---Get provider display name
---@param provider_name string The provider identifier
---@return string|nil display_name Provider display name, or nil if not found
function M.get_display_name(provider_name)
  local provider = providers[provider_name]
  return provider and provider.display_name or nil
end

return M
