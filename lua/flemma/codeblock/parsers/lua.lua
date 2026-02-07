--- Lua parser for code blocks
--- Executes Lua code and extracts global variables
---@class flemma.codeblock.parsers.Lua
local M = {}

local eval = require("flemma.eval")
local ctxutil = require("flemma.context")

---Parse Lua code and return global variables as a table
---@param code string The Lua code to execute
---@param context? table<string, any> Optional context with __filename, etc.
---@return table<string, any> variables Table of global variables defined in the code
function M.parse(code, context)
  local env = ctxutil.to_eval_env(context or {})
  local user_globals = eval.execute_safe(code, env)
  return user_globals
end

return M
