--- Tool calling support for Flemma
--- Manages tool registry, async source resolution, and built-in tool definitions
---@class flemma.Tools
local M = {}

local config_facade = require("flemma.config")
local hooks = require("flemma.hooks")
local json = require("flemma.utilities.json")
local loader = require("flemma.loader")
local log = require("flemma.logging")
local messages = require("flemma.messages")
local notify = require("flemma.notify")
local readiness = require("flemma.readiness")
local registry = require("flemma.tools.registry")

local BUILTIN_TOOLS = {
  "flemma.tools.definitions.builtin.bash",
  "flemma.tools.definitions.builtin.read",
  "flemma.tools.definitions.builtin.edit",
  "flemma.tools.definitions.builtin.write",
  "flemma.tools.definitions.builtin.grep",
  "flemma.tools.definitions.builtin.find",
  "flemma.tools.definitions.builtin.ls",
  "flemma.tools.definitions.builtin.mcporter",
  "flemma.tools.definitions.harness.jobs",
}

--------------------------------------------------------------------------------
-- Async source tracking
--------------------------------------------------------------------------------

local pending_sources = 0
---@type fun()[]
local ready_callbacks = {}
local active_timers = {}
local generation = 0

---@type { resolve_fn: fun(register: fun(name: string, def: flemma.tools.ToolDefinition), done: fun(err?: string)), opts: { timeout?: integer } }[]|nil
local deferred_async_sources = {}

---Fire all ready callbacks, clear the list, and emit the boot-complete autocmd
local function fire_ready_callbacks()
  local callbacks = ready_callbacks
  ready_callbacks = {}
  for _, cb in ipairs(callbacks) do
    cb()
  end
  hooks.dispatch("boot:complete")
end

--- Register a tool definition, materialize its config_schema defaults into L10,
--- and append its name to the tools allow_list so the default resolved tools
--- list includes all registered tools.
--- Tools with `enabled = false` are registered in the registry (available for
--- frontmatter opt-in) but not appended to the default tools list.
---@param name string
---@param def flemma.tools.ToolDefinition
local function register_tool(name, def)
  registry.register(name, def)
  if def.enabled ~= false then
    config_facade.record_default("append", "tools", name)
  end
  if def.metadata and def.metadata.config_schema then
    config_facade.register_module_defaults("tools", name, def.metadata.config_schema)
  end
end

---Register an async tool source that resolves definitions asynchronously
---@param resolve_fn fun(register: fun(name: string, def: flemma.tools.ToolDefinition), done: fun(err?: string)) Resolver function
---@param opts? { timeout?: integer } Options (timeout in seconds)
function M.register_async(resolve_fn, opts)
  opts = opts or {}
  pending_sources = pending_sources + 1

  local completed = false
  local my_generation = generation

  ---@param err? string
  local function done(err)
    if completed or my_generation ~= generation then
      return
    end
    completed = true

    if err then
      notify.warn("Async tool source failed: " .. err)
    end

    pending_sources = pending_sources - 1
    if pending_sources == 0 then
      vim.schedule(fire_ready_callbacks)
    end
  end

  ---@param name string
  ---@param def flemma.tools.ToolDefinition
  local function register(name, def)
    register_tool(name, def)
  end

  -- Set up timeout
  local resolved_config = config_facade.get()
  local timeout_s = opts.timeout
    or (resolved_config and resolved_config.tools and resolved_config.tools.default_timeout)
    or 30
  local timer = vim.uv.new_timer()
  if not timer then
    done("Failed to create timer")
    return
  end
  local function close_timer()
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end
  table.insert(active_timers, close_timer)
  timer:start(timeout_s * 1000, 0, function()
    done("Timed out after " .. timeout_s .. "s")
    close_timer()
  end)

  local ok, err = pcall(resolve_fn, register, done)
  if not ok then
    done(tostring(err))
  end
end

---Check whether all async tool sources have resolved
---@return boolean
function M.is_ready()
  return pending_sources == 0
end

---Register a callback to fire when all async sources are ready.
---Fires immediately if already ready.
---@param callback fun()
function M.on_ready(callback)
  if pending_sources == 0 then
    vim.schedule(callback)
    return
  end
  table.insert(ready_callbacks, callback)
end

---Start async tool sources that were deferred during module registration.
---Called after config finalization so DISCOVER-backed config values (e.g.,
---tools.mcporter.enabled) are available when resolvers read config.
function M.start_pending_sources()
  local sources = deferred_async_sources or {}
  deferred_async_sources = nil
  for _, entry in ipairs(sources) do
    M.register_async(entry.resolve_fn, entry.opts)
  end
  if #sources == 0 and pending_sources == 0 then
    vim.schedule(fire_ready_callbacks)
  end
end

--------------------------------------------------------------------------------
-- Third-party module tracking
--------------------------------------------------------------------------------

---@type string[]
local pending_modules = {}

---@type table<string, boolean>
local loaded_modules = {}

---Register a module path for lazy loading.
---Validates that the module exists immediately; defers actual require() until needed.
---@param module_path string Lua module path (must contain a dot)
function M.register_module(module_path)
  loader.assert_exists(module_path)
  if not loaded_modules[module_path] then
    table.insert(pending_modules, module_path)
  end
end

---Load all pending modules. Called before get_all/get_for_prompt.
local function ensure_modules_loaded()
  if #pending_modules == 0 then
    return
  end
  local to_load = pending_modules
  pending_modules = {}
  for _, module_path in ipairs(to_load) do
    if not loaded_modules[module_path] then
      loaded_modules[module_path] = true
      M.register(module_path)
    end
  end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

---Raise Suspense if async tool sources are still running, then load any
---pending third-party modules. Safe to call from any pipeline stage that
---needs tool definitions to be available.
function M.ensure_ready()
  if pending_sources > 0 then
    local boundary = readiness.get_or_create_boundary("tools:loaded", function(done)
      M.on_ready(function()
        done({ ok = true })
      end)
    end)
    error(readiness.Suspense.new("Waiting for tool definitions to load…", boundary))
  end
  ensure_modules_loaded()
end

---Setup tool registry with built-in tools
function M.setup()
  for _, module_name in ipairs(BUILTIN_TOOLS) do
    M.register(module_name)
  end

  local resolved_config = config_facade.get()
  if resolved_config.tools and resolved_config.tools.modules then
    for _, module_path in ipairs(resolved_config.tools.modules) do
      M.register_module(module_path)
    end
  end
end

--- Build a tool description with output_schema information merged in
--- This creates a description that helps the model understand what the tool returns
---@param tool flemma.tools.ToolDefinition The tool definition
---@return string The full description with output information
function M.build_description(tool)
  local desc = tool.description or ""

  if tool.output_schema then
    -- Add $schema hint and JSON-encode the output schema
    local schema_with_hint = vim.tbl_extend("keep", {
      ["$schema"] = "https://json-schema.org/draft/2020-12/schema",
    }, tool.output_schema)
    local schema_json = json.encode(schema_with_hint)
    desc = desc .. "\n\nReturns (JSON Schema): " .. schema_json
  end

  return desc
end

--- Serialize a tool definition's input_schema to a plain JSON Schema table.
--- If input_schema is a schema DSL node (has `to_json_schema()`), serialize it.
--- If it's already a plain table, pass it through unchanged.
---@param definition flemma.tools.ToolDefinition
---@return flemma.tools.JSONSchema
function M.to_json_schema(definition)
  local schema = definition.input_schema
  if type(schema.to_json_schema) == "function" then
    return schema:to_json_schema()
  end
  return schema --[[@as flemma.tools.JSONSchema]]
end

---Serialize a tool's input_schema for prompt inclusion, injecting the
---`background` parameter for async tools that haven't opted out.
---@param definition flemma.tools.ToolDefinition
---@return flemma.tools.JSONSchema
function M.to_json_schema_for_prompt(definition)
  local schema = M.to_json_schema(definition)
  if definition.async and definition.backgroundable ~= false then
    schema = vim.deepcopy(schema)
    schema.properties = schema.properties or {}
    schema.properties.background = {
      type = "boolean",
      default = false,
      description = messages.render("tool-parameter--background"),
    }
    log.trace("tools: injected background parameter into schema for " .. definition.name)
  end
  return schema
end

---Get all registered tools (excludes disabled tools by default).
---Loads any pending third-party modules before returning.
---@param opts? { include_disabled?: boolean, config?: flemma.Config }
---@return table<string, flemma.tools.ToolDefinition>
function M.get_all(opts)
  ensure_modules_loaded()
  opts = opts or {}
  if not opts.config then
    opts.config = config_facade.materialize()
  end
  return registry.get_all(opts --[[@as { include_disabled?: boolean, config?: flemma.Config }]])
end

--- Get tools filtered by per-buffer config.
--- When the config store has a tools list for this buffer (via frontmatter),
--- only matching tools are returned (including disabled tools that were
--- explicitly listed — this allows users to enable disabled tools).
--- When bufnr is nil or the tools list is empty/unset, all enabled tools are returned.
---@param bufnr? integer Buffer number for per-buffer config resolution
---@return table<string, flemma.tools.ToolDefinition>
function M.get_for_prompt(bufnr)
  -- Block until every async tool source (e.g. MCPorter) has finished registering.
  -- The full tool set goes into the provider request as part of the cache prefix.
  -- If we allowed a request to go out before all sources resolve, the first request
  -- would establish a prefix with a partial tool list. Once the remaining sources
  -- finish, subsequent requests would include the full list, breaking the prefix
  -- and invalidating the cache for the entire conversation from that point on.
  M.ensure_ready()

  if bufnr then
    local tools_info = config_facade.inspect(bufnr, "tools")
    local tools_list = tools_info and tools_info.value
    if type(tools_list) == "table" then
      local source = tools_info.layer
      if source and source ~= "D" then
        if #tools_list == 0 then
          return {}
        end
        local all_tools = M.get_all({ include_disabled = true })
        local allowed = {}
        for _, name in ipairs(tools_list) do
          allowed[name] = true
        end
        local filtered = {}
        for name, def in pairs(all_tools) do
          if allowed[name] then
            filtered[name] = def
          end
        end
        return filtered
      end
    end
  end
  return M.get_all()
end

--- Get all enabled tools for a prompt, sorted alphabetically by name.
--- Returns an array (not a name-keyed table) for deterministic ordering
--- in provider API requests, which improves prompt caching hit rates.
---@param bufnr? integer Buffer number for per-buffer config resolution
---@return flemma.tools.ToolDefinition[] sorted_tools Alphabetically sorted tool definitions
function M.get_sorted_for_prompt(bufnr)
  local all = M.get_for_prompt(bufnr)
  local sorted = {}
  for _, definition in pairs(all) do
    table.insert(sorted, definition)
  end
  table.sort(sorted, function(a, b)
    return a.name < b.name
  end)
  return sorted
end

---Register a tool definition or source.
---Dispatches on arguments:
---  register(name, def)       — single definition (sync)
---  register("mod.name")      — module with .resolve (async) or .definitions (sync)
---  register(resolve_fn)      — async resolve function
---  register({ resolve = fn })— async source table (optional .timeout)
---  register({ def1, def2 })  — array of definitions (sync)
---@param source string|function|table
---@param definition? flemma.tools.ToolDefinition
function M.register(source, definition)
  if type(source) == "string" then
    if definition then
      -- register(name, def) — single definition
      register_tool(source, definition)
    else
      -- register("module.name") — load module
      local mod = loader.load(source)
      if type(mod.resolve) == "function" then
        if mod.metadata and mod.metadata.config_schema then
          registry.register_module_schema(mod.metadata.name, mod.metadata.config_schema)
          config_facade.register_module_defaults("tools", mod.metadata.name, mod.metadata.config_schema)
        end
        if deferred_async_sources then
          table.insert(deferred_async_sources, { resolve_fn = mod.resolve, opts = { timeout = mod.timeout } })
        else
          M.register_async(mod.resolve, { timeout = mod.timeout })
        end
      elseif mod.definitions then
        for _, def in ipairs(mod.definitions) do
          register_tool(def.name, def)
        end
      end
    end
  elseif type(source) == "function" then
    M.register_async(source)
  elseif type(source) == "table" then
    if type(source.resolve) == "function" then
      M.register_async(source.resolve, { timeout = source.timeout })
    elseif source.name then
      -- Single definition table
      register_tool(source.name, source)
    else
      -- Array of definitions
      for _, def in ipairs(source) do
        register_tool(def.name, def)
      end
    end
  end
end

---Clear all registered tools and reset async state
function M.clear()
  registry.clear()
  pending_sources = 0
  ready_callbacks = {}
  generation = generation + 1
  for _, close_fn in ipairs(active_timers) do
    close_fn()
  end
  active_timers = {}
  deferred_async_sources = {}
  pending_modules = {}
  loaded_modules = {}
end

---Get a tool definition by name, ensuring lazy modules are loaded first.
---@param name string
---@return flemma.tools.ToolDefinition|nil
function M.get(name)
  ensure_modules_loaded()
  return registry.get(name)
end

---Get a tool's config schema for DISCOVER resolution.
---@param name string The tool name
---@return flemma.schema.ObjectNode|nil config_schema Tool config schema, or nil if not found
function M.get_config_schema(name)
  local tool = M.get(name)
  if tool then
    return tool.metadata and tool.metadata.config_schema
  end
  return registry.get_module_schema(name)
end

M.count = registry.count
M.is_executable = registry.is_executable
M.get_executor = registry.get_executor

--------------------------------------------------------------------------------
-- Tool approval (public API)
--------------------------------------------------------------------------------

---Approve a pending tool call by ID.
---Sets the tool_result header to `(approved)`. The next phase advance
---(manual `<C-]>` or autopilot) will execute the tool.
---@param bufnr integer
---@param tool_id string
---@return boolean success
---@return string|nil error
function M.approve(bufnr, tool_id)
  return require("flemma.tools.executor").approve(bufnr, tool_id)
end

---Reject a pending tool call by ID.
---Sets the tool_result header to `(rejected)`, optionally writing a
---rejection message into the fence body that the model will see.
---@param bufnr integer
---@param tool_id string
---@param message string|nil Optional rejection reason
---@return boolean success
---@return string|nil error
function M.reject(bufnr, tool_id, message)
  return require("flemma.tools.executor").reject(bufnr, tool_id, message)
end

return M
