--- Schema node type definitions for Flemma's unified config system
---
--- Each node type knows how to materialize its default value and validate
--- incoming values. Nodes support method chaining for metadata decoration.
---
---@class flemma.config.schema.types
local M = {}

local symbols = require("flemma.symbols")

-- =============================================================================
-- Base node (shared behaviour)
-- =============================================================================

---@class flemma.config.schema.Node
---@field _description string|nil Human-readable description for EmmyLua generation
---@field _type_as string|nil Type annotation override for EmmyLua generation
---@field _strict boolean Whether the node is in strict mode (ObjectNode default)
---@field materialize fun(self: flemma.config.schema.Node): any Return the default value for this node
---@field validate fun(self: flemma.config.schema.Node, value: any): boolean Return true if value is valid for this node
local BaseNode = {}
BaseNode.__index = BaseNode

--- Store a human-readable description. Returns self for chaining.
---@param text string
---@return flemma.config.schema.Node
function BaseNode:describe(text)
  self._description = text
  return self
end

--- Override the generated EmmyLua type annotation. Returns self for chaining.
---@param text string
---@return flemma.config.schema.Node
function BaseNode:type_as(text)
  self._type_as = text
  return self
end

--- Enable strict validation mode. Returns self for chaining.
---@return flemma.config.schema.Node
function BaseNode:strict()
  self._strict = true
  return self
end

--- Disable strict validation mode (allow unknown keys). Returns self for chaining.
---@return flemma.config.schema.Node
function BaseNode:passthrough()
  self._strict = false
  return self
end

--- Returns whether this node represents an ordered list. Default is false.
---@return boolean
function BaseNode:is_list()
  return false
end

-- =============================================================================
-- StringNode
-- =============================================================================

---@class flemma.config.schema.StringNode : flemma.config.schema.Node
---@field _default string|nil
local StringNode = setmetatable({}, { __index = BaseNode })
StringNode.__index = StringNode

--- Create a new StringNode with an optional default value.
---@param default string|nil
---@return flemma.config.schema.StringNode
function StringNode.new(default)
  local self = setmetatable({}, StringNode)
  self._default = default
  return self
end

--- Return the default string value.
---@return string|nil
function StringNode:materialize()
  return self._default
end

--- Return true if value is a string.
---@param value any
---@return boolean
function StringNode:validate(value)
  return type(value) == "string"
end

M.StringNode = StringNode

-- =============================================================================
-- IntegerNode
-- =============================================================================

---@class flemma.config.schema.IntegerNode : flemma.config.schema.Node
---@field _default integer|nil
local IntegerNode = setmetatable({}, { __index = BaseNode })
IntegerNode.__index = IntegerNode

--- Create a new IntegerNode with an optional default value.
---@param default integer|nil
---@return flemma.config.schema.IntegerNode
function IntegerNode.new(default)
  local self = setmetatable({}, IntegerNode)
  self._default = default
  return self
end

--- Return the default integer value.
---@return integer|nil
function IntegerNode:materialize()
  return self._default
end

--- Return true if value is a number with no fractional part.
--- In LuaJIT all numbers are doubles; we check type == "number" and no fraction.
---@param value any
---@return boolean
function IntegerNode:validate(value)
  if type(value) ~= "number" then
    return false
  end
  return math.floor(value) == value
end

M.IntegerNode = IntegerNode

-- =============================================================================
-- NumberNode
-- =============================================================================

---@class flemma.config.schema.NumberNode : flemma.config.schema.Node
---@field _default number|nil
local NumberNode = setmetatable({}, { __index = BaseNode })
NumberNode.__index = NumberNode

--- Create a new NumberNode with an optional default value.
---@param default number|nil
---@return flemma.config.schema.NumberNode
function NumberNode.new(default)
  local self = setmetatable({}, NumberNode)
  self._default = default
  return self
end

--- Return the default number value.
---@return number|nil
function NumberNode:materialize()
  return self._default
end

--- Return true if value is a number.
---@param value any
---@return boolean
function NumberNode:validate(value)
  return type(value) == "number"
end

M.NumberNode = NumberNode

-- =============================================================================
-- BooleanNode
-- =============================================================================

---@class flemma.config.schema.BooleanNode : flemma.config.schema.Node
---@field _default boolean|nil
local BooleanNode = setmetatable({}, { __index = BaseNode })
BooleanNode.__index = BooleanNode

--- Create a new BooleanNode with an optional default value.
---@param default boolean|nil
---@return flemma.config.schema.BooleanNode
function BooleanNode.new(default)
  local self = setmetatable({}, BooleanNode)
  self._default = default
  return self
end

--- Return the default boolean value.
---@return boolean|nil
function BooleanNode:materialize()
  return self._default
end

--- Return true if value is a boolean.
---@param value any
---@return boolean
function BooleanNode:validate(value)
  return type(value) == "boolean"
end

M.BooleanNode = BooleanNode

-- =============================================================================
-- EnumNode
-- =============================================================================

---@class flemma.config.schema.EnumNode : flemma.config.schema.Node
---@field _default string|nil
---@field _values_set table<string, boolean> Lookup table for valid values
local EnumNode = setmetatable({}, { __index = BaseNode })
EnumNode.__index = EnumNode

--- Create a new EnumNode from an array of valid values and an optional default.
---@param values string[] Array of valid enum values
---@param default string|nil
---@return flemma.config.schema.EnumNode
function EnumNode.new(values, default)
  local self = setmetatable({}, EnumNode)
  self._default = default
  self._values_set = {}
  for _, v in ipairs(values) do
    self._values_set[v] = true
  end
  return self
end

--- Return the default enum value.
---@return string|nil
function EnumNode:materialize()
  return self._default
end

--- Return true if value is one of the valid enum values.
---@param value any
---@return boolean
function EnumNode:validate(value)
  if type(value) ~= "string" then
    return false
  end
  return self._values_set[value] == true
end

M.EnumNode = EnumNode

-- =============================================================================
-- ObjectNode
-- =============================================================================

---@class flemma.config.schema.ObjectNode : flemma.config.schema.Node
---@field _fields table<string, flemma.config.schema.Node> String-keyed child schemas
---@field _aliases table<string, string>|nil Alias map extracted from symbols.ALIASES
---@field _discover (fun(key: string): flemma.config.schema.Node|nil)|nil Lazy resolution callback
local ObjectNode = setmetatable({}, { __index = BaseNode })
ObjectNode.__index = ObjectNode

--- Create a new ObjectNode from a fields table.
---
--- Symbol keys (symbols.ALIASES, symbols.DISCOVER) are extracted from the
--- fields table into dedicated fields on the node; they are not included in
--- _fields and will not appear in materialized output.
---
---@param fields table Raw fields table, may contain symbol keys
---@return flemma.config.schema.ObjectNode
function ObjectNode.new(fields)
  local self = setmetatable({}, ObjectNode)
  self._strict = true
  self._fields = {}
  self._aliases = nil
  self._discover = nil

  for key, value in pairs(fields) do
    if key == symbols.ALIASES then
      self._aliases = value
    elseif key == symbols.DISCOVER then
      self._discover = value
    elseif type(key) == "string" then
      self._fields[key] = value
    end
  end

  return self
end

--- Recursively materialize all child field defaults into a new table.
--- Uses vim.deepcopy for value independence when schema nodes are reused.
---@return table
function ObjectNode:materialize()
  local result = {}
  for field_name, field_schema in pairs(self._fields) do
    local materialized = field_schema:materialize()
    if materialized ~= nil then
      result[field_name] = vim.deepcopy(materialized)
    end
  end
  return result
end

--- Return true if value is a table.
---@param value any
---@return boolean
function ObjectNode:validate(value)
  return type(value) == "table"
end

--- Resolve a shorthand alias key to its canonical path string.
--- Returns nil if no alias is registered for the given key.
--- Aliases do not chain — only one level of resolution is performed.
---@param key string
---@return string|nil
function ObjectNode:resolve_alias(key)
  if not self._aliases then
    return nil
  end
  return self._aliases[key]
end

M.ObjectNode = ObjectNode

-- =============================================================================
-- ListNode
-- =============================================================================

---@class flemma.config.schema.ListNode : flemma.config.schema.Node
---@field _item_schema flemma.config.schema.Node Schema for each list item
---@field _default table Default list value (deep copied on materialize)
local ListNode = setmetatable({}, { __index = BaseNode })
ListNode.__index = ListNode

--- Create a new ListNode with an item schema and optional default list.
---@param item_schema flemma.config.schema.Node Schema applied to each item
---@param default table|nil Default list; defaults to empty table if omitted
---@return flemma.config.schema.ListNode
function ListNode.new(item_schema, default)
  local self = setmetatable({}, ListNode)
  self._item_schema = item_schema
  self._default = default or {}
  return self
end

--- Return a deep copy of the default list.
---@return table
function ListNode:materialize()
  return vim.deepcopy(self._default)
end

--- Return true for all list nodes.
---@return boolean
function ListNode:is_list()
  return true
end

--- Return true if value is a table (list).
---@param value any
---@return boolean
function ListNode:validate(value)
  return type(value) == "table"
end

--- Validate a single item against the item schema.
---@param value any
---@return boolean
function ListNode:validate_item(value)
  return self._item_schema:validate(value)
end

M.ListNode = ListNode

-- =============================================================================
-- MapNode
-- =============================================================================

---@class flemma.config.schema.MapNode : flemma.config.schema.Node
---@field _key_schema flemma.config.schema.Node Schema for map keys
---@field _value_schema flemma.config.schema.Node Schema for map values
local MapNode = setmetatable({}, { __index = BaseNode })
MapNode.__index = MapNode

--- Create a new MapNode with key and value schemas.
---@param key_schema flemma.config.schema.Node Schema applied to each key
---@param value_schema flemma.config.schema.Node Schema applied to each value
---@return flemma.config.schema.MapNode
function MapNode.new(key_schema, value_schema)
  local self = setmetatable({}, MapNode)
  self._key_schema = key_schema
  self._value_schema = value_schema
  return self
end

--- Return an empty table as the default map.
---@return table
function MapNode:materialize()
  return {}
end

--- Return true if value is a table.
---@param value any
---@return boolean
function MapNode:validate(value)
  return type(value) == "table"
end

M.MapNode = MapNode

-- =============================================================================
-- OptionalNode
-- =============================================================================

---@class flemma.config.schema.OptionalNode : flemma.config.schema.Node
---@field _inner flemma.config.schema.Node The wrapped inner schema
local OptionalNode = setmetatable({}, { __index = BaseNode })
OptionalNode.__index = OptionalNode

--- Create a new OptionalNode wrapping an inner schema.
---@param inner_schema flemma.config.schema.Node
---@return flemma.config.schema.OptionalNode
function OptionalNode.new(inner_schema)
  local self = setmetatable({}, OptionalNode)
  self._inner = inner_schema
  return self
end

--- Delegate materialization to the inner schema.
--- Returns nil if the inner schema has no default.
---@return any
function OptionalNode:materialize()
  return self._inner:materialize()
end

--- Return true for nil (not present) or any value valid under the inner schema.
---@param value any
---@return boolean
function OptionalNode:validate(value)
  if value == nil then
    return true
  end
  return self._inner:validate(value)
end

M.OptionalNode = OptionalNode

-- =============================================================================
-- UnionNode
-- =============================================================================

---@class flemma.config.schema.UnionNode : flemma.config.schema.Node
---@field _branches flemma.config.schema.Node[] Ordered array of branch schemas
local UnionNode = setmetatable({}, { __index = BaseNode })
UnionNode.__index = UnionNode

--- Create a new UnionNode from an array of branch schemas.
---@param branches flemma.config.schema.Node[]
---@return flemma.config.schema.UnionNode
function UnionNode.new(branches)
  local self = setmetatable({}, UnionNode)
  self._branches = branches
  return self
end

--- Return the default from the first branch.
---@return any
function UnionNode:materialize()
  if #self._branches > 0 then
    return self._branches[1]:materialize()
  end
  return nil
end

--- Return true if value matches any branch schema.
---@param value any
---@return boolean
function UnionNode:validate(value)
  for _, branch in ipairs(self._branches) do
    if branch:validate(value) then
      return true
    end
  end
  return false
end

M.UnionNode = UnionNode

-- =============================================================================
-- FuncNode
-- =============================================================================

---@class flemma.config.schema.FuncNode : flemma.config.schema.Node
local FuncNode = setmetatable({}, { __index = BaseNode })
FuncNode.__index = FuncNode

--- Create a new FuncNode.
---@return flemma.config.schema.FuncNode
function FuncNode.new()
  return setmetatable({}, FuncNode)
end

--- Return nil (functions have no meaningful default).
---@return nil
function FuncNode:materialize()
  return nil
end

--- Return true if value is a function.
---@param value any
---@return boolean
function FuncNode:validate(value)
  return type(value) == "function"
end

M.FuncNode = FuncNode

-- =============================================================================
-- LoadableNode
-- =============================================================================

---@class flemma.config.schema.LoadableNode : flemma.config.schema.Node
local LoadableNode = setmetatable({}, { __index = BaseNode })
LoadableNode.__index = LoadableNode

--- Create a new LoadableNode.
---@return flemma.config.schema.LoadableNode
function LoadableNode.new()
  return setmetatable({}, LoadableNode)
end

--- Return nil (loadable paths have no meaningful default).
---@return nil
function LoadableNode:materialize()
  return nil
end

--- Return true if value is a string containing at least one dot
--- (Lua module path convention). Flemma URNs are not loadable module paths.
---@param value any
---@return boolean
function LoadableNode:validate(value)
  if type(value) ~= "string" then
    return false
  end
  return value:find(".", 1, true) ~= nil
end

M.LoadableNode = LoadableNode

return M
