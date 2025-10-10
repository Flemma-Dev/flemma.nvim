local parser = require("flemma.parser")
local processor = require("flemma.processor")
local ast = require("flemma.ast")

local M = {}

--- Run full pipeline for given buffer lines and context
--- Returns:
---  - prompt: { history=[{role, parts, content}], system=string|nil } canonical roles
---  - evaluated: processor output with diagnostics array
function M.run(lines, context)
  local doc = parser.parse_lines(lines)
  local evaluated = processor.evaluate(doc, context or {})

  local history = {}
  local system = nil

  for _, msg in ipairs(evaluated.messages) do
    local role = nil
    if msg.role == "You" then
      role = "user"
    elseif msg.role == "Assistant" then
      role = "assistant"
    elseif msg.role == "System" then
      local parts = ast.to_generic_parts(msg.parts)
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
        parts = ast.to_generic_parts(msg.parts),
        content = nil,
      })
    end
  end

  return { history = history, system = system }, evaluated
end

return M
