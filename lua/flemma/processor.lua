local compiler = require("flemma.templating.compiler")
local config = require("flemma.config")
local config_store = require("flemma.config.store")
local ctxutil = require("flemma.context")
local eval = require("flemma.templating.eval")
local templating = require("flemma.templating")
local codeblock_parsers = require("flemma.codeblock.parsers")
local log = require("flemma.logging")
local parser = require("flemma.parser")
local state = require("flemma.state")
local diagnostic_format = require("flemma.utilities.diagnostic")
local symbols = require("flemma.symbols")
local ast = require("flemma.ast")
local ast_query = require("flemma.ast.query")
local tools_registry = require("flemma.tools.registry")

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

---@class flemma.processor.ToolResultPart
---@field kind "tool_result"
---@field tool_use_id string
---@field content string
---@field parts? table[] Child parts from capture (file/text); populated only for opted-in tools
---@field is_error boolean

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

---@class flemma.processor.EvaluatedFrontmatter
---@field context flemma.Context Evaluated context with user variables set
---@field diagnostics flemma.ast.Diagnostic[] Frontmatter-specific diagnostics (includes converted validation failures)
---@field frontmatter_code? string Raw frontmatter code that was evaluated (nil when no frontmatter)

---Evaluate frontmatter and return the resulting context (with user variables set).
---When bufnr is provided, frontmatter writes go directly to the config store's
---FRONTMATTER layer — no separate resolve step needed.
---@param doc flemma.ast.DocumentNode
---@param base_context flemma.Context|nil
---@param bufnr? integer Buffer number for config store writes
---@return flemma.Context context
---@return flemma.ast.Diagnostic[] diagnostics Frontmatter-specific diagnostics (includes converted validation failures)
---@return string? frontmatter_code Raw frontmatter code that was evaluated
local function evaluate_frontmatter_internal(doc, base_context, bufnr)
  local context = ctxutil.clone(base_context)
  local diagnostics = {}
  local frontmatter_code = nil

  -- Clear the frontmatter layer before evaluation so previous ops don't persist
  if bufnr then
    config.prepare_frontmatter(bufnr)
  end

  if doc.frontmatter then
    local fm = doc.frontmatter ---@cast fm -nil
    frontmatter_code = fm.code
    local fm_parser = codeblock_parsers.get(fm.language)

    if fm_parser then
      local ok, result, fm_validation_failures = pcall(fm_parser, fm.code, context, bufnr)
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
        -- Convert validation failures into diagnostics at the boundary —
        -- enriched with position/source_file from the frontmatter AST node.
        local fm_defaults = {
          position = fm.position,
          source_file = context:get_filename() or "N/A",
        }
        for _, failure in ipairs(fm_validation_failures or {}) do
          table.insert(diagnostics, diagnostic_format.from_validation_failure(failure, fm_defaults))
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

  return context, diagnostics, frontmatter_code
end

---Evaluate frontmatter from a parsed document.
---Returns the evaluated context (with user variables) and any diagnostics.
---When bufnr is provided, frontmatter config writes go to the config store.
---@param doc flemma.ast.DocumentNode
---@param base_context flemma.Context|nil
---@param bufnr? integer Buffer number for config store writes
---@return flemma.processor.EvaluatedFrontmatter
function M.evaluate_frontmatter(doc, base_context, bufnr)
  local context, diagnostics, frontmatter_code = evaluate_frontmatter_internal(doc, base_context, bufnr)
  return {
    context = context,
    diagnostics = diagnostics,
    frontmatter_code = frontmatter_code,
  }
end

---Convenience: parse buffer + evaluate frontmatter in one call.
---For callers that start from a bufnr (e.g., status.lua).
---@param bufnr integer
---@return flemma.processor.EvaluatedFrontmatter
function M.evaluate_buffer_frontmatter(bufnr)
  local doc = parser.get_parsed_document(bufnr)
  return M.evaluate_frontmatter(doc, ctxutil.from_buffer(bufnr), bufnr)
end

---Evaluate frontmatter if the code has changed since the last evaluation.
---Designed for passive triggers (InsertLeave, TextChanged) — swallows diagnostics
---and validation failures silently. On error, restores the previous L40 state
---so the last successful parse remains active.
---@param bufnr integer
function M.evaluate_frontmatter_if_changed(bufnr)
  local buffer_state = state.get_buffer_state(bufnr)

  -- Skip if buffer is locked (request in flight owns L40)
  if buffer_state.locked then
    return
  end

  local doc = parser.get_parsed_document(bufnr)

  if not doc.frontmatter then
    -- Frontmatter was removed — clear L40 if it was previously populated
    if buffer_state.frontmatter_eval_code ~= nil then
      config.prepare_frontmatter(bufnr)
      buffer_state.frontmatter_eval_code = nil
    end
    return
  end

  -- Skip if frontmatter code hasn't changed since last evaluation
  if doc.frontmatter.code == buffer_state.frontmatter_eval_code then
    return
  end

  -- Snapshot L40 before evaluation — if frontmatter has errors we restore
  -- the last good state so a mid-edit typo doesn't wipe the config.
  local snapshot = config_store.snapshot_buffer(bufnr)

  local result = M.evaluate_buffer_frontmatter(bufnr)

  -- Check for evaluation errors (syntax errors, runtime errors).
  -- Skip validation failures (d.validation) — those are post-execution schema
  -- checks, not broken frontmatter code. A mid-edit typo in a config value
  -- shouldn't rollback the entire L40 state.
  local has_errors = false
  for _, diagnostic in ipairs(result.diagnostics) do
    if diagnostic.severity == "error" and not diagnostic.validation then
      has_errors = true
      break
    end
  end

  if has_errors then
    -- Restore previous L40 — keep the last successfully parsed config
    config_store.restore_buffer(bufnr, snapshot)
    return
  end

  buffer_state.frontmatter_eval_code = result.frontmatter_code
end

--- Evaluate a document AST.
--- If a pre-evaluated frontmatter result is provided, it is reused instead of
--- re-evaluating frontmatter code. This allows callers to evaluate frontmatter
--- once and thread the result through multiple consumers.
---@class flemma.processor.EvaluateOpts
---@field evaluated_frontmatter? flemma.processor.EvaluatedFrontmatter Pre-evaluated frontmatter (skips re-evaluation)
---@field bufnr integer Buffer number for per-buffer config resolution and expression evaluation

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
    context, fm_diagnostics = evaluate_frontmatter_internal(doc, base_context, opts.bufnr)
  end

  -- Merge parser errors with frontmatter diagnostics (shallow copy to avoid
  -- mutating doc.errors, which persists in the AST snapshot across requests).
  -- Validation failures are already converted to diagnostics inside
  -- evaluate_frontmatter_internal(), so no separate normalization needed.
  local diagnostics = {}
  for _, d in ipairs(doc.errors or {}) do
    table.insert(diagnostics, d)
  end
  for _, d in ipairs(fm_diagnostics) do
    table.insert(diagnostics, d)
  end

  -- 2) Evaluate messages
  local evaluated_messages = {}
  local env = templating.from_context(context, opts.bufnr)
  eval.ensure_env(env)

  -- Build a tool_use_id -> info index once per document for capability lookups.
  local tool_use_index = ast_query.build_tool_use_index(doc)

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

      -- Collapse non-opted-in tool results to their fallback form (empty segments).
      -- Only tools declaring the `template_tool_result` capability get their
      -- inner segments compiled and evaluated through the capture mechanism.
      local prepared = {}
      for _, seg in ipairs(msg.segments or {}) do
        if seg.kind == "tool_result" and seg.segments and #seg.segments > 0 then
          local info = tool_use_index[seg.tool_use_id]
          if info and tools_registry.has_capability(info.name, "template_tool_result") then
            table.insert(prepared, seg)
          else
            table.insert(
              prepared,
              ast.tool_result(seg.tool_use_id, {
                segments = {},
                content = seg.content,
                is_error = seg.is_error,
                status = seg.status,
                start_line = seg.position and seg.position.start_line,
                end_line = seg.position and seg.position.end_line,
              })
            )
          end
        else
          table.insert(prepared, seg)
        end
      end

      local compile_result = compiler.compile(prepared)
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
  }
end

return M
