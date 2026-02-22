--- Provider registry for Flemma
--- Manages provider modules, capabilities, and model configuration

---@class flemma.provider.Registry
---@field defaults table<string, string>
---@field models table<string, string[]>
local M = {}

-- Load models from centralized models.lua
local models_data = require("flemma.models")

--------------------------------------------------------------------------------
-- Provider registry
--------------------------------------------------------------------------------

---@class flemma.provider.Capabilities
---@field supports_reasoning boolean
---@field supports_thinking_budget boolean
---@field outputs_thinking boolean
---@field output_has_thoughts boolean Whether output_tokens already includes thinking tokens for cost calculation
---@field min_thinking_budget? integer Minimum thinking budget value for this provider

---@class flemma.provider.ProviderEntry
---@field module string
---@field capabilities flemma.provider.Capabilities
---@field display_name string
---@field default_parameters? table<string, any>

---@class flemma.provider.Metadata
---@field name string Provider identifier (e.g., "anthropic")
---@field display_name string Human-readable name
---@field capabilities flemma.provider.Capabilities
---@field default_parameters? table<string, any> Provider-specific param defaults

---@class flemma.provider.RegistrationEntry
---@field module string Lua module path
---@field capabilities flemma.provider.Capabilities
---@field display_name string
---@field default_parameters? table<string, any> Provider-specific param defaults
---@field default_model? string Default model name
---@field models? table<string, flemma.models.ModelInfo> Model definitions with pricing
---@field cache_read_multiplier? number
---@field cache_write_multipliers? table<string, number>

---@type table<string, boolean>
local deprecated_warning_shown = {}

-- Deprecated provider aliases (old_name -> new_name)
local PROVIDER_ALIASES = {
  claude = "anthropic",
}

---@type table<string, flemma.provider.ProviderEntry>
local providers = {}

-- Built-in provider module paths (each module exports M.metadata)
local BUILTIN_PROVIDER_MODULES = {
  "flemma.provider.providers.openai",
  "flemma.provider.providers.anthropic",
  "flemma.provider.providers.vertex",
}

--------------------------------------------------------------------------------
-- Model helpers (must be defined before register())
--------------------------------------------------------------------------------

---@param provider_name string
---@return string[]
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

--------------------------------------------------------------------------------
-- Setup and definition
--------------------------------------------------------------------------------

---Register a provider.
---Dispatches on arguments:
---  register("module.path")      — load module, read .metadata, register
---  register("name", entry)      — direct definition with entry table
---@param source string Module path (single arg) or provider name (with entry)
---@param entry? flemma.provider.RegistrationEntry Registration entry (when source is a name)
function M.register(source, entry)
  local name, definition

  if entry then
    -- Two-arg form: register("name", entry)
    name = source
    local loader = require("flemma.loader")
    if loader.is_module_path(name) then
      error(string.format("flemma: provider name '%s' must not contain dots (dots indicate module paths)", name), 2)
    end
    definition = entry
  else
    -- Single-arg form: register("module.path") — load module and read metadata
    local mod = require(source)
    if not mod.metadata then
      error("Provider module " .. source .. " does not export metadata", 2)
    end
    name = mod.metadata.name
    definition = {
      module = source,
      capabilities = mod.metadata.capabilities,
      display_name = mod.metadata.display_name,
      default_parameters = mod.metadata.default_parameters,
    }
  end

  local capabilities = vim.tbl_extend("keep", definition.capabilities or {}, {
    supports_reasoning = false,
    supports_thinking_budget = false,
    outputs_thinking = false,
    output_has_thoughts = false,
  })

  providers[name] = {
    module = definition.module,
    capabilities = capabilities,
    display_name = definition.display_name,
    default_parameters = definition.default_parameters,
  }

  -- If models or default_model provided, update models_data
  if definition.default_model or definition.models then
    if not models_data.providers[name] then
      models_data.providers[name] = {
        default = definition.default_model or "",
        models = definition.models or {},
      }
    else
      if definition.default_model then
        models_data.providers[name].default = definition.default_model
      end
      if definition.models then
        for model_name, model_info in pairs(definition.models) do
          models_data.providers[name].models[model_name] = model_info
        end
      end
    end
    if definition.cache_read_multiplier then
      models_data.providers[name].cache_read_multiplier = definition.cache_read_multiplier
    end
    if definition.cache_write_multipliers then
      models_data.providers[name].cache_write_multipliers = definition.cache_write_multipliers
    end
  end

  -- Refresh defaults and models for this provider
  M.defaults[name] = models_data.providers[name] and models_data.providers[name].default or nil
  M.models[name] = get_provider_models(name)
end

---Initialize built-in providers (called during setup)
function M.setup()
  for _, module_path in ipairs(BUILTIN_PROVIDER_MODULES) do
    local mod = require(module_path)
    if mod.metadata and not providers[mod.metadata.name] then
      M.register(module_path)
    end
  end
end

---Clear all registered providers (for test isolation)
function M.clear()
  providers = {}
  M.defaults = {}
  M.models = {}
end

--------------------------------------------------------------------------------
-- Provider queries
--------------------------------------------------------------------------------

---Resolve a provider name, handling deprecated aliases
---Shows a deprecation warning once per session for deprecated names
---@param provider_name string The provider identifier (may be an alias)
---@return string resolved_name The resolved provider name
function M.resolve(provider_name)
  local alias_target = PROVIDER_ALIASES[provider_name]
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
---@return flemma.provider.Capabilities|nil capabilities Provider capabilities table, or nil if not found
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

---Get provider default parameters
---@param provider_name string The provider identifier
---@return table<string, any>|nil default_parameters Provider default parameters, or nil if not found
function M.get_default_parameters(provider_name)
  local resolved = M.resolve(provider_name)
  local provider = providers[resolved]
  return provider and provider.default_parameters or nil
end

--------------------------------------------------------------------------------
-- Model configuration
--------------------------------------------------------------------------------

-- Legacy compatibility - expose defaults and models from models.lua
M.defaults = {}
M.models = {}

---@param provider_name string
---@return string|nil
function M.get_model(provider_name)
  local provider = models_data.providers[provider_name]
  return provider and provider.default or nil
end

---@param model_name string|nil
---@param provider_name string
---@return boolean
function M.is_provider_model(model_name, provider_name)
  -- If model_name is nil, it can't belong to any provider
  if model_name == nil then
    return false
  end

  -- Check if the provider exists in models_data
  local provider = models_data.providers[provider_name]
  if not provider or not provider.models or vim.tbl_isempty(provider.models) then
    -- Custom provider with no model list: accept any model string
    return providers[provider_name] ~= nil
  end

  -- Check if the model_name exists in the models for that provider
  return provider.models[model_name] ~= nil
end

---@param model_name string|nil
---@param provider_name string
---@return string|nil
function M.get_appropriate_model(model_name, provider_name)
  -- If the model is appropriate for the provider, use it
  if M.is_provider_model(model_name, provider_name) then
    return model_name --[[@as string]]
  end

  -- Otherwise, return the default model for the provider
  return M.get_model(provider_name)
end

---@class flemma.provider.SwitchArgs
---@field provider string|nil
---@field model string|nil
---@field parameters table<string, any>
---@field positionals string[]
---@field extra_positionals string[]
---@field has_explicit_provider boolean
---@field has_explicit_model boolean

--- Extract provider/model parameters from parsed modeline tokens
---@param parsed flemma.modeline.ParsedTokens Parsed tokens from modeline.parse/modeline.parse_args
---@return flemma.provider.SwitchArgs
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
