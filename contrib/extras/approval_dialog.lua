--- Tool approval confirmation dialog — debug/demo helper.
--- Subscribes to tool:approval-required and shows vim.fn.confirm() for each
--- pending tool. Approve or deny tools directly from the dialog.
---
--- Enable:   :luafile contrib/extras/approval_dialog.lua
--- Disable:  :lua _G._flemma_approval_teardown()

vim.opt.rtp:prepend(".")

local hooks = require("flemma.hooks")
local tools = require("flemma.tools")

if _G._flemma_approval_teardown then
  _G._flemma_approval_teardown()
end

---@param input table<string, any>
---@return string
local function format_input(input)
  local lines = {}
  for key, value in pairs(input) do
    local display = type(value) == "string" and value or vim.inspect(value)
    if #display > 120 then
      display = display:sub(1, 117) .. "..."
    end
    lines[#lines + 1] = "  " .. key .. ": " .. display
  end
  return table.concat(lines, "\n")
end

local subscription = hooks.on("tool:approval-required", function(data)
  for _, tool in ipairs(data.tools) do
    if not vim.api.nvim_buf_is_valid(data.bufnr) then
      return
    end

    local message = "Tool: " .. tool.tool_name .. "\n" .. format_input(tool.input)
    local choice = vim.fn.confirm(message, "&Approve\n&Reject", 2, "Question")

    if not vim.api.nvim_buf_is_valid(data.bufnr) then
      return
    end

    if choice == 1 then
      tools.approve(data.bufnr, tool.tool_id)
    else
      tools.reject(data.bufnr, tool.tool_id)
    end
  end
end)

_G._flemma_approval_teardown = function()
  subscription:off()
  _G._flemma_approval_teardown = nil
  print("approval dialog: disabled")
end

print("approval dialog: enabled (run _G._flemma_approval_teardown() to disable)")
