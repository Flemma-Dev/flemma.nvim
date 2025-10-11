--- Centralized validation functions for Flemma
local M = {}

local log = require("flemma.logging")
local provider_config = require("flemma.provider.config")
local providers_registry = require("flemma.provider.providers")

--- Validates that a provider name is supported
-- @param provider_name string The provider name to validate
-- @return boolean, string|nil true if valid, or false with error message
function M.validate_provider(provider_name)
  if not providers_registry.has(provider_name) then
    local err = string.format(
      "Flemma: Unknown provider '%s'. Supported providers are: %s",
      tostring(provider_name),
      table.concat(providers_registry.supported_providers(), ", ")
    )
    return false, err
  end
  return true, nil
end

--- Validates and returns the appropriate model for a provider
-- @param model_name string|nil The model name (can be nil for default)
-- @param provider_name string The provider name
-- @return string|nil, string|nil The validated model name, or nil with error message
function M.validate_and_get_model(model_name, provider_name)
  local original_model = model_name
  local validated_model = provider_config.get_appropriate_model(original_model, provider_name)

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

--- Validates provider-specific parameters and shows warnings for known issues
-- @param provider_name string The provider name
-- @param model_name string The model name
-- @param parameters table The parameters to validate
-- @return boolean true if validation passes (warnings don't fail validation)
function M.validate_parameters(provider_name, model_name, parameters)
  -- Get the provider module path
  local provider_module_path = providers_registry.get(provider_name)
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

return M
