local processor = require("flemma.processor")
local ast = require("flemma.ast")

---@class flemma.Pipeline
local M = {}

---@class flemma.pipeline.UnresolvedTool
---@field id string
---@field name string

--- Validate that all tool_uses have matching tool_results
---@param history flemma.provider.HistoryMessage[] Array of messages with parts
---@return flemma.pipeline.UnresolvedTool[]
local function validate_tool_results(history)
  local pending_tool_uses = {}

  for _, msg in ipairs(history) do
    for _, part in ipairs(msg.parts or {}) do
      if part.kind == "tool_use" then
        pending_tool_uses[part.id] = {
          id = part.id,
          name = part.name,
        }
      elseif part.kind == "tool_result" then
        pending_tool_uses[part.tool_use_id] = nil
      end
    end
  end

  local unresolved = {}
  for _, tool in pairs(pending_tool_uses) do
    table.insert(unresolved, tool)
  end
  return unresolved
end

---@class flemma.pipeline.Prompt : flemma.provider.Prompt
---@field pending_tool_calls flemma.pipeline.UnresolvedTool[]
---@field opts flemma.opt.ResolvedOpts|nil

--- Run full pipeline from a pre-parsed document and context
---@param doc flemma.ast.DocumentNode
---@param context flemma.Context|nil
---@return flemma.pipeline.Prompt prompt
---@return flemma.processor.EvaluatedResult evaluated
function M.run(doc, context)
  local evaluated = processor.evaluate(doc, context)

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
      })
    end
  end

  -- Validate tool_use/tool_result matching
  local unresolved_tools = validate_tool_results(history)
  for _, tool in ipairs(unresolved_tools) do
    table.insert(all_diagnostics, {
      type = "tool_use",
      severity = "warning",
      error = string.format(
        "Tool call '%s' (%s) has no matching tool result. Add a **Tool Result:** block with the tool's output.",
        tool.name,
        tool.id
      ),
    })
  end

  -- Update evaluated with merged diagnostics
  evaluated.diagnostics = all_diagnostics

  return { history = history, system = system, pending_tool_calls = unresolved_tools, opts = evaluated.opts }, evaluated
end

return M
