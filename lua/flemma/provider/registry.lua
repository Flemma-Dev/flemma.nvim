--- Provider registry for Flemma
--- Manages provider modules, capabilities, and model configuration
--- (Merged from providers.lua and config.lua)
local M = {}

-- Load models from centralized models.lua
local models_data = require("flemma.models")

--------------------------------------------------------------------------------
-- Provider registry (from providers.lua)
--------------------------------------------------------------------------------

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
      supports_thinking_budget = true,
      outputs_thinking = true,
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

--------------------------------------------------------------------------------
-- Model configuration (from config.lua)
--------------------------------------------------------------------------------

-- Helper function to get all available models for a provider as a list
local function get_provider_models(provider_name)
  local provider = models_data.providers[provider_name]
  if not provider then
    return {}
  end

  local models = {}
  for model_name, _ in pairs(provider.models) do
    table.insert(models, model_name)
  end

  return models
end

-- Legacy compatibility - expose defaults and models from models.lua
M.defaults = {}
M.models = {}

-- Populate defaults from models.lua
for provider_name, provider_data in pairs(models_data.providers) do
  M.defaults[provider_name] = provider_data.default
  M.models[provider_name] = get_provider_models(provider_name)
end

-- Get the default model for a provider
function M.get_model(provider_name)
  local provider = models_data.providers[provider_name]
  return provider and provider.default or models_data.providers.anthropic.default
end

-- Check if a model belongs to a specific provider
function M.is_provider_model(model_name, provider_name)
  -- If model_name is nil, it can't belong to any provider
  if model_name == nil then
    return false
  end

  -- Check if the provider exists
  local provider = models_data.providers[provider_name]
  if not provider then
    return false
  end

  -- Check if the model_name exists in the models for that provider
  return provider.models[model_name] ~= nil
end

-- Get the appropriate model for a provider
function M.get_appropriate_model(model_name, provider_name)
  -- If the model is appropriate for the provider, use it
  if M.is_provider_model(model_name, provider_name) then
    return model_name
  end

  -- Otherwise, return the default model for the provider
  return M.get_model(provider_name)
end

--- Extract provider/model parameters from parsed modeline tokens
-- @param parsed table Parsed tokens from modeline.parse/modeline.parse_args
-- @return table Parsed switch arguments (see provider_config_spec for structure)
function M.extract_switch_arguments(parsed)
  local info = {
    provider = nil,
    model = nil,
    parameters = {},
    positionals = {},
    extra_positionals = {},
    has_explicit_provider = false,
    has_explicit_model = false,
  }

  if type(parsed) ~= "table" then
    return info
  end

  local index = 1
  while parsed[index] ~= nil do
    info.positionals[#info.positionals + 1] = parsed[index]
    index = index + 1
  end

  if parsed.provider ~= nil then
    info.provider = parsed.provider
    info.has_explicit_provider = true
  end

  if parsed.model ~= nil then
    info.model = parsed.model
    info.has_explicit_model = true
  end

  if not info.provider and info.positionals[1] then
    info.provider = info.positionals[1]
  end

  if not info.model and info.positionals[2] then
    info.model = info.positionals[2]
  end

  if #info.positionals > 2 then
    for i = 3, #info.positionals do
      info.extra_positionals[#info.extra_positionals + 1] = info.positionals[i]
    end
  end

  for k, v in pairs(parsed) do
    if type(k) ~= "number" and k ~= "provider" and k ~= "model" then
      info.parameters[k] = v
    end
  end

  return info
end

return M
