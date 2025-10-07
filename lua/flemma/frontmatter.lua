--- Frontmatter handling for Flemma chat files
local M = {}

local eval = require("flemma.eval")
local context_util = require("flemma.context")

-- Parse frontmatter from lines
function M.parse(lines)
  if not lines[1] or not lines[1]:match("^```lua%s*$") then
    return nil, lines
  end

  local frontmatter = {}
  local content = {}
  local in_frontmatter = true
  local start_idx = 2

  for i = 2, #lines do
    if lines[i]:match("^```%s*$") then
      in_frontmatter = false
      start_idx = i + 1
      break
    end
    table.insert(frontmatter, lines[i])
  end

  -- If we never found the closing ```, treat everything as content
  if in_frontmatter then
    return nil, lines
  end

  -- Collect remaining lines as content
  for i = start_idx, #lines do
    table.insert(content, lines[i])
  end

  return table.concat(frontmatter, "\n"), content
end

---Execute frontmatter code in a safe environment
---
---Returns a context object (clone of the input context) extended with
---user-defined variables from the frontmatter code.
---
---@param code string The Lua code from frontmatter
---@param context Context The shared context object
---@return Context exec_context A context object with user-defined variables added
function M.execute(code, context)
  -- Start with a cloned context (or empty table if no context)
  local exec_context = context_util.clone(context)

  -- If no code, return the cloned context as-is
  if not code then
    return exec_context
  end

  -- Create a base safe environment and merge in the context
  local env_for_frontmatter = eval.create_safe_env()

  -- Add all context fields to the execution environment
  for k, v in pairs(exec_context) do
    env_for_frontmatter[k] = v
  end

  -- Execute and get user-defined globals
  local user_globals = eval.execute_safe(code, env_for_frontmatter)

  -- Add user-defined variables to the execution context
  for k, v in pairs(user_globals) do
    exec_context[k] = v
  end

  return exec_context
end

return M
