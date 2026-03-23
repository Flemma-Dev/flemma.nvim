--- Schema DSL primitives for the unified configuration system.
---
--- The schema is the single source of truth for Flemma's configuration.
--- It defines structure, types, defaults, and list semantics.
---
--- Usage:
---   local s = require("flemma.schema")
---   local MySchema = s.object({
---     provider = s.string("anthropic"),
---     timeout  = s.optional(s.integer()),
---   })
---@class flemma.schema
local M = {}

local types = require("flemma.schema.types")

---@param default? string
---@return flemma.schema.StringNode
function M.string(default)
  return types.StringNode.new(default)
end

---@param default? integer
---@return flemma.schema.IntegerNode
function M.integer(default)
  return types.IntegerNode.new(default)
end

---@param default? number
---@return flemma.schema.NumberNode
function M.number(default)
  return types.NumberNode.new(default)
end

---@param default? boolean
---@return flemma.schema.BooleanNode
function M.boolean(default)
  return types.BooleanNode.new(default)
end

---@param values string[]
---@param default? any
---@return flemma.schema.EnumNode
function M.enum(values, default)
  return types.EnumNode.new(values, default)
end

--- List schema node that supports append/remove/prepend operations.
---@param item_schema flemma.schema.Node
---@param default? any[]
---@return flemma.schema.ListNode
function M.list(item_schema, default)
  return types.ListNode.new(item_schema, default)
end

---@param key_schema flemma.schema.Node
---@param value_schema flemma.schema.Node
---@param default? table
---@return flemma.schema.MapNode
function M.map(key_schema, value_schema, default)
  return types.MapNode.new(key_schema, value_schema, default)
end

--- Fixed-shape object schema node. Strict by default (unknown keys rejected).
--- The fields table may include special symbol keys:
---   [symbols.ALIASES] = { alias = "canonical.path" }
---   [symbols.DISCOVER] = function(key) return schema_node or nil end
---@param fields table<string|table, flemma.schema.Node|table|function>
---@return flemma.schema.ObjectNode
function M.object(fields)
  return types.ObjectNode.new(fields)
end

--- Wraps a schema node to make nil a valid value (field can be absent).
--- In JSON Schema: the field is omitted from `required`.
---@param inner_schema flemma.schema.Node
---@return flemma.schema.OptionalNode
function M.optional(inner_schema)
  return types.OptionalNode.new(inner_schema)
end

--- Wraps a schema node to allow null values (field must be present, value can be null).
--- In JSON Schema: the field stays in `required`, and `type` includes "null".
---@param inner_schema flemma.schema.Node
---@return flemma.schema.NullableNode
function M.nullable(inner_schema)
  return types.NullableNode.new(inner_schema)
end

--- Union schema node that accepts values matching any branch (first match wins).
---@param ... flemma.schema.Node
---@return flemma.schema.UnionNode
function M.union(...)
  return types.UnionNode.new({ ... })
end

--- Validates module paths via flemma.loader.
---@param default? string
---@return flemma.schema.LoadableNode
function M.loadable(default)
  return types.LoadableNode.new(default)
end

--- Validates that values are Lua functions.
---@return flemma.schema.FuncNode
function M.func()
  return types.FuncNode.new()
end

--- Matches exactly one value (by equality). Useful for sentinel values
--- like `false` in unions where a full boolean type would be too permissive.
---@param value any
---@return flemma.schema.LiteralNode
function M.literal(value)
  return types.LiteralNode.new(value)
end

return M
