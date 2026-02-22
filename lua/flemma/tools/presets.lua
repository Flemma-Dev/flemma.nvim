--- Tool approval preset registry
--- Manages named approval presets (static approve/deny tool lists) that can be
--- referenced by $name in auto_approve configuration. Ships built-in presets;
--- users can override or add their own.
---@class flemma.tools.Presets
local M = {}

local log = require("flemma.logging")

---@class flemma.tools.PresetDefinition
---@field approve? string[] Tool names to auto-approve
---@field deny? string[] Tool names to deny (overrides approve from other presets)

---@type table<string, flemma.tools.PresetDefinition>
local BUILTIN = {
  ["$readonly"] = { approve = { "read" } },
  ["$default"] = { approve = { "read", "write", "edit" } },
}

---@type table<string, flemma.tools.PresetDefinition>
local registry = {}

---@param message string
local function warn(message)
  log.warn("presets: " .. message)
  vim.notify("Flemma: " .. message, vim.log.levels.WARN)
end

---Validate a single preset definition
---@param name string
---@param definition table
---@return boolean valid
local function validate(name, definition)
  if not vim.startswith(name, "$") then
    warn(("Preset '%s' ignored — preset keys must start with '$'"):format(name))
    return false
  end
  if type(definition) ~= "table" then
    warn(("Preset '%s' ignored — expected table, got %s"):format(name, type(definition)))
    return false
  end
  if definition.approve ~= nil and type(definition.approve) ~= "table" then
    warn(("Preset '%s' ignored — 'approve' must be a string[], got %s"):format(name, type(definition.approve)))
    return false
  end
  if definition.deny ~= nil and type(definition.deny) ~= "table" then
    warn(("Preset '%s' ignored — 'deny' must be a string[], got %s"):format(name, type(definition.deny)))
    return false
  end
  return true
end

---Initialize the registry with built-in presets, then merge user presets on top.
---User presets override built-ins by name.
---@param user_presets? table<string, table> Raw presets from config.tools.presets
function M.setup(user_presets)
  registry = {}
  -- Register built-ins first
  for name, definition in pairs(BUILTIN) do
    registry[name] = vim.deepcopy(definition)
  end
  -- Merge user presets on top (override by name)
  if type(user_presets) == "table" then
    for name, definition in pairs(user_presets) do
      if validate(name, definition) then
        registry[name] = vim.deepcopy(definition)
      end
    end
  end
end

---Get a preset by name (returns a deep copy)
---@param name string Preset name (e.g. "$default")
---@return flemma.tools.PresetDefinition|nil
function M.get(name)
  local preset = registry[name]
  if not preset then
    return nil
  end
  return vim.deepcopy(preset)
end

---Get all registered presets (returns a deep copy)
---@return table<string, flemma.tools.PresetDefinition>
function M.get_all()
  return vim.deepcopy(registry)
end

---Get sorted list of all preset names
---@return string[]
function M.names()
  local result = {}
  for name in pairs(registry) do
    table.insert(result, name)
  end
  table.sort(result)
  return result
end

---Clear all presets (for testing)
function M.clear()
  registry = {}
end

return M
