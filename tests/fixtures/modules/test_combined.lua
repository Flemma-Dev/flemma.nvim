---@class test.fixtures.modules.TestCombined
local M = {}

M.definitions = {
  {
    name = "combo_tool",
    description = "Tool from combined module",
    input_schema = {
      type = "object",
      properties = {
        value = { type = "string" },
      },
    },
    execute = function(_input, _context)
      return { success = true, output = "ok" }
    end,
  },
}

M.approval = {
  ---@param tool_name string
  ---@return flemma.tools.ApprovalResult|nil
  resolve = function(tool_name)
    if tool_name == "combo_tool" then
      return "approve"
    end
    return nil
  end,
  priority = 60,
  description = "Combined module approval",
}

return M
