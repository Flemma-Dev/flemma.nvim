--- Tool calling support for Flemma
--- Manages tool registry and built-in tool definitions
local M = {}

local registry = require("flemma.tools.registry")

local builtin_tools = {
  "flemma.tools.definitions.calculator",
}

---Setup tool registry with built-in tools
function M.setup()
  for _, module_name in ipairs(builtin_tools) do
    local tool_module = require(module_name)
    registry.register(tool_module.definition.name, tool_module.definition)
  end
end

M.register = registry.register
M.get = registry.get
M.get_all = registry.get_all
M.clear = registry.clear
M.count = registry.count

return M
