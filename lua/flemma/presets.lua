--- Unified preset registry for Flemma.
--- Presets are named ($-prefixed) value holders that can carry provider, model,
--- parameters, and auto_approve fields. Call sites determine which fields to
--- extract and which config layer to write to.
---@class flemma.Presets
local M = {}

local log = require("flemma.logging")
local modeline = require("flemma.utilities.modeline")
local registry = require("flemma.provider.registry")
local tools_registry = require("flemma.tools.registry")

---@class flemma.presets.Preset
---@field provider? string Resolved provider name
---@field model? string Model name (nil = use provider default)
---@field parameters table<string, any> Provider parameters
---@field auto_approve? string[] Concrete list of tool names to auto-approve

---@type table<string, flemma.presets.Preset>
local BUILTIN = {
  ["$standard"] = { parameters = {}, auto_approve = { "read", "write", "edit", "find", "grep", "ls" } },
  ["$readonly"] = { parameters = {}, auto_approve = { "read", "find", "grep", "ls" } },
}

---@type table<string, flemma.presets.Preset>
local normalized_presets = {}

---@param message string
local function warn(message)
  log.warn("presets: " .. message)
  vim.notify("Flemma: " .. message, vim.log.levels.WARN)
end

---Validate and normalize a single preset definition.
---String and positional-table formats only produce provider/model/parameters.
---The strict table format additionally supports auto_approve.
---@param name string Preset name (e.g. "$fast")
---@param definition string|table Raw preset definition from config
---@return flemma.presets.Preset|nil normalized, string|nil error
local function normalize_definition(name, definition)
  local definition_type = type(definition)

  if definition_type == "string" then
    definition = modeline.parse(definition)
  elseif definition_type == "table" then
    definition = vim.deepcopy(definition)
  else
    return nil, ("Preset '%s' must be a table or string, received %s"):format(name, definition_type)
  end

  -- Extract auto_approve before extract_switch_arguments consumes the table,
  -- since it's not a provider/model/parameter field.
  local auto_approve = nil
  if definition_type == "table" and type(definition.auto_approve) == "table" then
    auto_approve = definition.auto_approve
    definition.auto_approve = nil
  elseif definition_type == "table" and definition.auto_approve ~= nil then
    return nil, ("Preset '%s' auto_approve must be a string[], got %s"):format(name, type(definition.auto_approve))
  end

  local extracted = registry.extract_switch_arguments(definition)
  local provider = extracted.provider
  local model = extracted.model

  -- Provider is optional for approval-only presets (e.g. $standard, $readonly)
  if provider ~= nil and (type(provider) ~= "string" or provider == "") then
    return nil, ("Preset '%s' has an invalid provider field"):format(name)
  end

  if model ~= nil and (type(model) ~= "string" or model == "") then
    return nil, ("Preset '%s' has an invalid model field"):format(name)
  end

  -- String definitions require positional <provider> <model>
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
    auto_approve = auto_approve,
  },
    nil
end

---Initialize the preset registry with built-in presets, then normalize and
---register user presets on top. User presets override built-ins by name.
---@param user_presets table|any Raw presets table from user config
function M.setup(user_presets)
  normalized_presets = {}

  -- Register built-ins first
  for name, definition in pairs(BUILTIN) do
    normalized_presets[name] = vim.deepcopy(definition)
  end

  if type(user_presets) ~= "table" then
    return
  end

  -- Merge user presets on top (override by name)
  for raw_name, definition in pairs(user_presets) do
    local name = tostring(raw_name)

    if not vim.startswith(name, "$") then
      log.warn(("presets: preset '%s' ignored — keys must start with '$'"):format(name))
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

---Post-registration validation. Validates auto_approve entries against the
---tool registry. Advisory warnings only — does not fail.
function M.finalize()
  for name, preset in pairs(normalized_presets) do
    if preset.auto_approve then
      for _, tool_name in ipairs(preset.auto_approve) do
        if not tools_registry.has(tool_name) then
          warn(("Preset '%s' references unknown tool '%s' in auto_approve"):format(name, tool_name))
        end
      end
    end
  end
end

---Get a normalized preset by name (returns a deep copy)
---@param name string Preset name (e.g. "$fast")
---@return flemma.presets.Preset|nil
function M.get(name)
  local preset = normalized_presets[name]
  if not preset then
    return nil
  end
  return {
    provider = preset.provider,
    model = preset.model,
    parameters = vim.deepcopy(preset.parameters),
    auto_approve = preset.auto_approve and vim.deepcopy(preset.auto_approve) or nil,
  }
end

---Resolve a preset reference from the model field at startup.
---Returns the normalized preset if model is a "$name" reference, nil if not a
---preset reference, or nil + error when lookup or conflict check fails.
---@param model_field string|nil The config.model value to inspect
---@param explicit_provider string|nil User-supplied provider (nil when not explicitly set)
---@return flemma.presets.Preset|nil preset, string|nil error
function M.resolve_default(model_field, explicit_provider)
  if type(model_field) ~= "string" or not vim.startswith(model_field, "$") then
    return nil, nil
  end

  local preset = M.get(model_field)
  if not preset then
    return nil, "Flemma: Default preset '" .. model_field .. "' not found. Provider not initialized."
  end

  -- Conflict check: only when the user explicitly set a provider
  if explicit_provider ~= nil and preset.provider ~= nil then
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

---Clear all presets (for testing)
function M.clear()
  normalized_presets = {}
end

return M
