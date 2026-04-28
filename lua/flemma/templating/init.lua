--- Templating registry for Flemma.
--- Manages populators that build the Lua environment available to {{ }} and {% %} blocks.
--- Each populator is a function(env) mutator that can add, override, or remove globals.
---@class flemma.Templating
local M = {}

local config_facade = require("flemma.config")
local loader = require("flemma.loader")
local symbols = require("flemma.symbols")

---@class flemma.templating.Populator
---@field name string Unique identifier for this populator
---@field priority integer Execution order (lower runs first, default 500)
---@field populate fun(env: table) Mutator that receives the env table

local BUILTIN_POPULATORS = {
  "flemma.templating.builtins.stdlib",
  "flemma.templating.builtins.format",
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
      local mod = loader.load(module_path)
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

--- Framework-internal keys that may be read before being explicitly set on a
--- given env instance. Pre-registering them in known_keys prevents false
--- positives from the strict __index while still catching user-variable typos
--- (including underscore-prefixed names like __name__).
---@type string[]
local FRAMEWORK_KEYS = {
  -- set by templating.from_context()
  "__filename",
  "__dirname",
  -- set/cleared by compiler.execute()
  "__emit",
  "__emit_expr",
  "__emit_part",
  "__emit_expr_error",
  "__segments",
  "__capture_start",
  "__capture_end",
  -- optional: set by callers that need output transformation (e.g., lualine % escaping)
  "__expr_transform",
}

---Create a new template environment by running all populators in priority order.
---
---The returned environment has a strict __index metamethod that errors when
---sandboxed code accesses a variable that was never defined. This catches
---typos like {{ mane }} or {{ __name__ }} instead of silently producing nil.
---
---Keys are considered "known" if they were set by a populator, added after
---creation (e.g., user variables from frontmatter), or are framework-internal
---keys (FRAMEWORK_KEYS). Non-string keys (symbol keys) are exempt and always
---return nil without error.
---@return table env Fresh environment table with strict undefined-variable checking
function M.create_env()
  ensure_modules_loaded()
  local sorted = {}
  for _, p in ipairs(populators) do
    table.insert(sorted, p)
  end
  table.sort(sorted, function(a, b)
    return a.priority < b.priority
  end)

  -- Phase 1: Run populators with __newindex tracking.
  -- This captures every key that was ever set, even if a later populator
  -- removes it (e.g., env.utf8 = nil in LuaJIT where utf8 is undefined).
  local known_keys = {} ---@type table<any, boolean>
  for _, key in ipairs(FRAMEWORK_KEYS) do
    known_keys[key] = true
  end
  local env = setmetatable({}, {
    __newindex = function(self, key, value)
      known_keys[key] = true
      rawset(self, key, value)
    end,
  })

  for _, p in ipairs(sorted) do
    p.populate(env)
  end

  -- Phase 2: Install strict __index that errors on truly undefined variables.
  setmetatable(env, {
    __index = function(_, key)
      if known_keys[key] or type(key) ~= "string" then
        return nil
      end
      error(string.format("Undefined variable '%s'", key), 2)
    end,
    __newindex = function(self, key, value)
      known_keys[key] = true
      rawset(self, key, value)
    end,
  })

  return env
end

---Create a template environment pre-seeded from a document context.
---
---Bridges document identity (file path, frontmatter options, user variables)
---into a fresh template environment. User-visible fields (__filename, __dirname)
---are set as string keys; internal metadata (frontmatter opts, bufnr, diagnostics)
---uses symbol keys invisible to sandbox code.
---@param ctx flemma.Context|nil Document context, or nil for an empty environment
---@param bufnr? integer Buffer number for context-aware operations
---@return table env
function M.from_context(ctx, bufnr)
  local env = M.create_env()

  if ctx and type(ctx.get_filename) == "function" then
    env.__filename = ctx:get_filename()
    env.__dirname = ctx:get_dirname()
  else
    env.__filename = nil
    env.__dirname = nil
  end

  env[symbols.BUFFER_NUMBER] = bufnr
  env[symbols.DIAGNOSTICS] = {}

  local variables = ctx and ctx[symbols.VARIABLES]
  for k, v in pairs(variables or {}) do
    env[k] = v
  end

  return env
end

---Setup: register built-in populators and user-configured modules.
function M.setup()
  for _, module_path in ipairs(BUILTIN_POPULATORS) do
    local mod = loader.load(module_path)
    M.register(mod.name, mod)
  end
  local resolved_config = config_facade.get()
  if resolved_config.templating and resolved_config.templating.modules then
    for _, module_path in ipairs(resolved_config.templating.modules) do
      M.register_module(module_path)
    end
  end
end

return M
