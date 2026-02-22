--- Lua parser for code blocks
--- Executes Lua code and extracts global variables
---@class flemma.codeblock.parsers.Lua
local M = {}

local eval = require("flemma.eval")
local ctxutil = require("flemma.context")
local opt_module = require("flemma.buffer.opt")

---Parse Lua code and return global variables as a table
---@param code string The Lua code to execute
---@param context? flemma.Context Optional context with __filename, etc.
---@return table<string, any> variables Table of global variables defined in the code
function M.parse(code, context)
  local env = ctxutil.to_eval_env(context or {})

  -- Inject flemma.opt into sandbox env before execute_safe
  -- This makes it part of initial_keys, so it won't leak to user_globals
  local opt_proxy, resolve = opt_module.create()
  env.flemma = { opt = opt_proxy }

  local user_globals = eval.execute_safe(code, env)

  -- Safety net: ensure flemma doesn't leak to returned globals
  user_globals.flemma = nil

  -- Store frontmatter opts on context
  if context and type(context) == "table" then
    context.__opts = resolve()
  end

  return user_globals
end

return M
