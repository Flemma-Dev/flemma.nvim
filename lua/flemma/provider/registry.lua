--- Provider registry for Flemma
--- Manages provider modules, capabilities, and model configuration

---@class flemma.provider.Registry
---@field defaults table<string, string>
---@field models table<string, string[]>
local M = {}

local config_facade = require("flemma.config")
local loader = require("flemma.loader")
local registry_utils = require("flemma.utilities.registry")

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
---@field config_schema? flemma.schema.ObjectNode Provider-specific config schema for DISCOVER resolution

---@class flemma.provider.Metadata
---@field name string Provider identifier (e.g., "anthropic")
---@field display_name string Human-readable name
---@field capabilities flemma.provider.Capabilities
---@field config_schema? flemma.schema.ObjectNode Provider-specific config schema for DISCOVER resolution
---@field models? string[] Module paths for model data (loaded via flemma.loader)

---@class flemma.provider.RegistrationEntry
---@field module string Lua module path
---@field capabilities flemma.provider.Capabilities
---@field display_name string
---@field config_schema? flemma.schema.ObjectNode Provider-specific config schema
---@field default_model? string Default model name
---@field models? table<string, flemma.models.ModelInfo> Model definitions with pricing

---@type table<string, flemma.provider.ProviderEntry>
local providers = {}

---@type table<string, flemma.models.ProviderModels>
local model_store = {}

-- Built-in provider module paths (each module exports M.metadata)
local BUILTIN_PROVIDER_MODULES = {
  "flemma.provider.providers.openai",
  "flemma.provider.providers.anthropic",
  "flemma.provider.providers.vertex",
  "flemma.provider.providers.moonshot",
}

--------------------------------------------------------------------------------
-- Model loading
--------------------------------------------------------------------------------

---@param provider_name string
---@return string[]
local function get_provider_model_names(provider_name)
  local provider = model_store[provider_name]
  if not provider then
    return {}
  end

  local names = {}
  for model_name, _ in pairs(provider.models) do
    names[#names + 1] = model_name
  end

  return names
end

---Load model data into the internal model store for a provider.
---By default, merges per-model entries. With `opts.replace`, replaces the entire table.
---@param provider_name string
---@param model_data flemma.models.ProviderModels
---@param opts? { replace: boolean }
function M.load_models(provider_name, model_data, opts)
  if opts and opts.replace then
    model_store[provider_name] = model_data
  else
    if not model_store[provider_name] then
      model_store[provider_name] = { default = model_data.default, models = {} }
    end
    if model_data.default then
      model_store[provider_name].default = model_data.default
    end
    for model_name, model_info in pairs(model_data.models) do
      model_store[provider_name].models[model_name] = model_info
    end
  end

  -- Refresh cached lookups
  M.defaults[provider_name] = model_store[provider_name] and model_store[provider_name].default or nil
  M.models[provider_name] = get_provider_model_names(provider_name)
end

---Register model data for a provider from a module path.
---@param provider_name string
---@param module_path string Module path loadable via flemma.loader
---@param opts? { replace: boolean }
function M.register_models(provider_name, module_path, opts)
  local model_data = loader.load(module_path)
  M.load_models(provider_name, model_data, opts)
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

  ---@type string[]|nil
  local model_modules

  if entry then
    -- Two-arg form: register("name", entry)
    name = source
    registry_utils.validate_name(name, "provider")
    definition = entry
  else
    -- Single-arg form: register("module.path") — load module and read metadata
    local mod = loader.load(source)
    if not mod.metadata then
      error("Provider module " .. source .. " does not export metadata", 2)
    end
    name = mod.metadata.name
    model_modules = mod.metadata.models
    definition = {
      module = source,
      capabilities = mod.metadata.capabilities,
      display_name = mod.metadata.display_name,
      config_schema = mod.metadata.config_schema,
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
    config_schema = definition.config_schema,
  }

  -- Load model modules declared in provider metadata
  if model_modules then
    for _, module_path in ipairs(model_modules) do
      local model_data = loader.load(module_path)
      M.load_models(name, model_data)
    end
  end

  -- If models or default_model provided inline (two-arg form), merge them
  if definition.default_model or definition.models then
    M.load_models(name, {
      default = definition.default_model or (model_store[name] and model_store[name].default or ""),
      models = definition.models or {},
    })
  end

  -- Materialize config_schema defaults into the DEFAULTS layer
  if definition.config_schema then
    config_facade.register_module_defaults("parameters", name, definition.config_schema)
  end
end

---Initialize built-in providers (called during setup)
function M.setup()
  for _, module_path in ipairs(BUILTIN_PROVIDER_MODULES) do
    local mod = loader.load(module_path)
    if mod.metadata and not providers[mod.metadata.name] then
      M.register(module_path)
    end
  end
end

---Unregister a provider by name
---@param name string The provider identifier
---@return boolean removed True if a provider was found and removed
function M.unregister(name)
  if not providers[name] then
    return false
  end
  providers[name] = nil
  model_store[name] = nil
  M.defaults[name] = nil
  M.models[name] = nil
  return true
end

---Clear all registered providers (for test isolation)
function M.clear()
  providers = {}
  model_store = {}
  M.defaults = {}
  M.models = {}
end

---Get all registered provider entries
---@return table<string, flemma.provider.ProviderEntry>
function M.get_all()
  return vim.deepcopy(providers)
end

---Get the count of registered providers
---@return integer
function M.count()
  local n = 0
  for _ in pairs(providers) do
    n = n + 1
  end
  return n
end

--------------------------------------------------------------------------------
-- Provider queries
--------------------------------------------------------------------------------

---Resolve a provider name
---@param provider_name string The provider identifier
---@return string resolved_name The resolved provider name
function M.resolve(provider_name)
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

---Get provider config schema for DISCOVER resolution
---@param provider_name string The provider identifier
---@return flemma.schema.ObjectNode|nil config_schema Provider config schema, or nil if not found
function M.get_config_schema(provider_name)
  local resolved = M.resolve(provider_name)
  local provider = providers[resolved]
  return provider and provider.config_schema or nil
end

--------------------------------------------------------------------------------
-- Model configuration
--------------------------------------------------------------------------------

M.defaults = {}
M.models = {}

---@param provider_name string
---@return string|nil
function M.get_model(provider_name)
  local provider = model_store[provider_name]
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

  -- Check if the provider exists in model_store
  local provider = model_store[provider_name]
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

---Look up model information (pricing, token limits) for a provider+model pair
---@param provider_name string
---@param model_name string
---@return flemma.models.ModelInfo|nil
function M.get_model_info(provider_name, model_name)
  local provider_data = model_store[provider_name]
  if not provider_data or not provider_data.models then
    return nil
  end
  return provider_data.models[model_name]
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
---@param parsed flemma.utilities.modeline.ParsedTokens Parsed tokens from modeline.parse/modeline.parse_args
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
