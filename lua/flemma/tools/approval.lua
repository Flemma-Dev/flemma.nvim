--- Tool execution approval resolver registry
--- Priority-based chain of named resolvers that determine whether a tool call
--- should be auto-approved, require user approval, or be denied.
--- Resolvers are evaluated in priority order (highest first); the first non-nil
--- result wins. If no resolver returns a decision, defaults to "require_approval".
---@class flemma.tools.Approval
local M = {}

local state = require("flemma.state")
local log = require("flemma.logging")

---@alias flemma.tools.ApprovalResult "approve"|"require_approval"|"deny"

---@class flemma.tools.ApprovalResolverDefinition
---@field resolve fun(tool_name: string, input: table<string, any>, context: flemma.config.AutoApproveContext): flemma.tools.ApprovalResult|nil
---@field priority? integer Higher values are evaluated first (default: 50)
---@field description? string Human-readable description for debugging/introspection

---@class flemma.tools.ApprovalResolverEntry
---@field name string Unique resolver name
---@field resolve fun(tool_name: string, input: table<string, any>, context: flemma.config.AutoApproveContext): flemma.tools.ApprovalResult|nil
---@field priority integer Higher values are evaluated first
---@field description? string Human-readable description

local DEFAULT_PRIORITY = 50

---@type flemma.tools.ApprovalResolverEntry[]
local resolvers = {}

---@type boolean
local sorted = true

---@type table<string, true>
local VALID_RESULTS = {
  approve = true,
  require_approval = true,
  deny = true,
}

---Ensure the resolver chain is sorted by priority (descending), with name as tie-breaker.
local function ensure_sorted()
  if sorted then
    return
  end
  table.sort(resolvers, function(a, b)
    if a.priority == b.priority then
      return a.name < b.name
    end
    return a.priority > b.priority
  end)
  sorted = true
end

---Insert or replace a resolver entry. Shared by public register() and internal setup().
---@param name string Unique resolver name
---@param definition flemma.tools.ApprovalResolverDefinition
local function register_entry(name, definition)
  for i, entry in ipairs(resolvers) do
    if entry.name == name then
      table.remove(resolvers, i)
      break
    end
  end

  table.insert(resolvers, {
    name = name,
    resolve = definition.resolve,
    priority = definition.priority or DEFAULT_PRIORITY,
    description = definition.description,
  })
  sorted = false
end

---Register a named approval resolver.
---If a resolver with the same name already exists, it is replaced.
---@param name string Unique resolver name
---@param definition flemma.tools.ApprovalResolverDefinition
function M.register(name, definition)
  local loader = require("flemma.loader")
  if loader.is_module_path(name) then
    error(
      string.format("flemma: approval resolver name '%s' must not contain dots (dots indicate module paths)", name),
      2
    )
  end
  register_entry(name, definition)
end

---Unregister a resolver by name.
---@param name string
---@return boolean removed True if a resolver was found and removed
function M.unregister(name)
  for i, entry in ipairs(resolvers) do
    if entry.name == name then
      table.remove(resolvers, i)
      return true
    end
  end
  return false
end

---Get a resolver entry by name.
---@param name string
---@return flemma.tools.ApprovalResolverEntry|nil
function M.get(name)
  for _, entry in ipairs(resolvers) do
    if entry.name == name then
      return entry
    end
  end
  return nil
end

---Get all registered resolvers, sorted by priority (highest first).
---@return flemma.tools.ApprovalResolverEntry[]
function M.get_all()
  ensure_sorted()
  return vim.deepcopy(resolvers)
end

---Clear all registered resolvers.
function M.clear()
  resolvers = {}
  sorted = true
end

---Get the count of registered resolvers.
---@return integer
function M.count()
  return #resolvers
end

---Resolve whether a tool execution should be auto-approved, require approval, or be denied.
---Evaluates resolvers in priority order (highest first). First non-nil result wins.
---If no resolver returns a decision, defaults to "require_approval".
---@param tool_name string
---@param input table<string, any>
---@param context flemma.config.AutoApproveContext
---@return flemma.tools.ApprovalResult
function M.resolve(tool_name, input, context)
  ensure_sorted()

  for _, entry in ipairs(resolvers) do
    local ok, result = pcall(entry.resolve, tool_name, input, context)
    if not ok then
      log.warn("approval: resolver '" .. entry.name .. "' error: " .. tostring(result))
    elseif result ~= nil then
      if VALID_RESULTS[result] then
        return result
      end
      log.warn("approval: resolver '" .. entry.name .. "' returned invalid result: " .. tostring(result))
    end
  end

  return "require_approval"
end

---Resolve an auto_approve policy (string[] or function) against a tool call.
---Shared by config and frontmatter resolvers to avoid duplicating the dispatch logic.
---@param policy flemma.config.AutoApprove The auto_approve value
---@param tool_name string
---@param input table<string, any>
---@param context flemma.config.AutoApproveContext
---@param error_result? flemma.tools.ApprovalResult Value to return on function error (default: nil/pass)
---@return flemma.tools.ApprovalResult|nil
local function resolve_auto_approve_policy(policy, tool_name, input, context, error_result)
  if type(policy) == "table" then
    local tool_presets = require("flemma.tools.presets")
    local approved = {}
    local denied = {}

    for _, entry in
      ipairs(policy --[[@as string[] ]])
    do
      if vim.startswith(entry, "$") then
        local preset = tool_presets.get(entry)
        if preset then
          if preset.approve then
            for _, name in ipairs(preset.approve) do
              approved[name] = true
            end
          end
          if preset.deny then
            for _, name in ipairs(preset.deny) do
              denied[name] = true
            end
          end
        end
      else
        approved[entry] = true
      end
    end

    local exclusions = context.opts and context.opts.auto_approve_exclusions
    if exclusions then
      for name in pairs(exclusions) do
        approved[name] = nil
      end
    end

    if denied[tool_name] then
      return "deny"
    end
    if approved[tool_name] then
      return "approve"
    end
    return nil
  end

  -- Function path unchanged from current code
  if type(policy) == "function" then
    local fn = policy --[[@as flemma.config.AutoApproveFunction]]
    local ok, decision = pcall(fn, tool_name, input, context)
    if not ok then
      log.warn("approval: auto_approve error: " .. tostring(decision))
      return error_result
    end
    if decision == true then
      return "approve"
    end
    if decision == "deny" then
      return "deny"
    end
    if decision == false then
      return "require_approval"
    end
    return nil
  end

  return nil
end

---Build a lazy-loading resolve function for a single module path.
---Validates existence eagerly but defers require() until first call.
---@param module_path string Dot-notation Lua module path
---@return fun(tool_name: string, input: table, context: flemma.config.AutoApproveContext): flemma.tools.ApprovalResult|nil
local function build_module_resolver(module_path)
  local loader = require("flemma.loader")
  loader.assert_exists(module_path)
  ---@type { resolve: fun(tool_name: string, input: table, context: flemma.config.AutoApproveContext): flemma.tools.ApprovalResult|nil }|nil
  local loaded_resolver = nil
  return function(tool_name, input, context)
    if not loaded_resolver then
      local mod = loader.load(module_path)
      if type(mod.resolve) == "function" then
        loaded_resolver = mod
      elseif type(mod) == "function" then
        loaded_resolver = { resolve = mod }
      else
        log.warn("approval: module '" .. module_path .. "' does not export 'resolve' function")
        loaded_resolver = {
          resolve = function()
            return nil
          end,
        }
      end
    end
    return loaded_resolver.resolve(tool_name, input, context)
  end
end

---Register built-in resolvers derived from the user's config.
---Converts `config.tools.auto_approve` and `config.tools.require_approval` into
---resolver chain entries. Called during plugin setup after config is stored in state.
function M.setup()
  local config = state.get_config()
  local tools_config = config.tools

  local auto_approve = tools_config and tools_config.auto_approve
  if auto_approve ~= nil then
    local loader = require("flemma.loader")
    if type(auto_approve) == "string" and loader.is_module_path(auto_approve) then
      -- Single module path: validate now, load lazily on first resolve
      -- Registered under the module path so users can get()/unregister() by path
      local module_resolve = build_module_resolver(auto_approve)
      register_entry(auto_approve, {
        priority = 100,
        description = "Built-in resolver from module " .. auto_approve,
        resolve = function(tool_name, input, context)
          if context.opts and context.opts.auto_approve then
            return nil -- defer to frontmatter resolver
          end
          return module_resolve(tool_name, input, context)
        end,
      })
    elseif type(auto_approve) == "table" then
      -- String array: partition into module paths, preset refs, and plain tool names
      ---@type string[]
      local tool_names = {}
      ---@type string[]
      local module_paths = {}
      for _, entry in
        ipairs(auto_approve --[[@as string[] ]])
      do
        if loader.is_module_path(entry) then
          table.insert(module_paths, entry)
        else
          -- Both $-prefixed preset refs and plain tool names stay in tool_names
          table.insert(tool_names, entry)
        end
      end
      -- Register a resolver per module path, addressable by path
      for _, module_path in ipairs(module_paths) do
        local module_resolve = build_module_resolver(module_path)
        register_entry(module_path, {
          priority = 100,
          description = "Built-in resolver from module " .. module_path,
          resolve = function(tool_name, input, context)
            if context.opts and context.opts.auto_approve then
              return nil -- defer to frontmatter resolver
            end
            return module_resolve(tool_name, input, context)
          end,
        })
      end
      -- Register a tool-name list resolver if any plain names or preset refs remain
      if #tool_names > 0 then
        register_entry("urn:flemma:approval:config", {
          priority = 100,
          description = "Built-in resolver from config.tools.auto_approve",
          resolve = function(tool_name, input, context)
            if context.opts and context.opts.auto_approve then
              return nil -- defer to frontmatter resolver
            end
            return resolve_auto_approve_policy(tool_names, tool_name, input, context, "require_approval")
          end,
        })
      end
    elseif type(auto_approve) == "function" then
      register_entry("urn:flemma:approval:config", {
        priority = 100,
        description = "Built-in resolver from config.tools.auto_approve",
        resolve = function(tool_name, input, context)
          if context.opts and context.opts.auto_approve then
            return nil -- defer to frontmatter resolver
          end
          return resolve_auto_approve_policy(auto_approve, tool_name, input, context, "require_approval")
        end,
      })
    else
      log.warn("approval: unexpected auto_approve type: " .. type(auto_approve))
    end
  end

  -- Frontmatter resolver: reads pre-evaluated opts from context.opts.
  -- Always registered; no-op when opts are not provided or don't set auto_approve.
  register_entry("urn:flemma:approval:frontmatter", {
    priority = 90,
    description = "Per-buffer approval from frontmatter flemma.opt.tools.auto_approve",
    resolve = function(tool_name, input, context)
      local opts = context.opts
      if not opts or not opts.auto_approve then
        return nil
      end
      return resolve_auto_approve_policy(opts.auto_approve, tool_name, input, context)
    end,
  })

  -- Sandbox-aware auto-approval: when sandboxing is enabled and a backend is
  -- available, auto-approve tools that execute inside the sandbox (currently: bash).
  -- Priority 50: below config (100) and frontmatter (90) so explicit user
  -- preferences always win, but above the catch-all (0).
  -- Checks are deferred to resolve time so runtime overrides and frontmatter
  -- sandbox options are respected per-call.
  register_entry("urn:flemma:approval:sandbox", {
    priority = DEFAULT_PRIORITY,
    description = "Auto-approve sandboxed tools when sandbox is enabled with an available backend",
    resolve = function(tool_name, _input, context)
      -- Only handle tools that execute inside the sandbox
      if tool_name ~= "bash" then
        return nil
      end

      -- Respect frontmatter exclusions (e.g. auto_approve:remove("bash"))
      local exclusions = context.opts and context.opts.auto_approve_exclusions
      if exclusions and exclusions[tool_name] then
        return nil
      end

      -- Resolve effective sandbox config (global + frontmatter + runtime override)
      local sandbox = require("flemma.sandbox")
      local sandbox_config = sandbox.resolve_config(context.opts)
      if not sandbox_config.enabled or sandbox_config.auto_approve == false then
        return nil
      end

      -- Verify a backend is actually available (not just configured)
      local backend_ok = sandbox.validate_backend(context.opts)
      if not backend_ok then
        return nil
      end

      return "approve"
    end,
  })

  local require_approval = tools_config and tools_config.require_approval
  if require_approval == false then
    register_entry("urn:flemma:approval:catch-all", {
      priority = 0,
      description = "Built-in catch-all from config.tools.require_approval = false",
      resolve = function()
        return "approve"
      end,
    })
  end
end

return M
