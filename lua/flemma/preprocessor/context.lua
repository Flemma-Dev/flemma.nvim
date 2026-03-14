--- Preprocessor execution context
--- Provides segment factories, metadata storage, and diagnostics for rewriter
--- handlers. Each handler invocation receives a Context instance scoped to the
--- current position in the document.
---@class flemma.preprocessor.ContextModule
local M = {}

--------------------------------------------------------------------------------
-- Forward declarations (fully defined later in this file)
--------------------------------------------------------------------------------

--- System message accessor — allows rewriters to prepend/append to system prompts.
---@class flemma.preprocessor.SystemAccessor

--- Frontmatter accessor — allows rewriters to mutate frontmatter fields.
---@class flemma.preprocessor.FrontmatterAccessor

--------------------------------------------------------------------------------
-- Context options
--------------------------------------------------------------------------------

---@class flemma.preprocessor.ContextOpts
---@field system? flemma.preprocessor.SystemAccessor
---@field frontmatter? flemma.preprocessor.FrontmatterAccessor
---@field message? table The current message node
---@field message_index? integer 1-indexed position in the message array
---@field position? { line?: integer, col?: integer } Current position in the buffer
---@field document? table The full document AST node
---@field interactive? boolean Whether this is an interactive (live) run
---@field _bufnr? integer Buffer number
---@field _rewriter_name? string Name of the currently executing rewriter
---@field _metadata? table<string, any> Pre-populated metadata
---@field _diagnostics? flemma.preprocessor.RewriterDiagnostic[] Pre-populated diagnostics

--------------------------------------------------------------------------------
-- Diagnostic options
--------------------------------------------------------------------------------

---@class flemma.preprocessor.DiagnosticOpts
---@field lnum? integer 0-indexed line number
---@field col? integer 0-indexed column
---@field end_lnum? integer 0-indexed end line
---@field end_col? integer 0-indexed end column

--------------------------------------------------------------------------------
-- Context class
--------------------------------------------------------------------------------

--- Execution context passed to rewriter handlers.
--- Provides segment factories for building emissions, metadata storage,
--- and diagnostic reporting.
---@class flemma.preprocessor.Context
---@field system flemma.preprocessor.SystemAccessor
---@field frontmatter flemma.preprocessor.FrontmatterAccessor
---@field message? table The current message node
---@field message_index? integer 1-indexed position in the message array
---@field position? { line?: integer, col?: integer } Current position in the buffer
---@field document? table The full document AST node
---@field interactive boolean Whether this is an interactive (live) run
---@field _bufnr? integer Buffer number
---@field _metadata table<string, any> Metadata key-value store
---@field _diagnostics flemma.preprocessor.RewriterDiagnostic[] Accumulated diagnostics
---@field _rewriter_name? string Name of the currently executing rewriter
local Context = {}
Context.__index = Context

--- Create a new Context instance.
---@param opts flemma.preprocessor.ContextOpts
---@return flemma.preprocessor.Context
function M.new(opts)
  local self = setmetatable({
    system = opts.system,
    frontmatter = opts.frontmatter,
    message = opts.message,
    message_index = opts.message_index,
    position = opts.position,
    document = opts.document,
    interactive = opts.interactive or false,
    _bufnr = opts._bufnr,
    _metadata = opts._metadata or {},
    _diagnostics = opts._diagnostics or {},
    _rewriter_name = opts._rewriter_name,
  }, Context)
  return self
end

--------------------------------------------------------------------------------
-- Segment factories
--------------------------------------------------------------------------------

--- Create a text emission that preserves matched text as literal content.
---@param str string The literal text
---@return flemma.preprocessor.TextEmission
function Context:text(str)
  return { type = "text", text = str }
end

--- Create an expression emission that replaces matched text with a sandboxed Lua expression.
---@param code string The Lua expression code
---@return flemma.preprocessor.ExpressionEmission
function Context:expression(code)
  return { type = "expression", code = code }
end

--- Create a remove emission that deletes the matched text.
---@return flemma.preprocessor.RemoveEmission
function Context:remove()
  return { type = "remove" }
end

--- Create a rewrite emission that replaces matched text with new literal content.
---@param replacement_text string The replacement text
---@return flemma.preprocessor.RewriteEmission
function Context:rewrite(replacement_text)
  return { type = "rewrite", text = replacement_text }
end

--------------------------------------------------------------------------------
-- Metadata
--------------------------------------------------------------------------------

--- Set a metadata key-value pair.
---@param key string Metadata key
---@param value any Metadata value
function Context:set(key, value)
  self._metadata[key] = value
end

--- Get a metadata value by key.
---@param key string Metadata key
---@return any
function Context:get(key)
  return self._metadata[key]
end

--------------------------------------------------------------------------------
-- Diagnostics
--------------------------------------------------------------------------------

--- Record a diagnostic from the current rewriter.
--- The type and rewriter_name fields are auto-filled from the context.
---@param severity integer vim.diagnostic.severity value
---@param message string Human-readable diagnostic message
---@param opts? flemma.preprocessor.DiagnosticOpts Optional position overrides
function Context:diagnostic(severity, message, opts)
  opts = opts or {}
  ---@type flemma.preprocessor.RewriterDiagnostic
  local diagnostic = {
    type = "rewriter",
    rewriter_name = self._rewriter_name or "unknown",
    severity = severity,
    message = message,
    lnum = opts.lnum,
    col = opts.col,
    end_lnum = opts.end_lnum,
    end_col = opts.end_col,
  }
  table.insert(self._diagnostics, diagnostic)
end

--- Get all accumulated diagnostics.
---@return flemma.preprocessor.RewriterDiagnostic[]
function Context:get_diagnostics()
  return self._diagnostics
end

M.Context = Context

return M
