--- Unified preset registry for Flemma.
--- Presets are named ($-prefixed) value holders that can carry provider, model,
--- parameters, and auto_approve fields. Call sites determine which fields to
--- extract and which config layer to write to.
---@class flemma.Presets
local M = {}

local bridge = require("flemma.bridge")
local log = require("flemma.logging")
local messages = require("flemma.messages")
local modeline = require("flemma.utilities.modeline")
local nav = require("flemma.schema.navigation")
local notify = require("flemma.notify")
local registry = require("flemma.provider.registry")
local schema_definition = require("flemma.config.schema")
local string_utils = require("flemma.utilities.string")
local tools_registry = require("flemma.tools.registry")

--- The general parameters schema (static fields like max_tokens, temperature)
--- distinguishes general from provider-specific keys — same derivation as
--- core.lua's routing.
---@type flemma.schema.Node
local parameters_schema = nav.unwrap_optional(schema_definition):get_child_schema("parameters") --[[@as flemma.schema.Node]]

---@class flemma.presets.Preset
---@field provider? string Resolved provider name
---@field model? string Model name (nil = use provider default)
---@field parameters table<string, any> Provider parameters
---@field auto_approve? string[] Tool names/ops for auto-approval
---@field tools? string[] Tool names/ops for the tools list

---@type table<string, flemma.presets.Preset>
local BUILTIN = {
  ["$standard"] = {
    parameters = {},
    auto_approve = { "read", "write", "edit", "find", "grep", "ls", "flemma.*" },
  },
  ["$readonly"] = { parameters = {}, auto_approve = { "read", "find", "grep", "ls" } },
}

---@type table<string, flemma.presets.Preset>
local normalized_presets = {}

---@param message string
local function warn(message)
  log.warn("presets: " .. message)
  notify.warn(message)
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
    return nil, messages["ui.preset.invalid_type"]{ preset = name, received = definition_type }
  end

  -- Extract auto_approve and tools before extract_switch_arguments consumes
  -- the table, since they're not provider/model/parameter fields.
  local auto_approve = nil
  if definition_type == "table" and type(definition.auto_approve) == "table" then
    auto_approve = definition.auto_approve
    definition.auto_approve = nil
  elseif definition_type == "table" and definition.auto_approve ~= nil then
    return nil, messages["ui.preset.invalid_auto_approve"]{ preset = name, received = type(definition.auto_approve) }
  end

  local tools = nil
  if definition_type == "table" and type(definition.tools) == "table" then
    tools = definition.tools
    definition.tools = nil
  elseif definition_type == "table" and definition.tools ~= nil then
    return nil, messages["ui.preset.invalid_tools"]{ preset = name, received = type(definition.tools) }
  end

  local extracted = registry.extract_switch_arguments(definition)
  local provider = extracted.provider
  local model = extracted.model

  -- Decompose provider/model and matrix (";key=value") parameters from the
  -- model value — the single point that covers both definition forms (a string
  -- definition's positional was split by extract, leaving matrix glued to the
  -- model; a table definition's model field arrives verbatim). Matrix
  -- parameters are preset-local by construction: they nest inside
  -- preset.parameters and only merge into config when the preset is used.
  ---@type table<string, any>|nil
  local matrix_parameters
  if type(model) == "string" then
    local decomposed = registry.decompose_model(model)
    if #decomposed.extras > 0 then
      warn(messages["ui.preset.ignored_matrix_segment"]{
        preset = name,
        segments = table.concat(decomposed.extras, ", "),
      })
    end
    model = decomposed.model
    if decomposed.provider and provider and decomposed.provider ~= provider then
      return nil,
        messages["ui.preset.model_provider_conflict"]{
          preset = name,
          provider_field = provider,
          provider_model = decomposed.provider,
        }
    end
    provider = provider or decomposed.provider
    if next(decomposed.parameters) then
      matrix_parameters = decomposed.parameters
    end
  end

  -- Provider is optional for approval-only presets (e.g. $standard, $readonly)
  if provider ~= nil and (type(provider) ~= "string" or provider == "") then
    return nil, messages["ui.preset.invalid_provider"]{ preset = name }
  end

  if model ~= nil and (type(model) ~= "string" or model == "") then
    return nil, messages["ui.preset.invalid_model"]{ preset = name }
  end

  -- String definitions require positional <provider> <model> (bare tokens, or
  -- the slash-consumed single-positional form) — key=value assignment syntax
  -- for provider/model is rejected here, same as before this relaxation.
  if definition_type == "string" then
    if not (provider and model) or extracted.has_explicit_provider or extracted.has_explicit_model then
      return nil, messages["ui.preset.invalid_string_format"]{ preset = name }
    end
    if #extracted.extra_positionals > 0 then
      return nil,
        messages["ui.preset.unexpected_positional"]{
          preset = name,
          args = table.concat(extracted.extra_positionals, ", "),
        }
    end
  elseif #extracted.extra_positionals > 0 then
    warn(messages["ui.preset.extra_positionals"]{
      preset = name,
      args = table.concat(extracted.extra_positionals, ", "),
    })
  end

  -- Fully normalize parameters: provider-specific keys nest under the
  -- provider namespace, so preset.parameters is isomorphic to
  -- config.parameters — one shape, no downstream provenance sniffing.
  -- Provider-less presets keep flat keys; they scope under the switch-target
  -- provider at use time.
  local parameters = {}
  for key, value in pairs(vim.deepcopy(extracted.parameters)) do
    if provider and not parameters_schema:has_field(key) and not registry.has(key) then
      parameters[provider] = parameters[provider] or {}
      parameters[provider][key] = value
    else
      parameters[key] = value
    end
  end
  if matrix_parameters then
    if provider then
      parameters[provider] = vim.tbl_deep_extend("force", parameters[provider] or {}, matrix_parameters)
    else
      warn(messages["ui.preset.model_params_no_provider"]{ preset = name, model = tostring(extracted.model) })
    end
  end

  return {
    provider = provider,
    model = model,
    parameters = parameters,
    auto_approve = auto_approve,
    tools = tools,
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
    elseif not name:sub(2, 2):match("[a-z]") then
      warn(messages["ui.preset.invalid_name"]{ preset = name })
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

---Post-registration validation. Validates tool names in auto_approve and tools
---fields against the tool registry. Strips op prefixes (+, ^, !) before lookup;
---skips $-prefixed entries (preset references, not tool names).
---Advisory warnings only — does not fail.
function M.finalize()
  for name, preset in pairs(normalized_presets) do
    local fields = {
      { list = preset.auto_approve, label = "auto_approve" },
      { list = preset.tools, label = "tools" },
    }
    for _, field in ipairs(fields) do
      if field.list then
        for _, entry in ipairs(field.list) do
          local tool_name = entry
          if type(entry) == "string" and #entry > 1 then
            local prefix = entry:sub(1, 1)
            if prefix == "+" or prefix == "^" or prefix == "!" then
              tool_name = entry:sub(2)
            elseif prefix == "$" and entry:sub(2, 2):match("[a-z]") then
              goto continue
            end
          end
          if type(tool_name) == "string" and not tool_name:find("*", 1, true) and not tools_registry.has(tool_name) then
            warn(messages["ui.preset.unknown_tool"]{ preset = name, tool_name = tool_name, field = field.label })
          end
          ::continue::
        end
      end
    end
  end
end

---Route a preset's parameters to the correct config channel and return the
---flat overrides that still need the explicit (key=value) channel. This is the
---single point that decides where a preset's parameters go — both `setup` and
---`:Flemma switch` call it, so the rule lives in one place.
---
---A provider-bearing preset carries config-shaped parameters (normalize_definition
---nests provider-specific keys), so they assign structurally through `writer` —
---isomorphic to config.parameters — leaving nothing for the explicit channel. A
---provider-less preset carries flat parameters that must scope under whichever
---provider the switch resolves to, so they are returned for the explicit channel
---and nothing is written structurally. The return is always a fresh copy, safe
---for the caller to overlay command-line overrides onto.
---@param preset flemma.presets.Preset
---@param writer table Config write proxy for the target layer
---@return table<string, any> overrides Flat parameters for the explicit channel
function M.route_parameters(preset, writer)
  if not preset.parameters or next(preset.parameters) == nil then
    return {}
  end
  if not preset.provider then
    return vim.deepcopy(preset.parameters)
  end
  for key, value in pairs(preset.parameters) do
    writer.parameters[key] = value
  end
  return {}
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
    tools = preset.tools and vim.deepcopy(preset.tools) or nil,
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
    return nil, messages["ui.preset.not_found"]{ preset = model_field }
  end

  -- Conflict check: only when the user explicitly set a provider
  if explicit_provider ~= nil and preset.provider ~= nil then
    local resolved_user = registry.resolve(explicit_provider)
    local resolved_preset = registry.resolve(preset.provider)
    if resolved_user ~= resolved_preset then
      return nil,
        messages["ui.preset.provider_conflict"]{
          provider_explicit = explicit_provider,
          preset = model_field,
          provider_preset = preset.provider,
        }
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

---Find the closest matching preset name for typo suggestions.
---@param name string Preset name to match against
---@return string|nil closest The closest preset name, or nil if none is close enough
function M.closest_match(name)
  return string_utils.closest_match(name, normalized_presets)
end

---Clear all presets (for testing)
function M.clear()
  normalized_presets = {}
end

bridge.register("get_preset", M.get)
bridge.register("closest_match_preset", M.closest_match)

return M
