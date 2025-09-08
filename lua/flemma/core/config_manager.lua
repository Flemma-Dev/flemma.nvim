--- Centralized configuration management for Flemma
local M = {}

local log = require("flemma.logging")
local plugin_config = require("flemma.config")
local state = require("flemma.state")
local validation = require("flemma.core.validation")

--- Merges parameters for a provider, handling general and provider-specific parameters
-- @param base_params table Base parameters (may contain provider-specific sub-tables)
-- @param provider_name string The provider name
-- @param provider_overrides table|nil Provider-specific parameter overrides
-- @return table Merged parameters
function M.merge_parameters(base_params, provider_name, provider_overrides)
  local merged_params = {}
  base_params = base_params or {}
  provider_overrides = provider_overrides or base_params[provider_name] or {}

  -- 1. Copy all non-provider-specific keys from the base parameters
  for k, v in pairs(base_params) do
    -- Only copy if it's not a provider-specific table or if it's a general parameter
    if type(v) ~= "table" or plugin_config.is_general_parameter(k) then
      merged_params[k] = v
    end
  end

  -- 2. Merge the provider-specific overrides, potentially overwriting general keys
  for k, v in pairs(provider_overrides) do
    merged_params[k] = v
  end

  return merged_params
end

--- Prepares a complete configuration for a provider
-- @param provider_name string The provider name
-- @param model_name string|nil The model name (can be nil for default)
-- @param parameters table|nil The parameters
-- @return table|nil, string|nil The prepared config, or nil with error message
function M.prepare_config(provider_name, model_name, parameters)
  -- Validate provider
  local valid, err = validation.validate_provider(provider_name)
  if not valid then
    log.error("prepare_config(): " .. err)
    return nil, err
  end

  -- Validate and get appropriate model
  local validated_model, model_err = validation.validate_and_get_model(model_name, provider_name)
  if not validated_model then
    return nil, model_err
  end

  -- Merge parameters
  local merged_params = M.merge_parameters(parameters, provider_name)
  merged_params.model = validated_model

  -- Validate parameters (shows warnings but doesn't fail)
  validation.validate_parameters(provider_name, validated_model, merged_params)

  -- Log the final configuration
  log.debug(
    "prepare_config(): Prepared config for provider "
      .. log.inspect(provider_name)
      .. " with model "
      .. log.inspect(validated_model)
      .. " and parameters: "
      .. log.inspect(merged_params)
  )

  return {
    provider = provider_name,
    model = validated_model,
    parameters = merged_params,
  }, nil
end

--- Applies a configuration to the global state
-- @param config table The configuration to apply (should have provider, model, parameters)
function M.apply_config(config)
  local updated_config = state.get_config()
  updated_config.provider = config.provider
  updated_config.model = config.model
  updated_config.parameters = config.parameters
  state.set_config(updated_config)

  log.debug(
    "apply_config(): Applied config - provider: "
      .. log.inspect(config.provider)
      .. ", model: "
      .. log.inspect(config.model)
  )
end

return M
