--- Provider registry for Flemma
--- Manages available provider modules and their capabilities
local M = {}

-- Track deprecation warnings to show only once per session
local deprecated_warning_shown = {}

-- Deprecated provider aliases (old_name -> new_name)
local provider_aliases = {
  claude = "anthropic",
}

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
  anthropic = {
    module = "flemma.provider.providers.anthropic",
    capabilities = {
      supports_reasoning = false,
      supports_thinking_budget = false,
      outputs_thinking = false,
    },
    display_name = "Anthropic",
  },
}

---Resolve a provider name, handling deprecated aliases
---Shows a deprecation warning once per session for deprecated names
---@param provider_name string The provider identifier (may be an alias)
---@return string resolved_name The resolved provider name
function M.resolve(provider_name)
  local alias_target = provider_aliases[provider_name]
  if alias_target then
    -- Show deprecation warning once per session per alias
    if not deprecated_warning_shown[provider_name] then
      deprecated_warning_shown[provider_name] = true
      vim.notify(
        string.format(
          "Flemma: The '%s' provider has been renamed to '%s'. Update your configuration.",
          provider_name,
          alias_target
        ),
        vim.log.levels.WARN
      )
    end
    return alias_target
  end
  return provider_name
end

---Get a provider module path for a specific provider name
---@param provider_name string The provider identifier (e.g., "openai", "vertex", "anthropic")
---@return string|nil module_path The provider module path, or nil if not found
function M.get(provider_name)
  local resolved = M.resolve(provider_name)
  local provider = providers[resolved]
  return provider and provider.module or nil
end

---Check if a provider exists
---@param provider_name string The provider identifier
---@return boolean exists True if provider is registered
function M.has(provider_name)
  local resolved = M.resolve(provider_name)
  return providers[resolved] ~= nil
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
  local resolved = M.resolve(provider_name)
  local provider = providers[resolved]
  return provider and provider.capabilities or nil
end

---Get provider display name
---@param provider_name string The provider identifier
---@return string|nil display_name Provider display name, or nil if not found
function M.get_display_name(provider_name)
  local resolved = M.resolve(provider_name)
  local provider = providers[resolved]
  return provider and provider.display_name or nil
end

return M
