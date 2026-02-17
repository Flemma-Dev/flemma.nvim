--- Centralized configuration management for Flemma
--- Includes validation logic (merged from core/validation.lua)
---@class flemma.core.ConfigManager
local M = {}

local log = require("flemma.logging")
local state = require("flemma.state")
local registry = require("flemma.provider.registry")

---Check if a parameter key is a general parameter applicable to all providers
---@param key string
---@return boolean
local function is_general_parameter(key)
  return key == "max_tokens"
    or key == "temperature"
    or key == "timeout"
    or key == "connect_timeout"
    or key == "cache_retention"
    or key == "thinking"
end

--------------------------------------------------------------------------------
-- Validation functions (merged from core/validation.lua)
--------------------------------------------------------------------------------

---Validates that a provider name is supported
---@param provider_name string
---@return boolean valid, string|nil err
function M.validate_provider(provider_name)
  if not registry.has(provider_name) then
    local err = string.format(
      "Flemma: Unknown provider '%s'. Supported providers are: %s",
      tostring(provider_name),
      table.concat(registry.supported_providers(), ", ")
    )
    return false, err
  end
  return true, nil
end

---Validates and returns the appropriate model for a provider
---@param model_name string|nil
---@param provider_name string
---@return string|nil validated_model, string|nil err
function M.validate_and_get_model(model_name, provider_name)
  local original_model = model_name
  local validated_model = registry.get_appropriate_model(original_model, provider_name)

  -- Log if we had to switch models during validation
  if validated_model ~= original_model and original_model ~= nil then
    local warn_msg = string.format(
      "Flemma: Model '%s' is not valid for provider '%s'. Using default: '%s'.",
      tostring(original_model),
      tostring(provider_name),
      tostring(validated_model)
    )
    vim.notify(warn_msg, vim.log.levels.WARN, { title = "Flemma Configuration" })
    log.warn(warn_msg)

    log.info(
      "validate_and_get_model(): Model "
        .. log.inspect(original_model)
        .. " is not valid for provider "
        .. log.inspect(provider_name)
        .. ". Using default: "
        .. log.inspect(validated_model)
    )
  elseif original_model == nil then
    log.debug(
      "validate_and_get_model(): Using default model for provider "
        .. log.inspect(provider_name)
        .. ": "
        .. log.inspect(validated_model)
    )
  end

  return validated_model, nil
end

---Validates provider-specific parameters and shows warnings for known issues
---@param provider_name string
---@param model_name string
---@param parameters table<string, any>
---@return boolean success
function M.validate_parameters(provider_name, model_name, parameters)
  -- Get the provider module path
  local provider_module_path = registry.get(provider_name)
  if not provider_module_path then
    log.warn("validate_parameters(): Unknown provider: " .. tostring(provider_name))
    return true
  end

  -- Load the provider module
  local ok, provider_module = pcall(require, provider_module_path)
  if not ok or not provider_module then
    log.warn("validate_parameters(): Failed to load provider module: " .. tostring(provider_module_path))
    return true
  end

  -- Delegate to provider-specific validation (or base implementation)
  return provider_module.validate_parameters(model_name, parameters)
end

--------------------------------------------------------------------------------
-- Configuration management
--------------------------------------------------------------------------------

---Merges parameters for a provider, handling general and provider-specific parameters
---Priority (lowest to highest):
---  1. Registered default_parameters from provider registry
---  2. General params from base_params (max_tokens, temperature, etc.)
---  3. Provider-specific overrides from base_params[provider_name] or explicit overrides
---@param base_params table<string, any>
---@param provider_name string
---@param provider_overrides? table<string, any>
---@return table<string, any> merged
function M.merge_parameters(base_params, provider_name, provider_overrides)
  local merged_params = {}
  base_params = base_params or {}
  -- Merge provider sub-table from base_params with explicit overrides (explicit wins).
  -- Previously, explicit overrides replaced the sub-table entirely, silently dropping
  -- keys like project_id when switching providers via presets.
  local provider_sub = type(base_params[provider_name]) == "table" and base_params[provider_name] or {}
  if provider_overrides then
    local merged_overrides = {}
    for k, v in pairs(provider_sub) do
      merged_overrides[k] = v
    end
    for k, v in pairs(provider_overrides) do
      merged_overrides[k] = v
    end
    provider_overrides = merged_overrides
  else
    provider_overrides = provider_sub
  end

  -- 1. Start with registered default parameters (lowest priority)
  local registered_defaults = registry.get_default_parameters(provider_name)
  if registered_defaults then
    for k, v in pairs(registered_defaults) do
      merged_params[k] = v
    end
  end

  -- 2. Copy all non-provider-specific keys from the base parameters
  for k, v in pairs(base_params) do
    -- Only copy if it's not a provider-specific table or if it's a general parameter
    if type(v) ~= "table" or is_general_parameter(k) then
      merged_params[k] = v
    end
  end

  -- 3. Merge the provider-specific overrides, potentially overwriting general keys
  for k, v in pairs(provider_overrides) do
    merged_params[k] = v
  end

  return merged_params
end

---Prepares a complete configuration for a provider
---@param provider_name string
---@param model_name? string
---@param parameters? table<string, any>
---@return { provider: string, model: string, parameters: table<string, any> }|nil config, string|nil err
function M.prepare_config(provider_name, model_name, parameters)
  -- Validate provider
  local valid, err = M.validate_provider(provider_name)
  if not valid then
    log.error("prepare_config(): " .. err)
    return nil, err
  end

  -- Resolve provider alias (e.g., 'claude' -> 'anthropic')
  -- This must happen after validation but before any other use of provider_name
  local resolved_provider = registry.resolve(provider_name)

  -- Validate and get appropriate model
  local validated_model, model_err = M.validate_and_get_model(model_name, resolved_provider)
  if not validated_model then
    return nil, model_err
  end

  -- Merge parameters
  local merged_params = M.merge_parameters(parameters or {}, resolved_provider)
  merged_params.model = validated_model

  -- Validate parameters (shows warnings but doesn't fail)
  M.validate_parameters(resolved_provider, validated_model, merged_params)

  -- Log the final configuration
  log.debug(
    "prepare_config(): Prepared config for provider "
      .. log.inspect(resolved_provider)
      .. " with model "
      .. log.inspect(validated_model)
      .. " and parameters: "
      .. log.inspect(merged_params)
  )

  return {
    provider = resolved_provider,
    model = validated_model,
    parameters = merged_params,
  }, nil
end

---Applies a configuration to the global state
---@param config { provider: string, model: string, parameters: table<string, any> }
function M.apply_config(config)
  local updated_config = state.get_config()
  updated_config.provider = config.provider
  updated_config.model = config.model
  -- NOTE: Do NOT overwrite updated_config.parameters here. The provider instance
  -- holds its own flattened parameters. The global config must preserve the original
  -- nested structure (with provider sub-tables like parameters.vertex) so that
  -- future switch_provider calls can correctly resolve provider-specific params.
  state.set_config(updated_config)

  log.debug(
    "apply_config(): Applied config - provider: "
      .. log.inspect(config.provider)
      .. ", model: "
      .. log.inspect(config.model)
  )
end

---Check if a parameter key is a general parameter applicable to all providers
---@param key string
---@return boolean
function M.is_general_parameter(key)
  return is_general_parameter(key)
end

return M
