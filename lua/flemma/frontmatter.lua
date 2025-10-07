--- Frontmatter handling for Flemma chat files
local M = {}

local eval = require("flemma.eval")
local context_util = require("flemma.context")
local parsers_registry = require("flemma.frontmatter.parsers")

-- Register built-in parsers
parsers_registry.register("lua", require("flemma.frontmatter.parsers.lua").parse)
parsers_registry.register("json", require("flemma.frontmatter.parsers.json").parse)

-- Parse frontmatter from lines
-- Returns: (language, code, content) or (nil, nil, lines)
function M.parse(lines)
  if not lines[1] then
    return nil, nil, lines
  end

  -- Extract language identifier from opening fence
  local language = lines[1]:match("^```(%w+)%s*$")
  if not language then
    return nil, nil, lines
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
    return nil, nil, lines
  end

  -- Collect remaining lines as content
  for i = start_idx, #lines do
    table.insert(content, lines[i])
  end

  return language, table.concat(frontmatter, "\n"), content
end

---Execute frontmatter code in a safe environment
---
---Returns a context object (clone of the input context) extended with
---user-defined variables from the frontmatter code.
---
---@param language string The language identifier (e.g., "lua", "json")
---@param code string The frontmatter code
---@param context Context The shared context object
---@return Context exec_context A context object with user-defined variables added
function M.execute(language, code, context)
  -- Start with a cloned context (or empty table if no context)
  local exec_context = context_util.clone(context)

  -- If no code, return the cloned context as-is
  if not code then
    return exec_context
  end

  -- Get the appropriate parser for the language
  local parser = parsers_registry.get(language)
  if not parser then
    error(
      string.format(
        "Unsupported frontmatter language '%s'. Supported: %s",
        language,
        table.concat(parsers_registry.supported_languages(), ", ")
      )
    )
  end

  -- Parse the frontmatter code using the language-specific parser
  local frontmatter_vars = parser(code, exec_context)

  -- Add parsed variables to the execution context
  for k, v in pairs(frontmatter_vars) do
    exec_context[k] = v
  end

  return exec_context
end

return M
