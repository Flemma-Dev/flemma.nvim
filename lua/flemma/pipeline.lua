local processor = require("flemma.processor")
local ast = require("flemma.ast")
local roles = require("flemma.utilities.roles")

---@class flemma.Pipeline
local M = {}

---@class flemma.pipeline.UnresolvedTool
---@field id string
---@field name string
---@field position flemma.ast.Position|nil

--- Validate that all tool_uses have matching resolved tool_results.
--- A tool_result with a non-nil status (e.g., pending, approved) is treated as
--- unresolved — only status=nil means the result is final.
---@param doc flemma.ast.DocumentNode
---@return flemma.pipeline.UnresolvedTool[]
local function validate_tool_results(doc)
  local siblings = ast.build_tool_sibling_table(doc)

  local unresolved = {}
  for _, sibling in pairs(siblings) do
    if sibling.use then
      if not sibling.result or sibling.result.status then
        table.insert(unresolved, {
          id = sibling.use.id,
          name = sibling.use.name,
          position = sibling.use.position,
        })
      end
    end
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
---@field bufnr integer Buffer number for per-buffer config resolution

--- Run full pipeline from a pre-parsed document and context.
--- If a pre-evaluated frontmatter result is provided, it is reused instead of
--- re-evaluating frontmatter code.
---@param doc flemma.ast.DocumentNode
---@param context flemma.Context|nil
---@param opts flemma.processor.EvaluateOpts
---@return flemma.pipeline.Prompt prompt
---@return flemma.processor.EvaluatedResult evaluated
function M.run(doc, context, opts)
  local evaluated = processor.evaluate(doc, context, opts)

  local history = {}
  local system = nil
  local all_diagnostics = evaluated.diagnostics or {}
  local source_file = (context and type(context.get_filename) == "function" and context:get_filename()) or "N/A"

  -- First pass: collect messages and identify the last assistant index.
  -- Abort handling operates on evaluated parts (before to_generic_parts) because
  -- aborted parts are a processor-stage concept that to_generic_parts ignores.
  ---@type { role: string, evaluated_parts: flemma.processor.EvaluatedPart[] }[]
  local collected = {}

  for _, msg in ipairs(evaluated.messages) do
    if roles.is_user(msg.role) then
      table.insert(collected, { role = roles.to_key(msg.role), evaluated_parts = msg.parts })
    elseif msg.role == roles.ASSISTANT then
      table.insert(collected, { role = roles.to_key(msg.role), evaluated_parts = msg.parts })
    elseif msg.role == roles.SYSTEM then
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

  -- Build tool_use_id -> name index for enriching tool_result parts.
  -- Chat Completions providers (Moonshot, etc.) require a `name` field on tool result
  -- messages. Rather than searching backward through history at request time, we resolve
  -- the name here in the pipeline where we have the full document.
  local tool_use_index = ast.build_tool_use_index(doc)

  -- Second pass: resolve aborted parts, then convert to generic parts.
  -- Keep abort markers in ALL text-only assistant messages so the LLM sees that
  -- previous responses were interrupted, and so the conversation prefix stays stable
  -- across requests (avoiding prompt-cache busting).
  -- Strip when tool_use parts are present — trailing text after tool_use blocks
  -- violates the Anthropic API constraint, and the abort info is already conveyed
  -- through the status=aborted tool_result placeholders.
  for _, entry in ipairs(collected) do
    if entry.role == "assistant" then
      local keep_aborted = true
      for _, part in ipairs(entry.evaluated_parts) do
        if part.kind == "tool_use" then
          keep_aborted = false
          break
        end
      end
      entry.evaluated_parts = resolve_aborted_parts(entry.evaluated_parts, keep_aborted)
    end

    local parts, diags = ast.to_generic_parts(entry.evaluated_parts, source_file)
    for _, d in ipairs(diags) do
      table.insert(all_diagnostics, d)
    end

    -- Enrich tool_result parts with the tool name from the matching tool_use
    for _, part in ipairs(parts) do
      if part.kind == "tool_result" and not part.name then
        local info = tool_use_index[part.tool_use_id]
        if info then
          part.name = info.name
        end
      end
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

  return { history = history, system = system, pending_tool_calls = unresolved_tools, bufnr = opts.bufnr }, evaluated
end

return M
