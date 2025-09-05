--- Claudius provider defaults
--- Centralized configuration for provider-specific defaults
local M = {}

-- Load models from centralized models.lua
local models_data = require("claudius.models")

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

-- Authentication notes for providers
M.auth_notes = {
  vertex = [[
## Authentication Options

Vertex AI requires OAuth2 authentication. You can:
1. Set VERTEX_AI_ACCESS_TOKEN environment variable with a valid access token
2. Store a service account JSON in the keyring (requires gcloud CLI)
3. Set VERTEX_SERVICE_ACCOUNT environment variable with the service account JSON
]],
}

-- Get the default model for a provider
function M.get_model(provider_name)
  local provider = models_data.providers[provider_name]
  return provider and provider.default or models_data.providers.claude.default
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

return M
