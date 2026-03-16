--- Iterator helper populator for the Flemma template environment.
--- Provides values() and each() for concise array iteration in templates.
---@class flemma.templating.builtins.Iterators : flemma.templating.Populator
local M = {}

M.name = "iterators"
M.priority = 200

---Populate the environment with iterator helper functions.
---@param env table
function M.populate(env)
  ---Iterate over array values without index.
  ---Usage: {% for item in values(items) do %}
  ---@param t table Array to iterate
  ---@return fun(): any iterator
  env.values = function(t)
    local i = 0
    return function()
      i = i + 1
      if t[i] ~= nil then
        return t[i]
      end
    end
  end

  ---Iterate over array values with loop metadata context.
  ---Usage: {% for item, loop in each(items) do %}
  ---The loop table provides: index (1-based), index0 (0-based), first, last, length.
  ---@param t table Array to iterate
  ---@return fun(): any|nil, table|nil iterator
  env.each = function(t)
    local i = 0
    local n = #t
    local ctx = { length = n }
    return function()
      i = i + 1
      if i <= n then
        ctx.index = i
        ctx.index0 = i - 1
        ctx.first = (i == 1)
        ctx.last = (i == n)
        return t[i], ctx
      end
    end
  end
end

return M
