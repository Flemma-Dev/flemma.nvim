--- Flemma provider defaults
--- Centralized configuration for provider-specific defaults
local M = {}

-- Load models from centralized models.lua
local models_data = require("flemma.models")

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
