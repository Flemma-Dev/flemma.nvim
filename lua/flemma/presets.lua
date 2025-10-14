--- Preset management for Flemma switch command
local M = {}

local log = require("flemma.logging")
local modeline = require("flemma.modeline")
local provider_config = require("flemma.provider.config")

local normalized_presets = {}

local function warn(message)
  log.warn("presets: " .. message)
  vim.notify("Flemma: " .. message, vim.log.levels.WARN)
end

local function normalize_definition(name, definition)
  local provider
  local model
  local definition_type = type(definition)

  if definition_type == "string" then
    definition = modeline.parse(definition)
  elseif definition_type == "table" then
    definition = vim.deepcopy(definition)
  else
    return nil, ("Preset '%s' must be a table or string, received %s"):format(name, definition_type)
  end

  local extracted = provider_config.extract_switch_arguments(definition)
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
        warn(err)
      else
        normalized_presets[name] = normalized
      end
    end
  end
end

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

function M.list()
  local keys = {}
  for name, _ in pairs(normalized_presets) do
    table.insert(keys, name)
  end
  table.sort(keys)
  return keys
end

return M
