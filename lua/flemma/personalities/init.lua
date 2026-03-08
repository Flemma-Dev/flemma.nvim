--- Personality registry for Flemma
--- Personalities are autonomous Lua modules that generate system prompts
--- from pre-built data (tools, environment, project context).
---@class flemma.Personalities
local M = {}

local loader = require("flemma.loader")
local registry_utils = require("flemma.registry")

---@class flemma.personalities.Personality
---@field render fun(opts: flemma.personalities.RenderOpts): string

---@class flemma.personalities.RenderOpts
---@field tools flemma.personalities.ToolEntry[]
---@field environment flemma.personalities.Environment
---@field project_context flemma.personalities.ProjectContextFile[]

---@class flemma.personalities.ToolEntry
---@field name string
---@field parts table<string, string[]>

---@class flemma.personalities.Environment
---@field cwd string
---@field current_file? string
---@field filetype? string
---@field git_branch? string
---@field date string
---@field time string

---@class flemma.personalities.CachedEnvironment
---@field date string
---@field time string

---@class flemma.personalities.ProjectContextFile
---@field path string
---@field content string

---@type table<string, string>
local BUILTIN_PERSONALITIES = {
  ["coding-assistant"] = "flemma.personalities.coding-assistant",
}

---@type table<string, flemma.personalities.Personality>
local personalities = {}

---Register a personality
---@param name string Personality name (no dots)
---@param personality flemma.personalities.Personality
function M.register(name, personality)
  registry_utils.validate_name(name, "personality")
  personalities[name] = personality
end

---Unregister a personality by name
---@param name string
---@return boolean removed
function M.unregister(name)
  if personalities[name] then
    personalities[name] = nil
    return true
  end
  return false
end

---Get a personality by name
---@param name string
---@return flemma.personalities.Personality|nil
function M.get(name)
  return personalities[name]
end

---Get all registered personalities
---@return table<string, flemma.personalities.Personality>
function M.get_all()
  return vim.deepcopy(personalities)
end

---Check if a personality exists
---@param name string
---@return boolean
function M.has(name)
  return personalities[name] ~= nil
end

---Clear all registered personalities
function M.clear()
  personalities = {}
end

---Get the count of registered personalities
---@return integer
function M.count()
  local n = 0
  for _ in pairs(personalities) do
    n = n + 1
  end
  return n
end

---Load and register built-in personalities
function M.setup()
  for name, module_path in pairs(BUILTIN_PERSONALITIES) do
    local personality = loader.load(module_path)
    M.register(name, personality)
  end
end

return M
