local ctxutil = require("flemma.context")
local eval = require("flemma.eval")
local emittable = require("flemma.emittable")
local json = require("flemma.json")
local codeblock_parsers = require("flemma.codeblock.parsers")

---@class flemma.Processor
local M = {}

---@param v any
---@return string
local function to_text(v)
  if v == nil then
    return ""
  end
  if type(v) == "table" then
    local ok, encoded = pcall(json.encode, v)
    if ok then
      return encoded
    end
  end
  return tostring(v)
end

-- Part types shared with ast.lua (canonical definitions live there)
---@alias flemma.processor.TextPart flemma.ast.GenericTextPart
---@alias flemma.processor.ThinkingPart flemma.ast.GenericThinkingPart
---@alias flemma.processor.ToolUsePart flemma.ast.GenericToolUsePart
---@alias flemma.processor.ToolResultPart flemma.ast.GenericToolResultPart

-- Part types unique to the processor stage (pre-conversion)
---@class flemma.processor.FilePart
---@field kind "file"
---@field filename string
---@field mime_type string
---@field data string
---@field position? flemma.ast.Position

---@alias flemma.processor.EvaluatedPart flemma.processor.TextPart|flemma.processor.ThinkingPart|flemma.processor.FilePart|flemma.processor.ToolUsePart|flemma.processor.ToolResultPart

---@class flemma.processor.EvaluatedMessage
---@field role "You"|"Assistant"|"System"
---@field parts flemma.processor.EvaluatedPart[]
---@field position flemma.ast.Position

---@class flemma.processor.EvaluatedResult
---@field messages flemma.processor.EvaluatedMessage[]
---@field diagnostics flemma.ast.Diagnostic[]
---@field opts flemma.opt.FrontmatterOpts|nil

---@class flemma.processor.EvaluatedFrontmatter
---@field context flemma.Context Evaluated context with __opts and user variables set
---@field diagnostics flemma.ast.Diagnostic[] Frontmatter-specific diagnostics

---Evaluate frontmatter and return the resulting context (with __opts and user variables set).
---@param doc flemma.ast.DocumentNode
---@param base_context flemma.Context|nil
---@return flemma.Context context
---@return flemma.ast.Diagnostic[] diagnostics Frontmatter-specific diagnostics
local function evaluate_frontmatter_internal(doc, base_context)
  local context = ctxutil.clone(base_context)
  local diagnostics = {}

  if doc.frontmatter then
    local fm = doc.frontmatter ---@cast fm -nil
    local fm_parser = codeblock_parsers.get(fm.language)

    if fm_parser then
      local ok, result = pcall(fm_parser, fm.code, context)
      if ok then
        if type(result) == "table" then
          context = ctxutil.extend(context, result)
        else
          table.insert(diagnostics, {
            type = "frontmatter",
            severity = "warning",
            language = fm.language,
            error = string.format("Frontmatter must be an object, got %s", type(result)),
            position = fm.position,
            source_file = context:get_filename() or "N/A",
          })
        end
      else
        table.insert(diagnostics, {
          type = "frontmatter",
          severity = "error",
          language = fm.language,
          error = tostring(result),
          position = fm.position,
          source_file = context:get_filename() or "N/A",
        })
      end
    else
      table.insert(diagnostics, {
        type = "frontmatter",
        severity = "error",
        language = fm.language,
        error = "Unsupported frontmatter language: " .. tostring(fm.language),
        position = fm.position,
        source_file = context:get_filename() or "N/A",
      })
    end
  end

  return context, diagnostics
end

---Evaluate frontmatter from a parsed document.
---Returns the evaluated context (with __opts and user variables) and any diagnostics.
---@param doc flemma.ast.DocumentNode
---@param base_context flemma.Context|nil
---@return flemma.processor.EvaluatedFrontmatter
function M.evaluate_frontmatter(doc, base_context)
  local context, diagnostics = evaluate_frontmatter_internal(doc, base_context)
  return { context = context, diagnostics = diagnostics }
end

---Convenience: parse buffer + evaluate frontmatter in one call.
---For callers that start from a bufnr (e.g., status.lua).
---@param bufnr integer
---@return flemma.processor.EvaluatedFrontmatter
function M.evaluate_buffer_frontmatter(bufnr)
  local parser = require("flemma.parser")
  local doc = parser.get_parsed_document(bufnr)
  return M.evaluate_frontmatter(doc, ctxutil.from_buffer(bufnr))
end

--- Evaluate a document AST.
--- If a pre-evaluated frontmatter result is provided, it is reused instead of
--- re-evaluating frontmatter code. This allows callers to evaluate frontmatter
--- once and thread the result through multiple consumers.
---@param doc flemma.ast.DocumentNode
---@param base_context flemma.Context|nil
---@param evaluated_frontmatter flemma.processor.EvaluatedFrontmatter|nil
---@return flemma.processor.EvaluatedResult
function M.evaluate(doc, base_context, evaluated_frontmatter)
  local context, fm_diagnostics
  if evaluated_frontmatter then
    context = evaluated_frontmatter.context
    fm_diagnostics = evaluated_frontmatter.diagnostics
  else
    context, fm_diagnostics = evaluate_frontmatter_internal(doc, base_context)
  end

  -- Merge parser errors with frontmatter diagnostics
  local diagnostics = doc.errors or {}
  for _, d in ipairs(fm_diagnostics) do
    table.insert(diagnostics, d)
  end

  -- 2) Evaluate messages
  local evaluated_messages = {}
  local env = ctxutil.to_eval_env(context)

  for _, msg in ipairs(doc.messages or {}) do
    local parts = {}

    for _, seg in ipairs(msg.segments or {}) do
      if seg.kind == "text" then
        if seg.value and #seg.value > 0 then
          table.insert(parts, { kind = "text", text = seg.value })
        end
      elseif seg.kind == "thinking" then
        -- Preserve thinking nodes - providers can choose to filter them
        -- Include signature if present (for provider state preservation)
        -- Include redacted flag for encrypted thinking blocks
        table.insert(parts, {
          kind = "thinking",
          content = seg.content,
          signature = seg.signature, -- table { value, provider } or nil
          redacted = seg.redacted,
        })
      elseif seg.kind == "expression" then
        local ok, result = pcall(eval.eval_expression, seg.code, env)
        if not ok then
          -- Check if the error is a structured table (e.g. from include())
          if type(result) == "table" and result.type then
            table.insert(diagnostics, {
              type = result.type,
              severity = "warning",
              filename = result.filename,
              raw = result.raw,
              error = result.error or tostring(result),
              position = seg.position,
              message_role = msg.role,
              source_file = context:get_filename() or "N/A",
            })
          else
            table.insert(diagnostics, {
              type = "expression",
              severity = "warning",
              expression = seg.code,
              error = tostring(result),
              position = seg.position,
              message_role = msg.role,
              source_file = context:get_filename() or "N/A",
            })
          end
          -- Keep original expression text in output
          table.insert(parts, { kind = "text", text = "{{" .. (seg.code or "") .. "}}" })
        elseif emittable.is_emittable(result) then
          -- Emittable result: create EmitContext and collect parts
          local emit_ctx = emittable.EmitContext.new({
            position = seg.position,
            diagnostics = diagnostics,
            source_file = context:get_filename() or "N/A",
          })
          local emit_ok, emit_err = pcall(result.emit, result, emit_ctx)
          if emit_ok then
            for _, ep in ipairs(emit_ctx.parts) do
              table.insert(parts, ep)
            end
          else
            table.insert(diagnostics, {
              type = "expression",
              severity = "warning",
              expression = seg.code,
              error = "Error during emit: " .. tostring(emit_err),
              position = seg.position,
              message_role = msg.role,
              source_file = context:get_filename() or "N/A",
            })
            table.insert(parts, { kind = "text", text = "{{" .. (seg.code or "") .. "}}" })
          end
        else
          local str_result = to_text(result)
          if str_result and #str_result > 0 then
            table.insert(parts, { kind = "text", text = str_result })
          end
        end
      elseif seg.kind == "tool_use" then
        table.insert(parts, {
          kind = "tool_use",
          id = seg.id,
          name = seg.name,
          input = seg.input,
        })
      elseif seg.kind == "tool_result" then
        -- Skip flemma:tool placeholder blocks (they are not resolved results)
        if not seg.status then
          table.insert(parts, {
            kind = "tool_result",
            tool_use_id = seg.tool_use_id,
            content = seg.content,
            is_error = seg.is_error,
          })
        end
      end
    end

    table.insert(evaluated_messages, {
      role = msg.role,
      parts = parts,
      position = msg.position,
    })
  end

  return {
    messages = evaluated_messages,
    diagnostics = diagnostics,
    opts = context:get_opts(),
  }
end

return M
