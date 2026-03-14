--- Preprocessor system for Flemma
--- Provides a rewriter-based pipeline that transforms buffer content before
--- it is sent to the provider. Rewriters register pattern-based text handlers
--- and segment-kind handlers, producing emissions (text, expression, remove,
--- rewrite) that the runner applies in priority order.
---@class flemma.Preprocessor
local M = {}

local registry = require("flemma.preprocessor.registry")

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local DEFAULT_PRIORITY = 500

--------------------------------------------------------------------------------
-- Emission types
--------------------------------------------------------------------------------

--- A text emission preserves the matched text as literal content.
---@class flemma.preprocessor.TextEmission
---@field type "text"
---@field text string

--- An expression emission replaces the matched text with a sandboxed Lua expression.
---@class flemma.preprocessor.ExpressionEmission
---@field type "expression"
---@field code string

--- A remove emission deletes the matched text entirely.
---@class flemma.preprocessor.RemoveEmission
---@field type "remove"

--- A rewrite emission replaces the matched text with new literal content.
---@class flemma.preprocessor.RewriteEmission
---@field type "rewrite"
---@field text string

---@alias flemma.preprocessor.Emission flemma.preprocessor.TextEmission|flemma.preprocessor.ExpressionEmission|flemma.preprocessor.RemoveEmission|flemma.preprocessor.RewriteEmission

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
---@field severity integer vim.diagnostic.severity value
---@field message string
---@field lnum? integer 0-indexed line number
---@field col? integer 0-indexed column
---@field end_lnum? integer 0-indexed end line
---@field end_col? integer 0-indexed end column

--------------------------------------------------------------------------------
-- Confirmation type (used by ctx:confirm() suspension API)
--------------------------------------------------------------------------------

---@class flemma.preprocessor.Confirmation
---@field id string Stable identifier for answer caching
---@field prompt string Human-readable question
---@field options? { yes_label?: string, no_label?: string }
---@field _is_confirmation boolean Always true — sentinel for is_confirmation()

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

return M
