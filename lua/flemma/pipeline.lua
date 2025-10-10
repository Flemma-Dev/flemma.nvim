local parser = require("flemma.parser")
local evaluator = require("flemma.evaluator")
local ast_to_parts = require("flemma.ast_to_parts")

local M = {}

--- Run full pipeline for given buffer lines and context
--- Returns:
---  - prompt: { history=[{role, parts, content}], system=string|nil } canonical roles
---  - evaluated: evaluator output for debug/use
---  - warnings: file warnings
function M.run(lines, context)
  local doc = parser.parse_lines(lines)
  local evaluated, warnings = evaluator.evaluate(doc, context or {})
  
  local history = {}
  local system = nil

  for _, msg in ipairs(evaluated.messages) do
    local role = nil
    if msg.role == "You" then 
      role = "user"
    elseif msg.role == "Assistant" then 
      role = "assistant"
    elseif msg.role == "System" then
      local parts = ast_to_parts.to_generic_parts(msg.parts)
      local sys_text = {}
      for _, p in ipairs(parts) do
        if p.kind == "text" or p.kind == "text_file" then 
          table.insert(sys_text, p.text or "") 
        end
      end
      system = vim.trim(table.concat(sys_text, "\n"))
    end

    if role then
      table.insert(history, {
        role = role,
        parts = ast_to_parts.to_generic_parts(msg.parts),
        content = nil,
      })
    end
  end

  return { history = history, system = system }, evaluated, warnings
end

return M
