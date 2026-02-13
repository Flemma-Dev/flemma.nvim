--- Tool calling support for Flemma
--- Manages tool registry, async source resolution, and built-in tool definitions
---@class flemma.Tools
local M = {}

local registry = require("flemma.tools.registry")

local builtin_tools = {
  "flemma.tools.definitions.calculator",
  "flemma.tools.definitions.bash",
  "flemma.tools.definitions.read",
  "flemma.tools.definitions.edit",
  "flemma.tools.definitions.write",
}

--------------------------------------------------------------------------------
-- Async source tracking
--------------------------------------------------------------------------------

local pending_sources = 0
---@type fun()[]
local ready_callbacks = {}
local active_timers = {}
local generation = 0

---Fire all ready callbacks and clear the list
local function fire_ready_callbacks()
  local callbacks = ready_callbacks
  ready_callbacks = {}
  for _, cb in ipairs(callbacks) do
    cb()
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
      vim.schedule(function()
        vim.notify("Flemma: Async tool source failed: " .. err, vim.log.levels.WARN)
      end)
    end

    pending_sources = pending_sources - 1
    if pending_sources == 0 then
      vim.schedule(fire_ready_callbacks)
    end
  end

  ---@param name string
  ---@param def flemma.tools.ToolDefinition
  local function register(name, def)
    registry.define(name, def)
  end

  -- Set up timeout
  local config = require("flemma.config")
  local timeout_s = opts.timeout or config.tools.default_timeout or 30
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

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

---Setup tool registry with built-in tools
function M.setup()
  for _, module_name in ipairs(builtin_tools) do
    M.register(module_name)
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
    local json = vim.fn.json_encode(schema_with_hint)
    desc = desc .. "\n\nReturns (JSON Schema): " .. json
  end

  return desc
end

--- Get tools filtered by resolved per-buffer opts
--- When opts.tools is present, only matching tools are returned (including disabled tools
--- that were explicitly listed — this allows users to enable disabled tools via flemma.opt).
--- When opts is nil or opts.tools is nil, all enabled tools are returned.
---@param opts flemma.opt.ResolvedOpts|nil
---@return table<string, flemma.tools.ToolDefinition>
function M.get_for_prompt(opts)
  if opts and opts.tools then
    -- Include disabled tools so users can explicitly enable them
    local all_tools = M.get_all({ include_disabled = true })
    local allowed = {}
    for _, name in ipairs(opts.tools) do
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
  return M.get_all()
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
      registry.define(source, definition)
    else
      -- register("module.name") — load module
      local mod = require(source)
      if type(mod.resolve) == "function" then
        M.register_async(mod.resolve, { timeout = mod.timeout })
      elseif mod.definitions then
        for _, def in ipairs(mod.definitions) do
          registry.define(def.name, def)
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
      registry.define(source.name, source)
    else
      -- Array of definitions
      for _, def in ipairs(source) do
        registry.define(def.name, def)
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
end

M.get = registry.get
M.get_all = registry.get_all
M.count = registry.count
M.is_executable = registry.is_executable
M.get_executor = registry.get_executor

return M
