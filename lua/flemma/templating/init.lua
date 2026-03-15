--- Templating registry for Flemma.
--- Manages populators that build the Lua environment available to {{ }} and {% %} blocks.
--- Each populator is a function(env) mutator that can add, override, or remove globals.
---@class flemma.Templating
local M = {}

local loader = require("flemma.loader")
local state = require("flemma.state")

---@class flemma.templating.Populator
---@field name string Unique identifier for this populator
---@field priority integer Execution order (lower runs first, default 500)
---@field populate fun(env: table) Mutator that receives the env table

local BUILTIN_POPULATORS = {
  "flemma.templating.builtins.stdlib",
  "flemma.templating.builtins.iterators",
}

---@type flemma.templating.Populator[]
local populators = {}

---@type string[]
local pending_modules = {}

---@type table<string, boolean>
local loaded_modules = {}

---Load all pending modules. Called before create_env().
local function ensure_modules_loaded()
  if #pending_modules == 0 then
    return
  end
  local to_load = pending_modules
  pending_modules = {}
  for _, module_path in ipairs(to_load) do
    if not loaded_modules[module_path] then
      loaded_modules[module_path] = true
      local mod = require(module_path)
      M.register(mod.name, mod)
    end
  end
end

---Register a populator by name.
---Replaces any existing populator with the same name.
---@param name string Unique identifier
---@param populator { priority?: integer, populate: fun(env: table) }
function M.register(name, populator)
  for i, p in ipairs(populators) do
    if p.name == name then
      table.remove(populators, i)
      break
    end
  end
  table.insert(populators, {
    name = name,
    priority = populator.priority or 500,
    populate = populator.populate,
  })
end

---Register a module path for lazy loading.
---Validates that the module exists immediately; defers actual require() until create_env().
---@param module_path string Lua module path (e.g., "my.templating.custom")
function M.register_module(module_path)
  loader.assert_exists(module_path)
  if not loaded_modules[module_path] then
    table.insert(pending_modules, module_path)
  end
end

---Create a new template environment by running all populators in priority order.
---@return table env Fresh environment table
function M.create_env()
  ensure_modules_loaded()
  local sorted = {}
  for _, p in ipairs(populators) do
    table.insert(sorted, p)
  end
  table.sort(sorted, function(a, b)
    return a.priority < b.priority
  end)
  local env = {}
  for _, p in ipairs(sorted) do
    p.populate(env)
  end
  return env
end

---Setup: register built-in populators and user-configured modules.
function M.setup()
  for _, module_path in ipairs(BUILTIN_POPULATORS) do
    local mod = require(module_path)
    M.register(mod.name, mod)
  end
  local resolved_config = state.get_config()
  if resolved_config.templating and resolved_config.templating.modules then
    for _, module_path in ipairs(resolved_config.templating.modules) do
      M.register_module(module_path)
    end
  end
end

---Clear all registered populators and module tracking.
function M.clear()
  populators = {}
  pending_modules = {}
  loaded_modules = {}
end

return M
