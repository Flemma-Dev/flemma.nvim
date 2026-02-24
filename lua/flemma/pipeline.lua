local processor = require("flemma.processor")
local ast = require("flemma.ast")

---@class flemma.Pipeline
local M = {}

---@class flemma.pipeline.UnresolvedTool
---@field id string
---@field name string
---@field position flemma.ast.Position|nil

--- Validate that all tool_uses have matching tool_results.
--- Operates on the AST directly so positions come from the source of truth
--- rather than being threaded through intermediate representations.
---@param doc flemma.ast.DocumentNode
---@return flemma.pipeline.UnresolvedTool[]
local function validate_tool_results(doc)
  local pending_tool_uses = {}

  for _, msg in ipairs(doc.messages) do
    for _, seg in ipairs(msg.segments) do
      if seg.kind == "tool_use" then
        pending_tool_uses[seg.id] = {
          id = seg.id,
          name = seg.name,
          position = seg.position,
        }
      elseif seg.kind == "tool_result" then
        -- Only clear when this is a resolved result (no status), not a flemma:tool placeholder
        if not seg.status then
          pending_tool_uses[seg.tool_use_id] = nil
        end
      end
    end
  end

  local unresolved = {}
  for _, tool in pairs(pending_tool_uses) do
    table.insert(unresolved, tool)
  end
  return unresolved
end

--- Process aborted parts in evaluated message parts.
--- When keep is true, converts aborted parts to text (for the LLM to see).
--- When keep is false, drops aborted parts entirely.
--- Also strips trailing whitespace-only text parts left behind after removal.
---@param parts flemma.processor.EvaluatedPart[]
---@param keep boolean Whether to convert aborted parts to text (true) or drop them (false)
---@return flemma.processor.EvaluatedPart[]
local function resolve_aborted_parts(parts, keep)
  local result = {}
  for _, part in ipairs(parts) do
    if part.kind == "aborted" then
      if keep then
        table.insert(result, { kind = "text", text = "<!-- " .. part.message .. " -->" })
      end
    else
      table.insert(result, part)
    end
  end
  -- Strip trailing whitespace-only text parts left behind after removal
  while #result > 0 do
    local last = result[#result]
    if last.kind == "text" and last.text:match("^%s*$") then
      result[#result] = nil
    else
      break
    end
  end
  return result
end

---@class flemma.pipeline.Prompt : flemma.provider.Prompt
---@field pending_tool_calls flemma.pipeline.UnresolvedTool[]
---@field opts flemma.opt.FrontmatterOpts|nil

--- Run full pipeline from a pre-parsed document and context.
--- If a pre-evaluated frontmatter result is provided, it is reused instead of
--- re-evaluating frontmatter code.
---@param doc flemma.ast.DocumentNode
---@param context flemma.Context|nil
---@param evaluated_frontmatter flemma.processor.EvaluatedFrontmatter|nil
---@return flemma.pipeline.Prompt prompt
---@return flemma.processor.EvaluatedResult evaluated
function M.run(doc, context, evaluated_frontmatter)
  local evaluated = processor.evaluate(doc, context, evaluated_frontmatter)

  local history = {}
  local system = nil
  local all_diagnostics = evaluated.diagnostics or {}
  local source_file = (context and type(context.get_filename) == "function" and context:get_filename()) or "N/A"

  -- First pass: collect messages and identify the last assistant index.
  -- Abort handling operates on evaluated parts (before to_generic_parts) because
  -- aborted parts are a processor-stage concept that to_generic_parts ignores.
  ---@type { role: string, evaluated_parts: flemma.processor.EvaluatedPart[] }[]
  local collected = {}
  local last_assistant_idx = nil

  for _, msg in ipairs(evaluated.messages) do
    if msg.role == "You" then
      table.insert(collected, { role = "user", evaluated_parts = msg.parts })
    elseif msg.role == "Assistant" then
      table.insert(collected, { role = "assistant", evaluated_parts = msg.parts })
      last_assistant_idx = #collected
    elseif msg.role == "System" then
      local parts, diags = ast.to_generic_parts(msg.parts, source_file)
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
  end

  -- Second pass: resolve aborted parts, then convert to generic parts.
  -- Historical assistant messages: always strip (LLM doesn't need old abort context).
  -- Last assistant message: strip when tool_use parts are present (the abort info is
  -- already in the tool_result errors, and trailing text after tool_use blocks violates
  -- Anthropic's API constraint). Preserve only for text-only messages so the LLM knows
  -- the response was truncated and can continue.
  for i, entry in ipairs(collected) do
    if entry.role == "assistant" then
      local keep_aborted = (i == last_assistant_idx)
      if keep_aborted then
        -- Last assistant: strip if message contains tool_use parts
        for _, part in ipairs(entry.evaluated_parts) do
          if part.kind == "tool_use" then
            keep_aborted = false
            break
          end
        end
      end
      entry.evaluated_parts = resolve_aborted_parts(entry.evaluated_parts, keep_aborted)
    end

    local parts, diags = ast.to_generic_parts(entry.evaluated_parts, source_file)
    for _, d in ipairs(diags) do
      table.insert(all_diagnostics, d)
    end
    table.insert(history, { role = entry.role, parts = parts })
  end

  -- Validate tool_use/tool_result matching
  local unresolved_tools = validate_tool_results(doc)
  for _, tool in ipairs(unresolved_tools) do
    table.insert(all_diagnostics, {
      type = "tool_use",
      severity = "warning",
      position = tool.position,
      error = string.format(
        "Tool call '%s' (%s) has no matching tool result. A synthetic 'No result provided' error response will be sent to the API.",
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
