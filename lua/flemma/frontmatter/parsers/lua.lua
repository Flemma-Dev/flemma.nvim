--- Lua parser for frontmatter
--- Executes Lua code and extracts global variables
local M = {}

local eval = require("flemma.eval")

---Parse Lua code and return global variables as a table
---@param code string The Lua code to execute
---@param context table Optional context with __filename, etc.
---@return table variables Table of global variables defined in the code
function M.parse(code, context)
  -- Create a base safe environment
  local env = eval.create_safe_env()

  -- Add context fields to the execution environment
  if context then
    for k, v in pairs(context) do
      env[k] = v
    end
  end

  -- Execute and get user-defined globals
  local user_globals = eval.execute_safe(code, env)

  return user_globals
end

return M
