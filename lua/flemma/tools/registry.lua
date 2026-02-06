--- Tool definition storage
--- Manages registered tools for API requests and execution
local M = {}

local tools = {}

---Register a tool definition
---@param name string The tool name
---@param definition table The tool definition with name, description, input_schema, and optional execute/async fields
function M.register(name, definition)
  tools[name] = definition
end

---Get a tool definition by name
---@param name string The tool name
---@return table|nil definition The tool definition, or nil if not found
function M.get(name)
  return tools[name]
end

---Get all registered tools (excludes hidden tools by default)
---@param opts? { include_hidden: boolean }
---@return table tools A copy of matching tool definitions
function M.get_all(opts)
  opts = opts or {}
  if opts.include_hidden then
    return vim.deepcopy(tools)
  end
  local result = {}
  for name, def in pairs(tools) do
    if not def.hidden then
      result[name] = vim.deepcopy(def)
    end
  end
  return result
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

---Check if a tool is executable (has an execute function and is not explicitly disabled)
---@param name string The tool name
---@return boolean
function M.is_executable(name)
  local tool = tools[name]
  if not tool then
    return false
  end
  if tool.executable == false then
    return false
  end
  return tool.execute ~= nil
end

---Get execution function and async flag for a tool
---@param name string The tool name
---@return function|nil executor, boolean is_async
function M.get_executor(name)
  local tool = tools[name]
  if not tool or not tool.execute or tool.executable == false then
    return nil, false
  end
  return tool.execute, tool.async == true
end

return M
