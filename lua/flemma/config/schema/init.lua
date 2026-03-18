--- Schema DSL factory — thin wrapper providing the user-facing API for schema node creation.
---
--- This module is a factory for creating schema nodes defined in `flemma.config.schema.types`.
--- It provides a clean DSL interface: `s.string()`, `s.object()`, etc.
---
---@class flemma.config.schema
local M = {}

local types = require("flemma.config.schema.types")

--- Create a StringNode with an optional default value.
---@param default string|nil
---@return flemma.config.schema.StringNode
function M.string(default)
  return types.StringNode.new(default)
end

--- Create an IntegerNode with an optional default value.
---@param default integer|nil
---@return flemma.config.schema.IntegerNode
function M.integer(default)
  return types.IntegerNode.new(default)
end

--- Create a NumberNode with an optional default value.
---@param default number|nil
---@return flemma.config.schema.NumberNode
function M.number(default)
  return types.NumberNode.new(default)
end

--- Create a BooleanNode with an optional default value.
---@param default boolean|nil
---@return flemma.config.schema.BooleanNode
function M.boolean(default)
  return types.BooleanNode.new(default)
end

--- Create an EnumNode from a list of valid values and an optional default.
---@param values string[] Array of valid enum values
---@param default string|nil
---@return flemma.config.schema.EnumNode
function M.enum(values, default)
  return types.EnumNode.new(values, default)
end

--- Create a ListNode with an item schema and optional default list.
---@param item_schema flemma.config.schema.Node Schema applied to each list item
---@param default table|nil Default list value
---@return flemma.config.schema.ListNode
function M.list(item_schema, default)
  return types.ListNode.new(item_schema, default)
end

--- Create a MapNode with key and value schemas.
---@param key_schema flemma.config.schema.Node Schema applied to each key
---@param value_schema flemma.config.schema.Node Schema applied to each value
---@return flemma.config.schema.MapNode
function M.map(key_schema, value_schema)
  return types.MapNode.new(key_schema, value_schema)
end

--- Create an ObjectNode from a fields table containing string-keyed child schemas.
---@param fields table String-keyed table of child schemas
---@return flemma.config.schema.ObjectNode
function M.object(fields)
  return types.ObjectNode.new(fields)
end

--- Create an OptionalNode wrapping an inner schema.
---@param inner flemma.config.schema.Node The inner schema to wrap
---@return flemma.config.schema.OptionalNode
function M.optional(inner)
  return types.OptionalNode.new(inner)
end

--- Create a UnionNode from variadic branch schemas.
---@param ... flemma.config.schema.Node One or more branch schemas
---@return flemma.config.schema.UnionNode
function M.union(...)
  local branches = { ... }
  return types.UnionNode.new(branches)
end

--- Create a FuncNode for function-type values.
---@return flemma.config.schema.FuncNode
function M.func()
  return types.FuncNode.new()
end

--- Create a LoadableNode for Lua module path strings.
---@return flemma.config.schema.LoadableNode
function M.loadable()
  return types.LoadableNode.new()
end

return M
