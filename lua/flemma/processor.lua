local compiler = require("flemma.templating.compiler")
local ctxutil = require("flemma.context")
local eval = require("flemma.templating.eval")
local codeblock_parsers = require("flemma.codeblock.parsers")
local log = require("flemma.logging")
local parser = require("flemma.parser")
local symbols = require("flemma.symbols")

---@class flemma.Processor
local M = {}

--- Convert a pcall error into a diagnostic table.
---
--- Structured error tables (e.g. from include()) are used as-is with defaults
--- filled in. Plain errors are wrapped in a new diagnostic with the given fallback fields.
---@param err any Error value from pcall
---@param defaults table<string, any> Default fields (position, source_file, severity, etc.)
---@param fallback table<string, any> Extra fields for non-structured errors (type, expression, language, etc.)
---@return flemma.ast.Diagnostic
local function error_to_diagnostic(err, defaults, fallback)
  if type(err) == "table" and err.type then
    for k, v in pairs(defaults) do
      if err[k] == nil then
        err[k] = v
      end
    end
    return err
  end
  fallback.error = tostring(err)
  for k, v in pairs(defaults) do
    fallback[k] = v
  end
  return fallback
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

---@class flemma.processor.AbortedPart
---@field kind "aborted"
---@field message string

---@alias flemma.processor.EvaluatedPart flemma.processor.TextPart|flemma.processor.ThinkingPart|flemma.processor.FilePart|flemma.processor.ToolUsePart|flemma.processor.ToolResultPart|flemma.processor.AbortedPart

---@class flemma.processor.EvaluatedMessage
---@field role "You"|"Assistant"|"System"
---@field parts flemma.processor.EvaluatedPart[]
---@field position flemma.ast.Position

---@class flemma.processor.EvaluatedResult
---@field messages flemma.processor.EvaluatedMessage[]
---@field diagnostics flemma.ast.Diagnostic[]
---@field opts flemma.opt.FrontmatterOpts|nil

---@class flemma.processor.EvaluatedFrontmatter
---@field context flemma.Context Evaluated context with frontmatter opts and user variables set
---@field diagnostics flemma.ast.Diagnostic[] Frontmatter-specific diagnostics

---Evaluate frontmatter and return the resulting context (with frontmatter opts and user variables set).
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
        table.insert(
          diagnostics,
          error_to_diagnostic(result, {
            position = fm.position,
            source_file = context:get_filename() or "N/A",
            severity = "error",
          }, {
            type = "frontmatter",
            language = fm.language,
          })
        )
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
---Returns the evaluated context (with frontmatter opts and user variables) and any diagnostics.
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
  local doc = parser.get_parsed_document(bufnr)
  return M.evaluate_frontmatter(doc, ctxutil.from_buffer(bufnr))
end

--- Evaluate a document AST.
--- If a pre-evaluated frontmatter result is provided, it is reused instead of
--- re-evaluating frontmatter code. This allows callers to evaluate frontmatter
--- once and thread the result through multiple consumers.
---@class flemma.processor.EvaluateOpts
---@field evaluated_frontmatter? flemma.processor.EvaluatedFrontmatter Pre-evaluated frontmatter (skips re-evaluation)
---@field bufnr? integer Buffer number for context-aware expression evaluation

---@param doc flemma.ast.DocumentNode
---@param base_context flemma.Context|nil
---@param opts? flemma.processor.EvaluateOpts
---@return flemma.processor.EvaluatedResult
function M.evaluate(doc, base_context, opts)
  opts = opts or {}
  local context, fm_diagnostics
  if opts.evaluated_frontmatter then
    context = opts.evaluated_frontmatter.context
    fm_diagnostics = opts.evaluated_frontmatter.diagnostics
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
  local env = ctxutil.to_eval_env(context, opts.bufnr)
  eval.ensure_env(env)

  for _, msg in ipairs(doc.messages or {}) do
    local parts

    if msg.role == "Assistant" then
      -- @Assistant messages: pass-through, no template evaluation
      parts = {}
      for _, seg in ipairs(msg.segments or {}) do
        if seg.kind == "text" then
          if seg.value and #seg.value > 0 then
            table.insert(parts, { kind = "text", text = seg.value })
          end
        elseif seg.kind == "thinking" then
          table.insert(parts, {
            kind = "thinking",
            content = seg.content,
            signature = seg.signature,
            redacted = seg.redacted,
          })
        elseif seg.kind == "tool_use" then
          table.insert(parts, {
            kind = "tool_use",
            id = seg.id,
            name = seg.name,
            input = seg.input,
          })
        elseif seg.kind == "tool_result" then
          if not seg.status then
            table.insert(parts, {
              kind = "tool_result",
              tool_use_id = seg.tool_use_id,
              content = seg.content,
              is_error = seg.is_error,
            })
          end
        elseif seg.kind == "aborted" then
          table.insert(parts, { kind = "aborted", message = seg.message })
        end
      end
    else
      -- @System and @You: compile and execute via template engine
      log.trace("processor: compiling @" .. msg.role .. " message (" .. #(msg.segments or {}) .. " segments)")
      local compile_result = compiler.compile(msg.segments or {})
      local exec_parts, exec_diagnostics = compiler.execute(compile_result, env)
      parts = exec_parts
      for _, d in ipairs(exec_diagnostics) do
        d.message_role = msg.role
        table.insert(diagnostics, d)
      end
      if #exec_diagnostics > 0 then
        log.debug("processor: @" .. msg.role .. " template produced " .. #exec_diagnostics .. " diagnostics")
      end
    end

    table.insert(evaluated_messages, {
      role = msg.role,
      parts = parts,
      position = msg.position,
    })
  end

  -- Drain generic eval-phase diagnostics (file drift, future producers)
  for _, d in ipairs(env[symbols.DIAGNOSTICS] or {}) do
    table.insert(diagnostics, d)
  end

  return {
    messages = evaluated_messages,
    diagnostics = diagnostics,
    opts = context:get_opts(),
  }
end

return M
