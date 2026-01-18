--- Tool definition storage
--- Manages registered tools for API requests
local M = {}

local tools = {}

---Register a tool definition
---@param name string The tool name
---@param definition table The tool definition with name, description, input_schema
function M.register(name, definition)
  tools[name] = definition
end

---Get a tool definition by name
---@param name string The tool name
---@return table|nil definition The tool definition, or nil if not found
function M.get(name)
  return tools[name]
end

---Get all registered tools
---@return table tools A copy of all tool definitions
function M.get_all()
  return vim.deepcopy(tools)
end

---Clear all registered tools
function M.clear()
  tools = {}
end

---Get the count of registered tools
---@return number count The number of registered tools
function M.count()
  local n = 0
  for _ in pairs(tools) do
    n = n + 1
  end
  return n
end

return M
