local parser = require("flemma.parser")
local processor = require("flemma.processor")
local ast = require("flemma.ast")

local M = {}

--- Run full pipeline for given buffer lines and context
--- Returns:
---  - prompt: { history=[{role, parts, content}], system=string|nil } canonical roles
---  - evaluated: processor output with diagnostics array (including diagnostics from to_generic_parts)
function M.run(lines, context)
  local doc = parser.parse_lines(lines)
  local evaluated = processor.evaluate(doc, context or {})

  local history = {}
  local system = nil
  local all_diagnostics = evaluated.diagnostics or {}
  local source_file = (context and type(context.get_filename) == "function" and context:get_filename()) or "N/A"

  for _, msg in ipairs(evaluated.messages) do
    local role = nil
    if msg.role == "You" then
      role = "user"
    elseif msg.role == "Assistant" then
      role = "assistant"
    elseif msg.role == "System" then
      local parts, diags = ast.to_generic_parts(msg.parts, source_file)
      -- Merge diagnostics from to_generic_parts
      for _, d in ipairs(diags) do
        table.insert(all_diagnostics, d)
      end
      local sys_text = {}
      for _, p in ipairs(parts) do
        if p.kind == "text" or p.kind == "text_file" then
          table.insert(sys_text, p.text or "")
        end
      end
      system = vim.trim(table.concat(sys_text, "\n"))
    end

    if role then
      local parts, diags = ast.to_generic_parts(msg.parts, source_file)
      -- Merge diagnostics from to_generic_parts
      for _, d in ipairs(diags) do
        table.insert(all_diagnostics, d)
      end
      table.insert(history, {
        role = role,
        parts = parts,
        content = nil,
      })
    end
  end

  -- Update evaluated with merged diagnostics
  evaluated.diagnostics = all_diagnostics

  return { history = history, system = system }, evaluated
end

return M
