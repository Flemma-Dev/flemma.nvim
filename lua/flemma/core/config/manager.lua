--- Centralized configuration management for Flemma
--- Includes validation logic (merged from core/validation.lua)
---@class flemma.core.ConfigManager
local M = {}

local config_facade = require("flemma.config")
local nav = require("flemma.config.schema.navigation")
local log = require("flemma.logging")
local registry = require("flemma.provider.registry")
local schema_definition = require("flemma.config.schema.definition")

local FALLBACK_MAX_TOKENS = 4000
local MIN_MAX_TOKENS = 1024

--- The parameters schema node, used to distinguish static (general) fields
--- from DISCOVER-resolved (provider-specific) fields.
---@type flemma.config.schema.Node
local parameters_schema = nav.unwrap_optional(schema_definition):get_child_schema("parameters") --[[@as flemma.config.schema.Node]]

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

    log.debug(
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
-- max_tokens resolution
--------------------------------------------------------------------------------

---Resolve percentage-based or over-limit max_tokens to an integer.
---Mutates parameters.max_tokens in place.
---@param provider_name string
---@param model_name string
---@param parameters table<string, any>
function M.resolve_max_tokens(provider_name, model_name, parameters)
  local value = parameters.max_tokens
  if value == nil then
    return
  end

  if type(value) == "string" then
    local pct_str = value:match("^(%d+)%%$")
    if pct_str then
      local pct = tonumber(pct_str)
      local model_info = registry.get_model_info(provider_name, model_name)
      if model_info and model_info.max_output_tokens then
        local resolved = math.floor(model_info.max_output_tokens * pct / 100)
        parameters.max_tokens = math.max(resolved, MIN_MAX_TOKENS)
        log.debug(
          "resolve_max_tokens(): "
            .. value
            .. " of "
            .. tostring(model_info.max_output_tokens)
            .. " → "
            .. tostring(parameters.max_tokens)
        )
      else
        parameters.max_tokens = FALLBACK_MAX_TOKENS
        log.debug(
          "resolve_max_tokens(): No model data for "
            .. provider_name
            .. "/"
            .. model_name
            .. ", falling back to "
            .. tostring(FALLBACK_MAX_TOKENS)
        )
      end
    else
      parameters.max_tokens = FALLBACK_MAX_TOKENS
      log.warn(
        "resolve_max_tokens(): Invalid max_tokens string '"
          .. value
          .. "', falling back to "
          .. tostring(FALLBACK_MAX_TOKENS)
      )
    end
    return
  end

  if type(value) == "number" then
    local model_info = registry.get_model_info(provider_name, model_name)
    if model_info and model_info.max_output_tokens and value > model_info.max_output_tokens then
      vim.notify(
        string.format(
          "Flemma: max_tokens %d exceeds %s limit (%d), clamping.",
          value,
          model_name,
          model_info.max_output_tokens
        ),
        vim.log.levels.WARN
      )
      parameters.max_tokens = model_info.max_output_tokens
    end
  end
end

--------------------------------------------------------------------------------
-- Configuration management
--------------------------------------------------------------------------------

---Flatten provider parameters from a materialized config into a single table.
---Copies general parameters from `config.parameters`, overlays provider-specific
---parameters from `config.parameters[provider_name]`, and adds `model`.
---This replaces merge_parameters — the facade's layer resolution handles merging;
---this function only flattens the namespaced schema structure for provider.new().
---@param provider_name string Resolved provider name
---@param config table Materialized config from config_facade.materialize()
---@return table<string, any> flat Flattened parameter table for provider.new()
function M.flatten_provider_params(provider_name, config)
  local flat = {}
  local params = config.parameters or {}
  -- Copy general parameters (non-table scalar values)
  for k, v in pairs(params) do
    if type(v) ~= "table" then
      flat[k] = v
    end
  end
  -- Overlay provider-specific parameters (highest specificity wins)
  local specific = params[provider_name]
  if type(specific) == "table" then
    for k, v in pairs(specific) do
      flat[k] = v
    end
  end
  flat.model = config.model
  return flat
end

---Validate provider and model, write explicit parameters to the facade,
---and return a provider-ready configuration with flattened parameters.
---
---Parameters are written to the facade at the correct namespaced paths:
---general params (max_tokens, thinking, etc.) go to `parameters.<key>`,
---provider-specific params go to `parameters.<provider>.<key>`.
---@param provider_name string
---@param model_name? string
---@param explicit_params? table<string, any> Only the user's explicit overrides
---@param layer? integer Facade layer to write to (default: RUNTIME)
---@return { provider: string, model: string, parameters: table<string, any> }|nil config, string|nil err
function M.prepare_config(provider_name, model_name, explicit_params, layer)
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

  -- Write to the facade: provider, model, and explicit parameters
  M.apply_config(resolved_provider, validated_model, explicit_params, layer)

  -- Read back from the materialized facade state and flatten for provider.new()
  local resolved_config = config_facade.materialize()
  local flat_params = M.flatten_provider_params(resolved_provider, resolved_config)

  -- Resolve percentage-based or over-limit max_tokens before validation
  M.resolve_max_tokens(resolved_provider, validated_model, flat_params)

  -- Validate parameters (shows warnings but doesn't fail)
  M.validate_parameters(resolved_provider, validated_model, flat_params)

  -- Log the final configuration
  log.debug(
    "prepare_config(): Prepared config for provider "
      .. log.inspect(resolved_provider)
      .. " with model "
      .. log.inspect(validated_model)
      .. " and parameters: "
      .. log.inspect(flat_params)
  )

  return {
    provider = resolved_provider,
    model = validated_model,
    parameters = flat_params,
  }, nil
end

---Write provider, model, and explicit parameters to the facade layer.
---General parameters are written to `parameters.<key>`, provider-specific
---parameters to `parameters.<provider>.<key>`. Re-materializes the full
---config into state for legacy consumers.
---@param provider_name string Resolved provider name
---@param model_name? string Validated model name
---@param explicit_params? table<string, any> User's explicit parameter overrides
---@param layer? integer Facade layer to write to (default: RUNTIME)
function M.apply_config(provider_name, model_name, explicit_params, layer)
  layer = layer or config_facade.LAYERS.RUNTIME
  local w = config_facade.writer(nil, layer)
  w.provider = provider_name
  if model_name then
    w.model = model_name
  end

  -- Write each explicit parameter to the correct namespaced path.
  -- Static fields on the parameters schema (max_tokens, thinking, etc.) are
  -- general params; everything else is provider-specific via DISCOVER.
  if explicit_params then
    for k, v in pairs(explicit_params) do
      if k ~= "model" then
        if parameters_schema:has_field(k) then
          w.parameters[k] = v
        else
          w.parameters[provider_name][k] = v
        end
      end
    end
  end

  log.debug(
    "apply_config(): Applied config - provider: "
      .. log.inspect(provider_name)
      .. ", model: "
      .. log.inspect(model_name)
      .. " (layer: "
      .. tostring(layer)
      .. ")"
  )
end

---Check if a parameter key is a general parameter applicable to all providers.
---A key is "general" if it is a static field on the parameters schema object
---(as opposed to a provider-specific sub-object resolved via DISCOVER).
---@param key string
---@return boolean
function M.is_general_parameter(key)
  return parameters_schema:has_field(key)
end

return M
