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
  -- Remove existing resolver with same name
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
    for _, name in
      ipairs(policy --[[@as string[] ]])
    do
      if name == tool_name then
        return "approve"
      end
    end
    return nil
  end

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
      -- Module path: validate now, load lazily on first resolve
      loader.assert_exists(auto_approve)
      local module_path = auto_approve
      ---@type { resolve: fun(tool_name: string, input: table, context: flemma.config.AutoApproveContext): flemma.tools.ApprovalResult|nil }|nil
      local loaded_resolver = nil
      M.register("config:auto_approve", {
        priority = 100,
        description = "Built-in resolver from module " .. module_path,
        resolve = function(tool_name, input, context)
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
        end,
      })
    elseif type(auto_approve) ~= "table" and type(auto_approve) ~= "function" then
      log.warn("approval: unexpected auto_approve type: " .. type(auto_approve))
    else
      M.register("config:auto_approve", {
        priority = 100,
        description = "Built-in resolver from config.tools.auto_approve",
        resolve = function(tool_name, input, context)
          return resolve_auto_approve_policy(auto_approve, tool_name, input, context, "require_approval")
        end,
      })
    end
  end

  -- Frontmatter resolver: evaluates buffer frontmatter to get per-buffer auto_approve.
  -- Always registered; no-op when frontmatter doesn't set auto_approve.
  M.register("frontmatter:auto_approve", {
    priority = 90,
    description = "Per-buffer approval from frontmatter flemma.opt.tools.auto_approve",
    resolve = function(tool_name, input, context)
      local processor = require("flemma.processor")
      local opts = processor.resolve_buffer_opts(context.bufnr)
      if not opts or not opts.auto_approve then
        return nil
      end
      return resolve_auto_approve_policy(opts.auto_approve, tool_name, input, context)
    end,
  })

  local require_approval = tools_config and tools_config.require_approval
  if require_approval == false then
    M.register("config:catch_all_approve", {
      priority = 0,
      description = "Built-in catch-all from config.tools.require_approval = false",
      resolve = function()
        return "approve"
      end,
    })
  end
end

return M
