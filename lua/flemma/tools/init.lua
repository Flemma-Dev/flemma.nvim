--- Tool calling support for Flemma
--- Manages tool registry and built-in tool definitions
local M = {}

local registry = require("flemma.tools.registry")

local builtin_tools = {
  "flemma.tools.definitions.calculator",
  "flemma.tools.definitions.bash",
}

---Setup tool registry with built-in tools
function M.setup()
  for _, module_name in ipairs(builtin_tools) do
    local tool_module = require(module_name)
    registry.register(tool_module.definition.name, tool_module.definition)
  end
end

--- Build a tool description with output_schema information merged in
--- This creates a description that helps the model understand what the tool returns
---@param tool table The tool definition with name, description, input_schema, and optional output_schema
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

M.register = registry.register
M.get = registry.get
M.get_all = registry.get_all
M.clear = registry.clear
M.count = registry.count
M.is_executable = registry.is_executable
M.get_executor = registry.get_executor

return M
