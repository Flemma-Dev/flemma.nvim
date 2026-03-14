--- Preprocessor execution context
--- Provides segment factories, metadata storage, and diagnostics for rewriter
--- handlers. Each handler invocation receives a Context instance scoped to the
--- current position in the document.
---@class flemma.preprocessor.ContextModule
local M = {}

--------------------------------------------------------------------------------
-- SystemAccessor
--------------------------------------------------------------------------------

---@class flemma.preprocessor.SystemAccessorEntry
---@field emission flemma.preprocessor.Emission
---@field position? { line?: integer, col?: integer }

--- System message accessor — allows rewriters to prepend/append to system prompts.
--- Emissions are collected during the rewriter run and applied afterward.
---@class flemma.preprocessor.SystemAccessor
---@field _prepends flemma.preprocessor.SystemAccessorEntry[]
---@field _appends flemma.preprocessor.SystemAccessorEntry[]
---@field _ctx? flemma.preprocessor.Context
local SystemAccessor = {}
SystemAccessor.__index = SystemAccessor

--- Create a new SystemAccessor instance.
---@return flemma.preprocessor.SystemAccessor
function SystemAccessor.new()
  ---@diagnostic disable-next-line: return-type-mismatch
  return setmetatable({
    _prepends = {},
    _appends = {},
    _ctx = nil,
  }, SystemAccessor)
end

--- Set the current context. Called by the runner before each handler.
---@param ctx flemma.preprocessor.Context
function SystemAccessor:set_context(ctx)
  self._ctx = ctx
end

--- Record an emission to prepend to the system message.
---@param emission flemma.preprocessor.Emission
function SystemAccessor:prepend(emission)
  local position = self._ctx and self._ctx.position or nil
  table.insert(self._prepends, {
    emission = emission,
    position = position,
  })
end

--- Record an emission to append to the system message.
---@param emission flemma.preprocessor.Emission
function SystemAccessor:append(emission)
  local position = self._ctx and self._ctx.position or nil
  table.insert(self._appends, {
    emission = emission,
    position = position,
  })
end

--- Get all prepend entries.
---@return flemma.preprocessor.SystemAccessorEntry[]
function SystemAccessor:get_prepends()
  return self._prepends
end

--- Get all append entries.
---@return flemma.preprocessor.SystemAccessorEntry[]
function SystemAccessor:get_appends()
  return self._appends
end

M.SystemAccessor = SystemAccessor

--------------------------------------------------------------------------------
-- FrontmatterAccessor
--------------------------------------------------------------------------------

---@class flemma.preprocessor.FrontmatterSetMutation
---@field action "set"
---@field key string
---@field value any

---@class flemma.preprocessor.FrontmatterAppendMutation
---@field action "append"
---@field line string

---@class flemma.preprocessor.FrontmatterRemoveMutation
---@field action "remove"
---@field key string

---@alias flemma.preprocessor.FrontmatterMutation flemma.preprocessor.FrontmatterSetMutation|flemma.preprocessor.FrontmatterAppendMutation|flemma.preprocessor.FrontmatterRemoveMutation

--- Frontmatter accessor — allows rewriters to mutate frontmatter fields.
--- Mutations are collected during the rewriter run and applied afterward.
---@class flemma.preprocessor.FrontmatterAccessor
---@field _mutations flemma.preprocessor.FrontmatterMutation[]
local FrontmatterAccessor = {}
FrontmatterAccessor.__index = FrontmatterAccessor

--- Create a new FrontmatterAccessor instance.
---@return flemma.preprocessor.FrontmatterAccessor
function FrontmatterAccessor.new()
  ---@diagnostic disable-next-line: return-type-mismatch
  return setmetatable({
    _mutations = {},
  }, FrontmatterAccessor)
end

--- Record a set mutation (set key to value).
---@param key string Frontmatter key
---@param value any Value to set
function FrontmatterAccessor:set(key, value)
  table.insert(self._mutations, {
    action = "set",
    key = key,
    value = value,
  })
end

--- Record an append mutation (append a raw line).
---@param line string Line to append
function FrontmatterAccessor:append(line)
  table.insert(self._mutations, {
    action = "append",
    line = line,
  })
end

--- Record a remove mutation (remove a key).
---@param key string Frontmatter key to remove
function FrontmatterAccessor:remove(key)
  table.insert(self._mutations, {
    action = "remove",
    key = key,
  })
end

--- Get all recorded mutations.
---@return flemma.preprocessor.FrontmatterMutation[]
function FrontmatterAccessor:get_mutations()
  return self._mutations
end

M.FrontmatterAccessor = FrontmatterAccessor

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
    system = opts.system or SystemAccessor.new(),
    frontmatter = opts.frontmatter or FrontmatterAccessor.new(),
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
