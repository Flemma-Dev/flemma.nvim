--- Lua parser for code blocks
--- Executes Lua code and extracts global variables
---@class flemma.codeblock.parsers.Lua
local M = {}

local config = require("flemma.config")
local eval = require("flemma.templating.eval")
local templating = require("flemma.templating")

---Parse Lua code and return global variables as a table.
---When bufnr is provided, frontmatter writes go directly to the config store's
---FRONTMATTER layer via a write proxy. The proxy IS flemma.opt — no separate
---resolve step needed.
---@param code string The Lua code to execute
---@param context? flemma.Context Optional context with __filename, etc.
---@param bufnr? integer Buffer number for config store writes
---@return table<string, any> variables Table of global variables defined in the code
function M.parse(code, context, bufnr)
  local env = templating.from_context(context)

  -- Inject flemma.opt into sandbox env before execute_frontmatter.
  -- When bufnr is available, use a config write proxy that records ops
  -- directly in the store. The layer is already cleared by the caller.
  if bufnr then
    local writer = config.writer(bufnr, config.LAYERS.FRONTMATTER)
    env.flemma = { opt = writer }
  else
    env.flemma = { opt = {} }
  end

  local user_globals = eval.execute_frontmatter(code, env)

  -- Safety net: ensure flemma doesn't leak to returned globals
  user_globals.flemma = nil

  -- Run coerce transforms on frontmatter ops (e.g., $preset expansion)
  if bufnr then
    config.coerce_frontmatter(bufnr)
  end

  return user_globals
end

return M
