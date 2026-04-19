--- Preprocessor system for Flemma
--- Provides a rewriter-based pipeline that transforms buffer content before
--- it is sent to the provider. Rewriters register pattern-based text handlers
--- and segment-kind handlers, producing emissions (text, expression, remove,
--- rewrite) that the runner applies in priority order.
---@class flemma.Preprocessor
local M = {}

local context_module = require("flemma.preprocessor.context")
local notify = require("flemma.notify")
local registry = require("flemma.preprocessor.registry")
local runner = require("flemma.preprocessor.runner")
local state = require("flemma.state")

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local DEFAULT_PRIORITY = 500

--------------------------------------------------------------------------------
-- Emission types
--------------------------------------------------------------------------------

--- A text emission preserves the matched text as literal content.
---@class flemma.preprocessor.TextEmission
---@field kind "text"
---@field value string

--- An expression emission replaces the matched text with a sandboxed Lua expression.
---@class flemma.preprocessor.ExpressionEmission
---@field kind "expression"
---@field code string

--- A remove emission deletes the matched text entirely.
---@class flemma.preprocessor.RemoveEmission
---@field kind "remove"

--- A rewrite emission replaces the matched text with new literal content.
---@class flemma.preprocessor.RewriteEmission
---@field kind "rewrite"
---@field value string

--- A code emission inserts a template code block ({% lua_code %}).
---@class flemma.preprocessor.CodeEmission
---@field kind "code"
---@field code string
---@field trim_before? boolean
---@field trim_after? boolean

---@alias flemma.preprocessor.Emission flemma.preprocessor.TextEmission|flemma.preprocessor.ExpressionEmission|flemma.preprocessor.RemoveEmission|flemma.preprocessor.RewriteEmission|flemma.preprocessor.CodeEmission

---@alias flemma.preprocessor.EmissionList flemma.preprocessor.Emission[]

--------------------------------------------------------------------------------
-- Match type
--------------------------------------------------------------------------------

--- Describes a pattern match within a line of text.
---@class flemma.preprocessor.Match
---@field full string The full matched string
---@field start_col integer 1-indexed start column within the line
---@field end_col integer 1-indexed end column within the line (inclusive)
---@field captures string[] Capture groups from the pattern
---@field _line? integer Internal: line number for position derivation

--------------------------------------------------------------------------------
-- Forward declarations (defined in submodules)
--------------------------------------------------------------------------------

--- Forward declaration — full definition lives in flemma.preprocessor.context
---@class flemma.preprocessor.Context

--------------------------------------------------------------------------------
-- Handler types
--------------------------------------------------------------------------------

---@alias flemma.preprocessor.TextHandler fun(match: flemma.preprocessor.Match, context: flemma.preprocessor.Context): flemma.preprocessor.Emission|flemma.preprocessor.EmissionList|nil
---@alias flemma.preprocessor.SegmentHandler fun(segment: table, context: flemma.preprocessor.Context): flemma.preprocessor.Emission|flemma.preprocessor.EmissionList|nil

--------------------------------------------------------------------------------
-- Diagnostic type
--------------------------------------------------------------------------------

---@class flemma.preprocessor.RewriterDiagnostic
---@field type "rewriter"
---@field rewriter_name string
---@field severity "error"|"warning"
---@field error string Human-readable diagnostic message
---@field position? flemma.ast.Position
---@field label? string Short label for the diagnostic
---@field filename? string Associated filename
---@field raw? string Raw source text that triggered the diagnostic

--------------------------------------------------------------------------------
-- Syntax rule type
--------------------------------------------------------------------------------

--- Declarative Vim syntax rule returned by rewriter:get_vim_syntax(config).
--- Each rule describes a syntax item and its associated highlight group.
---@class flemma.preprocessor.SyntaxRule
---@field kind "match"|"region"
---@field group string Full highlight group name (e.g., "FlemmaUserFileReference")
---@field pattern? string For "match": the Vim pattern
---@field start? string For "region": start pattern
---@field end_? string For "region": end pattern (trailing _ avoids Lua reserved word)
---@field containedin? string|string[] "*" (default) or subset like {"user", "system"}
---@field contains? string Vim syntax groups this region contains (for nested highlighting)
---@field hl string|table Highlight value (same format as config highlight values)
---@field options? string Extra Vim syntax options ("oneline", "keepend", "display", etc.)
---@field raw? string Escape hatch: raw VimScript string, bypasses generation

--------------------------------------------------------------------------------
-- Rewriter class
--------------------------------------------------------------------------------

---@class flemma.preprocessor.TextHandlerEntry
---@field pattern string Lua pattern
---@field handler flemma.preprocessor.TextHandler

---@class flemma.preprocessor.SegmentHandlerEntry
---@field kind string Segment kind to match
---@field handler flemma.preprocessor.SegmentHandler

---@class flemma.preprocessor.Rewriter
---@field name string
---@field priority integer
---@field text_handlers flemma.preprocessor.TextHandlerEntry[]
---@field segment_handlers flemma.preprocessor.SegmentHandlerEntry[]
---@field get_vim_syntax? fun(self: flemma.preprocessor.Rewriter, config: flemma.Config): flemma.preprocessor.SyntaxRule[]
local Rewriter = {}
Rewriter.__index = Rewriter

---@class flemma.preprocessor.RewriterOpts
---@field priority? integer Priority for ordering (lower runs first, default 500)

--- Create a new Rewriter instance.
---@param name string Rewriter name
---@param opts? flemma.preprocessor.RewriterOpts
---@return flemma.preprocessor.Rewriter
function Rewriter.new(name, opts)
  opts = opts or {}
  local self = setmetatable({
    name = name,
    priority = opts.priority or DEFAULT_PRIORITY,
    text_handlers = {},
    segment_handlers = {},
  }, Rewriter)
  return self
end

--- Register a text pattern handler.
---@param pattern string Lua pattern to match against line text
---@param handler flemma.preprocessor.TextHandler Handler function
function Rewriter:on_text(pattern, handler)
  table.insert(self.text_handlers, {
    pattern = pattern,
    handler = handler,
  })
end

--- Register a segment kind handler.
---@param kind string Segment kind to match (e.g., "expression", "file_reference")
---@param handler flemma.preprocessor.SegmentHandler Handler function
function Rewriter:on(kind, handler)
  table.insert(self.segment_handlers, {
    kind = kind,
    handler = handler,
  })
end

M.Rewriter = Rewriter

--------------------------------------------------------------------------------
-- Built-in rewriter module paths (loaded by setup())
--------------------------------------------------------------------------------

---@type string[]
local BUILTIN_REWRITERS = {
  "flemma.preprocessor.rewriters.file_references",
}

M.BUILTIN_REWRITERS = BUILTIN_REWRITERS

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Create a new rewriter with the given name and options.
---@param name string Rewriter name
---@param opts? flemma.preprocessor.RewriterOpts
---@return flemma.preprocessor.Rewriter
function M.create_rewriter(name, opts)
  return Rewriter.new(name, opts)
end

--- Register a rewriter. Accepts three overloads:
---   (name, rewriter)        — register under an explicit name
---   (module_path_string)    — register from a module path
---   (rewriter_object)       — register using the rewriter's .name field
---@param source string|flemma.preprocessor.Rewriter
---@param definition? flemma.preprocessor.Rewriter
function M.register(source, definition)
  registry.register(source, definition)
end

--- Return all registered rewriters sorted by priority ascending.
---@return flemma.preprocessor.Rewriter[]
function M.get_all()
  return registry.get_all()
end

--- Unregister a rewriter by name.
---@param name string
---@return boolean removed
function M.unregister(name)
  return registry.unregister(name)
end

--------------------------------------------------------------------------------
-- Pipeline execution
--------------------------------------------------------------------------------

---@class flemma.preprocessor.RunUserOpts
---@field interactive? boolean Whether this is an interactive (live) run (default false)

--- Run the preprocessor pipeline on a parsed document.
--- Returns the transformed document and diagnostics. If a Confirmation is thrown
--- during an interactive run, returns nil, nil so the caller can present the
--- confirmation UI and re-run.
---@param doc flemma.ast.DocumentNode Parsed document to transform
---@param bufnr integer|nil Buffer number (required for interactive mode)
---@param opts? flemma.preprocessor.RunUserOpts
---@return flemma.ast.DocumentNode|nil result_doc Nil when suspended for confirmation
---@return flemma.preprocessor.RewriterDiagnostic[]|nil diagnostics Nil when suspended
function M.run(doc, bufnr, opts)
  opts = opts or {}
  local rewriters = registry.get_all()
  if #rewriters == 0 then
    return doc, {}
  end

  ---@type flemma.preprocessor.RunOpts
  local run_opts = {
    interactive = opts.interactive or false,
    rewriters = rewriters,
    bufnr = bufnr,
  }

  local ok, result_or_err, result_diagnostics = pcall(runner.run_pipeline, doc, bufnr, run_opts)

  if not ok then
    -- Check if this is a Confirmation suspension
    if context_module.is_confirmation(result_or_err) then
      -- Store the pending confirmation in buffer state for the UI to present
      if bufnr then
        local buffer_state = state.get_buffer_state(bufnr)
        local confirmation = result_or_err --[[@as flemma.preprocessor.Confirmation]]
        buffer_state._pending_confirmation = confirmation
      end
      return nil, nil
    end
    -- Non-confirmation error — re-throw
    error(result_or_err)
  end

  ---@cast result_or_err flemma.ast.DocumentNode
  ---@cast result_diagnostics flemma.preprocessor.RewriterDiagnostic[]
  return result_or_err, result_diagnostics
end

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

--- Initialize the preprocessor subsystem.
--- Loads built-in rewriters and registers the post-parse hook.
function M.setup()
  -- Load built-in rewriters
  for _, module_path in ipairs(BUILTIN_REWRITERS) do
    local load_ok, load_err = pcall(M.register, module_path)
    if not load_ok then
      notify.warn("Failed to load built-in rewriter " .. module_path .. ": " .. tostring(load_err))
    end
  end

  -- Register post-parse hook (parser.set_post_parse_hook is added in Task 8)
  -- The hook runs the preprocessor in non-interactive mode after each parse,
  -- storing diagnostics in buffer state and returning the rewritten document.
  local parser_ok, parser_module = pcall(require, "flemma.parser")
  if parser_ok then
    local parser_table = parser_module --[[@as table]]
    local hook_setter = parser_table.set_post_parse_hook
    if hook_setter then
      hook_setter(function(doc, bufnr)
        local result_doc, diagnostics = M.run(doc, bufnr, { interactive = false })
        if result_doc and bufnr then
          local buffer_state = state.get_buffer_state(bufnr)
          buffer_state.rewriter_diagnostics = diagnostics
        end
        return result_doc or doc
      end)
    end
  end
end

return M
