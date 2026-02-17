--- Preset management for Flemma switch command
---@class flemma.Presets
local M = {}

local log = require("flemma.logging")
local modeline = require("flemma.modeline")
local registry = require("flemma.provider.registry")

---@class flemma.presets.NormalizedPreset
---@field provider string Resolved provider name
---@field model string|nil Model name (nil = use provider default)
---@field parameters table<string, any> Provider parameters

---@type table<string, flemma.presets.NormalizedPreset>
local normalized_presets = {}

---@param message string
local function warn(message)
  log.warn("presets: " .. message)
  vim.notify("Flemma: " .. message, vim.log.levels.WARN)
end

---Validate and normalize a single preset definition
---@param name string Preset name (e.g. "$fast")
---@param definition string|table Raw preset definition from config
---@return flemma.presets.NormalizedPreset|nil normalized, string|nil error
local function normalize_definition(name, definition)
  local definition_type = type(definition)

  if definition_type == "string" then
    definition = modeline.parse(definition)
  elseif definition_type == "table" then
    definition = vim.deepcopy(definition)
  else
    return nil, ("Preset '%s' must be a table or string, received %s"):format(name, definition_type)
  end

  local extracted = registry.extract_switch_arguments(definition)
  local provider = extracted.provider
  local model = extracted.model

  if type(provider) ~= "string" or provider == "" then
    return nil, ("Preset '%s' is missing a provider field"):format(name)
  end

  if model ~= nil and (type(model) ~= "string" or model == "") then
    return nil, ("Preset '%s' has an invalid model field"):format(name)
  end

  if definition_type == "string" then
    if not extracted.positionals[1] or not extracted.positionals[2] then
      return nil, ("Preset '%s' string definitions must start with '<provider> <model>'"):format(name)
    end
    if #extracted.extra_positionals > 0 then
      return nil,
        ("Preset '%s' contains unexpected positional argument: %s"):format(
          name,
          table.concat(extracted.extra_positionals, ", ")
        )
    end
  elseif #extracted.extra_positionals > 0 then
    warn(
      ("Preset '%s' ignores additional positional values (%s) beyond provider/model"):format(
        name,
        table.concat(extracted.extra_positionals, ", ")
      )
    )
  end

  local parameters = vim.deepcopy(extracted.parameters)

  return {
    provider = provider,
    model = model,
    parameters = parameters,
  }, nil
end

---Hydrate all presets from raw config into normalized form
---@param presets table|any Raw presets table from user config
function M.refresh(presets)
  normalized_presets = {}

  if type(presets) ~= "table" then
    return
  end

  for raw_name, definition in pairs(presets) do
    local name = tostring(raw_name)

    if not vim.startswith(name, "$") then
      warn(("Preset '%s' ignored because preset keys must start with '$'"):format(name))
    else
      local normalized, err = normalize_definition(name, definition)
      if not normalized then
        warn(err --[[@as string]])
      else
        normalized_presets[name] = normalized
      end
    end
  end
end

---Get a normalized preset by name (returns a deep copy)
---@param name string Preset name (e.g. "$fast")
---@return flemma.presets.NormalizedPreset|nil
function M.get(name)
  local preset = normalized_presets[name]
  if not preset then
    return nil
  end
  return {
    provider = preset.provider,
    model = preset.model,
    parameters = vim.deepcopy(preset.parameters),
  }
end

---Resolve a preset reference from the model field at startup.
---Returns the normalized preset if model is a "$name" reference, nil if not a
---preset reference, or nil + error when lookup or conflict check fails.
---@param model_field string|nil The config.model value to inspect
---@param explicit_provider string|nil User-supplied provider (nil when not explicitly set)
---@return flemma.presets.NormalizedPreset|nil preset, string|nil error
function M.resolve_default(model_field, explicit_provider)
  if type(model_field) ~= "string" or not vim.startswith(model_field, "$") then
    return nil, nil
  end

  local preset = M.get(model_field)
  if not preset then
    return nil, "Flemma: Default preset '" .. model_field .. "' not found. Provider not initialized."
  end

  -- Conflict check: only when the user explicitly set a provider
  if explicit_provider ~= nil then
    local resolved_user = registry.resolve(explicit_provider)
    local resolved_preset = registry.resolve(preset.provider)
    if resolved_user ~= resolved_preset then
      return nil,
        "Flemma: Explicit provider '"
          .. explicit_provider
          .. "' conflicts with preset '"
          .. model_field
          .. "' (provider: '"
          .. preset.provider
          .. "'). Provider not initialized."
    end
  end

  return preset, nil
end

---List all registered preset names, sorted alphabetically
---@return string[]
function M.list()
  local keys = {}
  for name, _ in pairs(normalized_presets) do
    table.insert(keys, name)
  end
  table.sort(keys)
  return keys
end

return M
