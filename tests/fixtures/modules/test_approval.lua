---@class test.fixtures.modules.TestApproval
local M = {}

M.approval = {
  ---@param tool_name string
  ---@param _input table
  ---@param _context flemma.tools.AutoApproveContext
  ---@return flemma.tools.ApprovalResult|nil
  resolve = function(tool_name, _input, _context)
    if tool_name == "test_tool" then
      return "approve"
    end
    return nil
  end,
  priority = 75,
  description = "Test approval fixture",
}

return M
