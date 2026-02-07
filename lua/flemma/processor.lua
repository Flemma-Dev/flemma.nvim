local ctxutil = require("flemma.context")
local eval = require("flemma.eval")
local emittable_mod = require("flemma.emittable")
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
    local ok, json = pcall(vim.fn.json_encode, v)
    if ok then
      return json
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
---@field raw string
---@field mime_type string
---@field data string
---@field position? flemma.ast.Position

---@class flemma.processor.UnsupportedFilePart
---@field kind "unsupported_file"
---@field raw? string
---@field error? string
---@field position? flemma.ast.Position

---@alias flemma.processor.EvaluatedPart flemma.processor.TextPart|flemma.processor.ThinkingPart|flemma.processor.FilePart|flemma.processor.UnsupportedFilePart|flemma.processor.ToolUsePart|flemma.processor.ToolResultPart

---@class flemma.processor.EvaluatedMessage
---@field role "You"|"Assistant"|"System"
---@field parts flemma.processor.EvaluatedPart[]
---@field position flemma.ast.Position

---@class flemma.processor.EvaluatedResult
---@field messages flemma.processor.EvaluatedMessage[]
---@field diagnostics flemma.ast.Diagnostic[]

--- Evaluate a document AST.
---@param doc flemma.ast.DocumentNode
---@param base_context flemma.Context|nil
---@return flemma.processor.EvaluatedResult
function M.evaluate(doc, base_context)
  -- Use doc.errors as the unified diagnostics array (parser may have populated it)
  local diagnostics = doc.errors or {}
  local context = ctxutil.clone(base_context)

  -- 1) Frontmatter execution using the parser registry
  if doc.frontmatter then
    local fm = doc.frontmatter ---@cast fm -nil
    local parser = codeblock_parsers.get(fm.language)

    if parser then
      local ok, result = pcall(parser, fm.code, context)
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
        -- Include signature if present (for provider state preservation, e.g., Vertex AI)
        table.insert(parts, { kind = "thinking", content = seg.content, signature = seg.signature })
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
        elseif emittable_mod.is_emittable(result) then
          -- Emittable result: create EmitContext and collect parts
          local emit_ctx = emittable_mod.EmitContext.new({
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
        table.insert(parts, {
          kind = "tool_result",
          tool_use_id = seg.tool_use_id,
          content = seg.content,
          is_error = seg.is_error,
        })
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
  }
end

return M
