--- Per-buffer options for Flemma
--- Provides a vim.opt-style API for frontmatter configuration
---@class flemma.buffer.Opt
local M = {}

---@class flemma.opt.FrontmatterOpts
---@field tools string[]|nil List of allowed tool names
---@field auto_approve flemma.config.AutoApprove|nil Per-buffer auto-approve policy
---@field auto_approve_exclusions table<string, boolean>|nil Tools to exclude from preset expansion
---@field autopilot boolean|nil Per-buffer autopilot override (true/false)
---@field parameters table<string, any>|nil General parameter overrides (provider-agnostic)
---@field anthropic table<string, any>|nil Per-buffer Anthropic parameter overrides
---@field openai table<string, any>|nil Per-buffer OpenAI parameter overrides
---@field vertex table<string, any>|nil Per-buffer Vertex parameter overrides
---@field sandbox table|nil Per-buffer sandbox config overrides

---@class flemma.opt.Entry
---@field name string
---@field enabled boolean

--- Sentinel metatable used to identify ListOption instances
---@class flemma.opt.ListOption
---@field _entries flemma.opt.Entry[] Ordered entries with enabled flags (private)
---@field _universe table<string, boolean> Set of all valid names (private)
local ListOption = {}
ListOption.__index = ListOption

--- Levenshtein distance between two strings
---@param a string
---@param b string
---@return integer
local function levenshtein(a, b)
  local la, lb = #a, #b
  if la == 0 then
    return lb
  end
  if lb == 0 then
    return la
  end
  local prev, curr = {}, {}
  for j = 0, lb do
    prev[j] = j
  end
  for i = 1, la do
    curr[0] = i
    for j = 1, lb do
      local cost = a:byte(i) == b:byte(j) and 0 or 1
      curr[j] = math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
    end
    prev, curr = curr, prev
  end
  return prev[lb]
end

--- Validate that a name exists in the universe; errors with suggestion if not.
--- Module paths (containing dots) bypass the universe check and are validated via loader instead.
---@param self flemma.opt.ListOption
---@param name string
local function validate_name(self, name)
  local loader = require("flemma.loader")
  -- Module paths bypass the universe check — validated via loader instead
  if loader.is_module_path(name) then
    loader.assert_exists(name)
    -- Add to universe so subsequent operations recognize this name
    self._universe[name] = true
    return
  end
  if not self._universe[name] then
    local best, best_dist = nil, math.huge
    for candidate in pairs(self._universe) do
      local dist = levenshtein(name, candidate)
      if dist < best_dist then
        best, best_dist = candidate, dist
      end
    end
    local msg = string.format("flemma.opt: unknown value '%s'", name)
    if best and best_dist <= 3 then
      msg = msg .. string.format(". Did you mean '%s'?", best)
    end
    error(msg)
  end
end

---@param self flemma.opt.ListOption
---@param value string|string[]
---@return flemma.opt.ListOption
function ListOption:remove(value)
  local to_remove = {}
  if type(value) == "string" then
    validate_name(self, value)
    to_remove[value] = true
  elseif type(value) == "table" then
    for _, v in ipairs(value) do
      validate_name(self, v)
      to_remove[v] = true
    end
  end
  for _, entry in ipairs(self._entries) do
    if to_remove[entry.name] then
      entry.enabled = false
    end
  end
  return self
end

---@param self flemma.opt.ListOption
---@param value string|string[]
---@return flemma.opt.ListOption
function ListOption:append(value)
  if type(value) == "table" then
    for _, v in ipairs(value) do
      self:append(v)
    end
    return self
  end
  validate_name(self, value)
  -- Remove from current position
  for i, entry in ipairs(self._entries) do
    if entry.name == value then
      table.remove(self._entries, i)
      break
    end
  end
  -- Add at end, enabled
  table.insert(self._entries, { name = value, enabled = true })
  return self
end

---@param self flemma.opt.ListOption
---@param value string|string[]
---@return flemma.opt.ListOption
function ListOption:prepend(value)
  if type(value) == "table" then
    -- Prepend in reverse order so the final order matches the input
    for i = #value, 1, -1 do
      self:prepend(value[i])
    end
    return self
  end
  validate_name(self, value)
  -- Remove from current position
  for i, entry in ipairs(self._entries) do
    if entry.name == value then
      table.remove(self._entries, i)
      break
    end
  end
  -- Add at beginning, enabled
  table.insert(self._entries, 1, { name = value, enabled = true })
  return self
end

---@param self flemma.opt.ListOption
---@return string[]
function ListOption:get()
  local result = {}
  for _, entry in ipairs(self._entries) do
    if entry.enabled then
      table.insert(result, entry.name)
    end
  end
  return result
end

--- Set: enable only the listed names, disable all others
--- Listed names appear first in order, remaining names retain original order.
---@param self flemma.opt.ListOption
---@param names string[]
function ListOption:set(names)
  for _, name in ipairs(names) do
    validate_name(self, name)
  end
  local requested = {}
  for _, name in ipairs(names) do
    requested[name] = true
  end
  local new_entries = {}
  -- Add requested names first, in user-specified order, enabled
  for _, name in ipairs(names) do
    table.insert(new_entries, { name = name, enabled = true })
  end
  -- Add remaining names, disabled, preserving original order
  for _, entry in ipairs(self._entries) do
    if not requested[entry.name] then
      table.insert(new_entries, { name = entry.name, enabled = false })
    end
  end
  self._entries = new_entries
end

-- Operator overloads (vim.opt-style)
-- + appends, - removes, ^ prepends

---@param self flemma.opt.ListOption
---@param value string|string[]
---@return flemma.opt.ListOption
function ListOption:__add(value)
  return self:append(value)
end

---@param self flemma.opt.ListOption
---@param value string|string[]
---@return flemma.opt.ListOption
function ListOption:__sub(value)
  return self:remove(value)
end

---@param self flemma.opt.ListOption
---@param value string|string[]
---@return flemma.opt.ListOption
function ListOption:__pow(value)
  return self:prepend(value)
end

--- Marker used by is_list_option to identify ListOption instances across metatables.
---@type boolean
ListOption._is_list_option = true

--- Check if a value is a ListOption instance (supports custom per-instance metatables)
---@param v any
---@return boolean
local function is_list_option(v)
  if type(v) ~= "table" then
    return false
  end
  local mt = getmetatable(v)
  return type(mt) == "table" and mt._is_list_option == true
end

-- Option definitions: each returns an array of {name, enabled} entries
---@alias flemma.opt.DefaultFn fun(): flemma.opt.Entry[]

---@type table<string, flemma.opt.DefaultFn>
local option_defs = {
  tools = function()
    local tools_module = require("flemma.tools")
    local all_tools = tools_module.get_all({ include_disabled = true })
    local entries = {}
    for name, def in pairs(all_tools) do
      table.insert(entries, { name = name, enabled = def.enabled ~= false })
    end
    table.sort(entries, function(a, b)
      return a.name < b.name
    end)
    return entries
  end,
}

--- Create a new list option from an array of entries
---@param entries flemma.opt.Entry[]
---@return flemma.opt.ListOption
local function create_list_option(entries)
  local universe = {}
  for _, entry in ipairs(entries) do
    universe[entry.name] = true
  end
  return setmetatable({ _entries = entries, _universe = universe }, ListOption)
end

--- Create a new opt proxy and resolve function
--- Each call starts fresh from defaults (stateless per evaluation)
---@return table opt_proxy The proxy object injected as flemma.opt
---@return fun(): flemma.opt.FrontmatterOpts resolve Function to get frontmatter option values
function M.create()
  -- Create ListOption instances for each option, initialized from defaults
  ---@type table<string, flemma.opt.ListOption>
  local options = {}
  for name, default_fn in pairs(option_defs) do
    options[name] = create_list_option(default_fn())
  end

  -- Track which options were explicitly accessed
  ---@type table<string, boolean>
  local touched = {}

  -- Raw options that are sub-properties of ListOption instances (e.g., tools.auto_approve)
  ---@type table<string, any>
  local raw_options = {}

  -- Give the tools ListOption a custom metatable so flemma.opt.tools.auto_approve works
  -- while list operations (:remove, :append, +, -, ^) continue to function normally.
  local tools_option = options["tools"]
  setmetatable(tools_option, {
    _is_list_option = true,
    __index = function(_, key)
      if key == "auto_approve" then
        return raw_options.auto_approve
      end
      if key == "autopilot" then
        return raw_options.autopilot
      end
      return ListOption[key]
    end,
    __newindex = function(_, key, value)
      if key == "auto_approve" then
        if type(value) ~= "table" and type(value) ~= "function" then
          error(string.format("flemma.opt.tools.auto_approve: expected table or function, got %s", type(value)))
        end
        raw_options.auto_approve = value
        return
      end
      if key == "autopilot" then
        if type(value) ~= "boolean" then
          error(string.format("flemma.opt.tools.autopilot: expected boolean, got %s", type(value)))
        end
        raw_options.autopilot = value
        return
      end
      rawset(tools_option, key, value)
    end,
    __add = ListOption.__add,
    __sub = ListOption.__sub,
    __pow = ListOption.__pow,
  })

  -- Per-provider parameter overrides (e.g., { anthropic = { thinking_budget = 4096 } })
  ---@type table<string, table<string, any>>
  local provider_params = {}
  ---@type table<string, table>
  local provider_proxies = {}

  -- General parameter overrides (provider-agnostic, e.g., thinking = "high")
  -- Uses is_general_parameter from config manager plus thinking (added in Phase 5)
  ---@type table<string, any>
  local general_params = {}

  local config_manager = require("flemma.core.config.manager")

  local opt_proxy = setmetatable({}, {
    ---@param _ table
    ---@param key string
    ---@return flemma.opt.ListOption|table|any
    __index = function(_, key)
      if option_defs[key] then
        touched[key] = true
        return options[key]
      end
      if key == "sandbox" then
        return raw_options.sandbox
      end
      local provider_reg = require("flemma.provider.registry")
      if provider_reg.has(key) then
        if not provider_proxies[key] then
          provider_params[key] = provider_params[key] or {}
          provider_proxies[key] = setmetatable({}, {
            __index = function(_, param)
              return provider_params[key][param]
            end,
            __newindex = function(_, param, value)
              provider_params[key][param] = value
            end,
          })
        end
        return provider_proxies[key]
      end
      if config_manager.is_general_parameter(key) then
        return general_params[key]
      end
      error(string.format("flemma.opt: unknown option '%s'", key))
    end,

    ---@param _ table
    ---@param key string
    ---@param value any
    __newindex = function(_, key, value)
      if option_defs[key] then
        -- Operator chains (+ - ^) already mutated in-place and return the ListOption
        if is_list_option(value) then
          return
        end
        if type(value) ~= "table" then
          error(string.format("flemma.opt.%s: expected table, got %s", key, type(value)))
        end
        touched[key] = true
        options[key]:set(value)
        return
      end
      if key == "sandbox" then
        if type(value) == "boolean" then
          value = { enabled = value }
        elseif type(value) ~= "table" then
          error("flemma.opt.sandbox: expected boolean or table, got " .. type(value))
        end
        raw_options.sandbox = vim.tbl_deep_extend("force", raw_options.sandbox or {}, value)
        return
      end
      local provider_reg = require("flemma.provider.registry")
      if provider_reg.has(key) then
        if type(value) ~= "table" then
          error(string.format("flemma.opt.%s: expected table, got %s", key, type(value)))
        end
        provider_params[key] = value
        provider_proxies[key] = nil -- invalidate cached proxy
        return
      end
      if config_manager.is_general_parameter(key) then
        general_params[key] = value
        return
      end
      error(string.format("flemma.opt: unknown option '%s'", key))
    end,
  })

  ---@return flemma.opt.FrontmatterOpts
  local function resolve()
    ---@type flemma.opt.FrontmatterOpts
    local result = {}
    for name in pairs(touched) do
      result[name] = options[name]:get()
    end
    if raw_options.auto_approve ~= nil then
      result.auto_approve = raw_options.auto_approve
    end
    if raw_options.autopilot ~= nil then
      result.autopilot = raw_options.autopilot
    end
    if raw_options.sandbox ~= nil then
      result.sandbox = vim.deepcopy(raw_options.sandbox)
    end
    -- Add general parameter overrides
    if next(general_params) then
      result.parameters = vim.deepcopy(general_params)
    end
    -- Add provider-specific overrides
    for pname, params in pairs(provider_params) do
      if next(params) then
        result[pname] = vim.deepcopy(params)
      end
    end
    return result
  end

  return opt_proxy, resolve
end

return M
