--- Frontmatter handling for Flemma chat files
local M = {}

local eval = require("flemma.eval")

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
---@param code string The Lua code from frontmatter
---@param context Context The shared context object with __filename and __include_stack
---@return table environment The environment with frontmatter variables
function M.execute(code, context)
  if not code then
    return {}
  end

  -- Create a base environment for frontmatter execution
  local env_for_frontmatter = eval.create_safe_env()

  -- Explicitly set required fields from context for include() support
  if context then
    env_for_frontmatter.__filename = context.__filename
    env_for_frontmatter.__include_stack = context.__include_stack
      or (context.__filename and { context.__filename } or nil)
  end

  return eval.execute_safe(code, env_for_frontmatter)
end

return M
