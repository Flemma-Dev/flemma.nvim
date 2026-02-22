--- Tool definition storage
--- Pure storage for tool definitions — no async logic
---@class flemma.tools.Registry
local M = {}

---@class flemma.tools.JSONSchema
---@field type string|string[] JSON Schema type ("object", "string", "number", or nullable array like {"number", "null"})
---@field description? string Human-readable description of this schema element
---@field properties? table<string, flemma.tools.JSONSchema> Property schemas keyed by name
---@field required? string[] Required property names
---@field additionalProperties? boolean Whether to allow extra properties (set false for strict mode)

--- Context passed to tool execute functions as an optional third argument
---@class flemma.tools.ExecutionContext
---@field bufnr integer Buffer number for the current execution
---@field opts? flemma.opt.ResolvedOpts Per-buffer resolved options
---@field cwd string Absolute, normalized working directory
---@field __dirname? string Directory containing the .chat buffer (nil for unsaved buffers)
---@field __filename? string Full path of the .chat buffer (nil for unsaved buffers)

---@class flemma.tools.ToolDefinition
---@field name string Tool name (must match registry key)
---@field description string Human-readable description
---@field strict? boolean Enable strict schema enforcement (OpenAI only; requires additionalProperties=false on input_schema)
---@field input_schema flemma.tools.JSONSchema JSON Schema for the tool input
---@field output_schema? flemma.tools.JSONSchema JSON Schema for the tool output (used in description)
---@field async? boolean True if execute takes a callback (default false)
---@field enabled? boolean Set to false to exclude from API requests by default (still executable, can be enabled via flemma.opt.tools)
---@field executable? boolean Set to false to disable execution
---@field execute? fun(input: table<string, any>, callback?: fun(result: flemma.tools.ExecutionResult), context?: flemma.tools.ExecutionContext): any Executor function (sync returns ExecutionResult, async returns cancel fn or nil)
---@field format_preview? fun(input: table<string, any>, max_length: integer): string Custom preview body generator (receives input and available width after "name: " prefix)

---@class flemma.tools.ExecutionResult
---@field success boolean Whether execution succeeded
---@field output? string|table Result output (string or JSON-encodable table)
---@field error? string Error message (when success=false)

---@type table<string, flemma.tools.ToolDefinition>
local tools = {}

---Store a single tool definition
---@param name string The tool name
---@param definition flemma.tools.ToolDefinition The tool definition
function M.define(name, definition)
  local loader = require("flemma.loader")
  if loader.is_module_path(name) then
    error(string.format("flemma: tool name '%s' must not contain dots (dots indicate module paths)", name), 2)
  end
  if tools[name] then
    vim.notify(
      string.format("flemma: tool '%s' redefined (previously registered, now overwritten)", name),
      vim.log.levels.WARN
    )
  end
  tools[name] = definition
end

---Get a tool definition by name
---@param name string The tool name
---@return flemma.tools.ToolDefinition|nil definition The tool definition, or nil if not found
function M.get(name)
  return tools[name]
end

---Get all registered tools (excludes disabled tools by default)
---@param opts? { include_disabled: boolean }
---@return table<string, flemma.tools.ToolDefinition> tools A copy of matching tool definitions
function M.get_all(opts)
  opts = opts or {}
  if opts.include_disabled then
    return vim.deepcopy(tools)
  end
  local result = {}
  for name, def in pairs(tools) do
    if def.enabled ~= false then
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
