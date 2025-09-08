--- Centralized validation functions for Flemma
local M = {}

local log = require("flemma.logging")
local provider_config = require("flemma.provider.config")
local models = require("flemma.models")

--- Validates that a provider name is supported
-- @param provider_name string The provider name to validate
-- @return boolean, string|nil true if valid, or false with error message
function M.validate_provider(provider_name)
  if provider_name ~= "openai" and provider_name ~= "vertex" and provider_name ~= "claude" then
    local err = string.format(
      "Flemma: Unknown provider '%s'. Supported providers are: %s",
      tostring(provider_name),
      table.concat({ "claude", "openai", "vertex" }, ", ")
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
  -- OpenAI-specific validations
  if provider_name == "openai" then
    -- Check for reasoning parameter support
    local reasoning_value = parameters.reasoning
    if reasoning_value ~= nil and reasoning_value ~= "" then
      local model_info = models.providers.openai
        and models.providers.openai.models
        and models.providers.openai.models[model_name]
      local supports_reasoning_effort = model_info and model_info.supports_reasoning_effort == true

      if not supports_reasoning_effort then
        local warning_msg = string.format(
          "Flemma: The 'reasoning' parameter is not supported by the selected OpenAI model '%s'. It may be ignored or cause an API error.",
          model_name
        )
        vim.notify(warning_msg, vim.log.levels.WARN, { title = "Flemma Configuration" })
        log.warn(warning_msg)
      end
    end

    -- Check for temperature <> 1.0 with OpenAI o-series models when reasoning is active
    local temp_value = parameters.temperature
    local model_info = models.providers.openai
      and models.providers.openai.models
      and models.providers.openai.models[model_name]
    local supports_reasoning_effort = model_info and model_info.supports_reasoning_effort == true

    if
      reasoning_value ~= nil
      and reasoning_value ~= ""
      and supports_reasoning_effort
      and string.sub(model_name, 1, 1) == "o"
      and temp_value ~= nil
      and temp_value ~= 1
      and temp_value ~= 1.0
    then
      local temp_warning_msg = string.format(
        "Flemma: For OpenAI o-series models with 'reasoning' active, 'temperature' must be 1 or omitted. Current value is '%s'. The API will likely reject this.",
        tostring(temp_value)
      )
      vim.notify(temp_warning_msg, vim.log.levels.WARN, { title = "Flemma Configuration" })
      log.warn(temp_warning_msg)
    end
  end

  return true
end

return M
