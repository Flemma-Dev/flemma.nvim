--- Tool execution approval resolver registry
--- Priority-based chain of named resolvers that determine whether a tool call
--- should be auto-approved, require user approval, or be denied.
--- Resolvers are evaluated in priority order (highest first); the first non-nil
--- result wins. If no resolver returns a decision, defaults to "require_approval".
---@class flemma.tools.Approval
local M = {}

local config_facade = require("flemma.config")
local loader = require("flemma.loader")
local log = require("flemma.logging")
local registry_utils = require("flemma.registry")
local sandbox = require("flemma.sandbox")
local tools_registry = require("flemma.tools.registry")

---@class flemma.tools.AutoApproveContext
---@field bufnr integer
---@field tool_id string

---@alias flemma.tools.AutoApproveDecision true|false|"deny"

---@alias flemma.tools.AutoApproveFunction fun(tool_name: string, input: table, context: flemma.tools.AutoApproveContext): flemma.tools.AutoApproveDecision|nil

---@alias flemma.tools.ApprovalResult "approve"|"require_approval"|"deny"

---@class flemma.tools.ApprovalResolverDefinition
---@field resolve fun(tool_name: string, input: table<string, any>, context: flemma.tools.AutoApproveContext): flemma.tools.ApprovalResult|nil
---@field priority? integer Higher values are evaluated first (default: 50)
---@field description? string Human-readable description for debugging/introspection

---@class flemma.tools.ApprovalResolverEntry
---@field name string Unique resolver name
---@field resolve fun(tool_name: string, input: table<string, any>, context: flemma.tools.AutoApproveContext): flemma.tools.ApprovalResult|nil
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
  registry_utils.validate_name(name, "approval resolver")
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

---Check if a resolver exists by name.
---@param name string
---@return boolean
function M.has(name)
  for _, entry in ipairs(resolvers) do
    if entry.name == name then
      return true
    end
  end
  return false
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
---@param context flemma.tools.AutoApproveContext
---@return flemma.tools.ApprovalResult
function M.resolve(tool_name, input, context)
  local result = M.resolve_with_source(tool_name, input, context)
  return result
end

---Like resolve(), but also returns the name of the resolver that made the decision.
---Used by status display to annotate why a tool was approved/denied.
---@param tool_name string
---@param input table<string, any>
---@param context flemma.tools.AutoApproveContext
---@return flemma.tools.ApprovalResult result
---@return string source Resolver name, or "default" if no resolver matched
function M.resolve_with_source(tool_name, input, context)
  ensure_sorted()

  for _, entry in ipairs(resolvers) do
    local ok, result = pcall(entry.resolve, tool_name, input, context)
    if not ok then
      log.warn("approval: resolver '" .. entry.name .. "' error: " .. tostring(result))
    elseif result ~= nil then
      if VALID_RESULTS[result] then
        return result, entry.name
      end
      log.warn("approval: resolver '" .. entry.name .. "' returned invalid result: " .. tostring(result))
    end
  end

  return "require_approval", "default"
end

---Build a lazy-loading resolve function for a single module path.
---Validates existence eagerly but defers require() until first call.
---@param module_path string Dot-notation Lua module path
---@return fun(tool_name: string, input: table, context: flemma.tools.AutoApproveContext): flemma.tools.ApprovalResult|nil
local function build_module_resolver(module_path)
  loader.assert_exists(module_path)
  ---@type { resolve: fun(tool_name: string, input: table, context: flemma.tools.AutoApproveContext): flemma.tools.ApprovalResult|nil }|nil
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

---Resolve an auto_approve policy (string[] or function) against a tool call.
---The string[] path does a simple membership check — presets are already expanded
---by the config store's coerce function.
---@param policy flemma.tools.AutoApprove The auto_approve value (resolved from config store)
---@param tool_name string
---@param input table<string, any>
---@param context flemma.tools.AutoApproveContext
---@param error_result? flemma.tools.ApprovalResult Value to return on function error (default: nil/pass)
---@return flemma.tools.ApprovalResult|nil
local function resolve_auto_approve_policy(policy, tool_name, input, context, error_result)
  if type(policy) == "table" then
    for _, entry in
      ipairs(policy --[[@as string[] ]])
    do
      if loader.is_module_path(entry) then
        local ok, resolver = pcall(build_module_resolver, entry)
        if ok then
          local result = resolver(tool_name, input, context)
          if result ~= nil then
            return result
          end
        else
          log.warn("approval: failed to load module resolver '" .. entry .. "': " .. tostring(resolver))
        end
      elseif entry == tool_name then
        return "approve"
      end
    end
    return nil
  end

  -- Function path unchanged from current code
  if type(policy) == "function" then
    local fn = policy --[[@as flemma.tools.AutoApproveFunction]]
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

---Register built-in resolvers derived from the user's config.
---Converts `config.tools.auto_approve` and `config.tools.require_approval` into
---resolver chain entries. Called during plugin setup after config is stored in state.
function M.setup()
  local config = config_facade.get()
  local tools_config = config.tools

  -- Module-path auto_approve: user set auto_approve to a single module path string.
  -- Schema default is a list, so this only fires for explicit string values.
  local auto_approve = tools_config.auto_approve
  if type(auto_approve) == "string" and loader.is_module_path(auto_approve) then
    local module_resolve = build_module_resolver(auto_approve)
    register_entry(auto_approve, {
      priority = 100,
      description = "Built-in resolver from module " .. auto_approve,
      resolve = function(tool_name, input, context)
        return module_resolve(tool_name, input, context)
      end,
    })
  end

  -- Unified auto_approve resolver: reads the resolved auto_approve from the
  -- config store at resolve time. This single resolver replaces the old
  -- separate config + frontmatter resolvers — layer resolution handles merging.
  register_entry("urn:flemma:approval:config", {
    priority = 100,
    description = "Unified resolver from config store (all layers merged)",
    resolve = function(tool_name, input, context)
      local bufnr = context.bufnr
      local resolved = config_facade.inspect(bufnr, "tools.auto_approve")
      local policy = resolved and resolved.value
      if policy == nil then
        return nil
      end
      return resolve_auto_approve_policy(policy, tool_name, input, context, "require_approval")
    end,
  })

  -- Sandbox-aware auto-approval: when sandboxing is enabled and a backend is
  -- available, auto-approve tools that declare "can_auto_approve_if_sandboxed"
  -- in their capabilities array (currently: bash).
  -- Priority 25: below config (100) and the community default (50)
  -- so both explicit user preferences and third-party resolvers win. Above the
  -- catch-all (0). Checks are deferred to resolve time so runtime overrides and
  -- frontmatter sandbox options are respected per-call.
  register_entry("urn:flemma:approval:sandbox", {
    priority = 25,
    description = "Auto-approve sandboxed tools when sandbox is enabled with an available backend",
    resolve = function(tool_name, _input, context)
      local bufnr = context.bufnr

      -- Config-level guard: user explicitly disabled sandbox auto-approval
      if tools_config.auto_approve_sandboxed == false then
        return nil
      end

      -- Only handle tools that declare the sandbox auto-approve capability
      local definition = tools_registry.get(tool_name)
      if not definition or not definition.capabilities then
        return nil
      end
      if not vim.tbl_contains(definition.capabilities, "can_auto_approve_if_sandboxed") then
        return nil
      end

      -- Respect frontmatter exclusions. We must check the operation log, not the
      -- resolved list: a tool absent from the materialized list may simply have
      -- never been added — that's different from the user actively removing it.
      -- layer_has_op answers the intent question; the resolved value cannot.
      if
        bufnr
        and config_facade.layer_has_op(
          config_facade.LAYERS.FRONTMATTER,
          bufnr,
          "remove",
          "tools.auto_approve",
          tool_name
        )
      then
        return nil
      end

      -- A `set` op in frontmatter means the user specified the complete approval
      -- policy for this buffer — sandbox must not grant additional approvals.
      -- We check the op log because `set` and `append` can produce identical
      -- resolved lists; only the operation distinguishes full ownership from
      -- an incremental tweak.
      if bufnr and config_facade.layer_has_set(config_facade.LAYERS.FRONTMATTER, bufnr, "tools.auto_approve") then
        return nil
      end

      -- Verify sandbox is enabled and a backend is available.
      -- sandbox.is_enabled reads from the config store (includes frontmatter).
      if not sandbox.is_enabled(bufnr) then
        return nil
      end
      local backend_ok = sandbox.validate_backend(bufnr)
      if not backend_ok then
        return nil
      end

      return "approve"
    end,
  })

  local require_approval = tools_config.require_approval
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
