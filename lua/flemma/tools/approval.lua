--- Tool execution approval resolver
--- Determines whether a tool call should be auto-approved, require user approval,
--- or be denied entirely based on the configured auto_approve policy.
---@class flemma.tools.Approval
local M = {}

local state = require("flemma.state")
local log = require("flemma.logging")

---@alias flemma.tools.ApprovalResult "approve"|"require_approval"|"deny"

---Resolve whether a tool execution should be auto-approved, require approval, or be denied.
---@param tool_name string
---@param input table<string, any>
---@param context flemma.config.AutoApproveContext
---@return flemma.tools.ApprovalResult
function M.resolve(tool_name, input, context)
  local config = state.get_config()
  local auto_approve = config.tools and config.tools.auto_approve

  if auto_approve == nil then
    return "require_approval"
  end

  if type(auto_approve) == "table" then
    if vim.tbl_contains(auto_approve, tool_name) then
      return "approve"
    end
    return "require_approval"
  end

  if type(auto_approve) == "function" then
    local ok, result = pcall(auto_approve, tool_name, input, context)
    if not ok then
      log.warn("approval: auto_approve function error: " .. tostring(result))
      return "require_approval"
    end
    if result == true then
      return "approve"
    end
    if result == "deny" then
      return "deny"
    end
    return "require_approval"
  end

  log.warn("approval: unexpected auto_approve type: " .. type(auto_approve))
  return "require_approval"
end

return M
