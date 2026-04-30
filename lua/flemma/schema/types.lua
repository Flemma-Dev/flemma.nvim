--- Schema node type classes for the config schema DSL.
--- Defines the class hierarchy for all schema node types. Not part of the
--- public API — consumers use the factory functions in flemma.schema.
---@class flemma.schema.types
local M = {}

local symbols = require("flemma.symbols")
local loader = require("flemma.loader")

-- ---------------------------------------------------------------------------
-- Coerce context type (used by Node:coerce and consumers)
-- ---------------------------------------------------------------------------

--- Context passed to coerce functions for resolving config values.
--- Provides read access to the resolved config (global layers only).
---@class flemma.schema.CoerceContext
---@field get fun(path: string): any Resolve a config path from global layers (L10-L30)

-- ---------------------------------------------------------------------------
-- Node base class
-- ---------------------------------------------------------------------------

---@class flemma.schema.Node
---@field _description? string Human-readable description for EmmyLua generation
---@field _type_as? string Override generated type annotation
---@field _coerce? fun(value: any, ctx: flemma.schema.CoerceContext?): any Value transformer (runs before validation on writes; finalize() re-runs with ctx)
---@field _deferred_validator? fun(value: any, ctx: flemma.schema.CoerceContext): boolean, string? Semantic validator deferred to finalize (runs after coerce, on resolved values)
local Node = {}
Node.__index = Node

--- Attach a human-readable description (emitted as EmmyLua field comment).
---@param text string
---@return flemma.schema.Node self
function Node:describe(text)
  self._description = text
  return self
end

--- Override the generated EmmyLua type annotation.
---@param type_string string
---@return flemma.schema.Node self
function Node:type_as(type_string)
  self._type_as = type_string
  return self
end

--- Attach a value transformer.
--- Runs before validation on every proxy write. Also invoked by
--- `config.finalize()` to re-run transforms with a populated ctx.
--- Use for ergonomic shorthands (e.g., `bool → { enabled = bool }`)
--- and context-dependent expansions (e.g., preset names → tool lists).
---@param fn fun(value: any, ctx: flemma.schema.CoerceContext?): any Receives the raw value + optional context, returns the transformed value
---@return flemma.schema.Node self
function Node:coerce(fn)
  self._coerce = fn
  return self
end

--- Apply the coerce transformer to a value, if one is set.
--- Returns the value unchanged when no coerce function is attached.
---@param value any
---@param ctx flemma.schema.CoerceContext? Context for config lookups (nil during boot)
---@return any
function Node:apply_coerce(value, ctx)
  if self._coerce then
    return self._coerce(value, ctx)
  end
  return value
end

--- Whether this node has a coerce transformer.
---@return boolean
function Node:has_coerce()
  return self._coerce ~= nil
end

--- Return the coerce function, or nil if none.
---@return (fun(value: any, ctx: flemma.schema.CoerceContext?): any)?
function Node:get_coerce()
  return self._coerce
end

--- Attach a deferred semantic validator.
--- Unlike validate_value() (structural, runs at write time), deferred validators
--- run at finalize() time when the full runtime state is available (e.g., tool
--- registry populated, presets resolved). The validator is a pure predicate —
--- severity is the reporter's decision, not the validator's.
---@param fn fun(value: any, ctx: flemma.schema.CoerceContext): boolean, string? Receives the resolved value + context, returns ok + optional error message
---@return flemma.schema.Node self
function Node:validate(fn)
  self._deferred_validator = fn
  return self
end

--- Whether this node has a deferred semantic validator.
---@return boolean
function Node:has_deferred_validator()
  return self._deferred_validator ~= nil
end

--- Return the deferred validator function, or nil if none.
---@return (fun(value: any, ctx: flemma.schema.CoerceContext): boolean, string?)?
function Node:get_deferred_validator()
  return self._deferred_validator
end

--- Whether this node has a meaningful default value to materialize.
---@return boolean
function Node:has_default()
  return false
end

--- Return the default value for this node, or nil if none.
---@return any
function Node:materialize()
  return nil
end

--- Whether this node represents a list (supports append/remove/prepend ops).
---@return boolean
function Node:is_list()
  return false
end

--- Whether this node represents a fixed-shape object (supports sub-key navigation).
--- Base implementation returns false; ObjectNode overrides to return true.
--- Used by the proxy to distinguish navigation nodes from leaf nodes.
---@return boolean
function Node:is_object()
  return false
end

--- Return the inner schema for nodes that wrap another node (e.g. OptionalNode).
--- Base implementation returns nil; OptionalNode overrides to return its inner schema.
--- Used by schema navigation to unwrap optional wrappers during path traversal.
---@return flemma.schema.Node?
function Node:get_inner_schema()
  return nil
end

--- Return the child schema for the given key. Base returns nil; ObjectNode overrides.
--- Safe to call on any node: non-object nodes have no children and return nil.
---@param _key string
---@return flemma.schema.Node?
function Node:get_child_schema(_key)
  return nil
end

--- Resolve an alias key to its canonical sub-path at this schema level.
--- Base implementation returns nil; ObjectNode overrides with real alias logic.
--- Safe to call on any node: non-object nodes have no aliases.
---@param _key string
---@return string?
function Node:resolve_alias(_key)
  return nil
end

--- Return the item schema for list nodes.
--- Base implementation returns nil; ListNode overrides to return its item schema.
--- Used by the proxy to construct list proxies with item-level validation.
---@return flemma.schema.Node?
function Node:get_item_schema()
  return nil
end

--- Whether this node has a list part (ObjectNode with :allow_list()).
--- Base implementation returns false; ObjectNode overrides.
---@return boolean
function Node:has_list_part()
  return false
end

--- Return the list item schema for the list part (ObjectNode with :allow_list()).
--- Base implementation returns nil; ObjectNode overrides.
---@return flemma.schema.Node?
function Node:get_list_item_schema()
  return nil
end

--- Whether this node has a DISCOVER callback for lazily resolving unknown keys.
--- Base implementation returns false; ObjectNode overrides.
---@return boolean
function Node:has_discover()
  return false
end

--- Whether this node has a statically defined field (not DISCOVER-resolved).
--- Base implementation returns false; ObjectNode overrides.
---@param _key string
---@return boolean
function Node:has_field(_key)
  return false
end

--- Iterate over all known fields (static + DISCOVER-cached) as (key, schema) pairs.
--- Base implementation returns an empty iterator; ObjectNode overrides.
--- Used by the facade's materialize() to walk the schema tree.
---@return fun(t: table<string, flemma.schema.Node>, k?: string): string, flemma.schema.Node
---@return table<string, flemma.schema.Node>
function Node:all_known_fields()
  return pairs({})
end

--- Validate a value against this schema node.
--- Returns true on success, false + error message on failure.
---@param _value any
---@return boolean, string?
function Node:validate_value(_value)
  return true
end

--- Serialize this schema node to a JSON Schema table.
--- Each concrete node type overrides this with its own serialization.
---@return table
function Node:to_json_schema()
  error("Schema node does not support JSON Schema serialization")
end

--- Whether this node represents an optional field (field can be absent).
--- Used by ObjectNode:to_json_schema() to compute the `required` array.
---@return boolean
function Node:is_optional()
  return false
end

-- ---------------------------------------------------------------------------
-- JSON Schema helpers
-- ---------------------------------------------------------------------------

--- Add description and default to a JSON Schema table when present.
---@param result table The JSON Schema table being built
---@param node flemma.schema.Node The source schema node
---@return table result The same table, mutated in place
local function add_common_json_schema_fields(result, node)
  if node._description then
    result.description = node._description
  end
  if node:has_default() then
    result.default = node:materialize()
  end
  return result
end

-- ---------------------------------------------------------------------------
-- ScalarNode base (string, number, boolean)
-- ---------------------------------------------------------------------------

---@class flemma.schema.ScalarNode : flemma.schema.Node
---@field _default? any Default scalar value (nil means no default)
---@field _lua_type string Expected Lua type string (from type())
local ScalarNode = setmetatable({}, { __index = Node })
ScalarNode.__index = ScalarNode

--- Whether this node has a meaningful default value to materialize.
--- Uses `_default ~= nil`, which is safe for boolean defaults:
--- `false ~= nil` is `true` in Lua, so a false default is correctly detected.
---@return boolean
function ScalarNode:has_default()
  return self._default ~= nil
end

---@return any
function ScalarNode:materialize()
  return self._default
end

---@param value any
---@return boolean, string?
function ScalarNode:validate_value(value)
  if type(value) ~= self._lua_type then
    return false, "expected " .. self._lua_type .. ", got " .. type(value)
  end
  return true
end

-- ---------------------------------------------------------------------------
-- StringNode
-- ---------------------------------------------------------------------------

---@class flemma.schema.StringNode : flemma.schema.ScalarNode
---@field _default? string
local StringNode = setmetatable({}, { __index = ScalarNode })
StringNode.__index = StringNode

---@param default? string
---@return flemma.schema.StringNode
function StringNode.new(default)
  local node = setmetatable({}, StringNode)
  node._lua_type = "string"
  node._default = default
  return node
end

---@return table
function StringNode:to_json_schema()
  return add_common_json_schema_fields({ type = "string" }, self)
end

-- ---------------------------------------------------------------------------
-- NumberNode (any number, including floats)
-- ---------------------------------------------------------------------------

---@class flemma.schema.NumberNode : flemma.schema.ScalarNode
---@field _default? number
local NumberNode = setmetatable({}, { __index = ScalarNode })
NumberNode.__index = NumberNode

---@param default? number
---@return flemma.schema.NumberNode
function NumberNode.new(default)
  local node = setmetatable({}, NumberNode)
  node._lua_type = "number"
  node._default = default
  return node
end

---@return table
function NumberNode:to_json_schema()
  return add_common_json_schema_fields({ type = "number" }, self)
end

-- ---------------------------------------------------------------------------
-- BooleanNode
-- ---------------------------------------------------------------------------

---@class flemma.schema.BooleanNode : flemma.schema.ScalarNode
---@field _default? boolean
local BooleanNode = setmetatable({}, { __index = ScalarNode })
BooleanNode.__index = BooleanNode

---@param default? boolean
---@return flemma.schema.BooleanNode
function BooleanNode.new(default)
  local node = setmetatable({}, BooleanNode)
  node._lua_type = "boolean"
  node._default = default
  return node
end

---@return table
function BooleanNode:to_json_schema()
  return add_common_json_schema_fields({ type = "boolean" }, self)
end

-- ---------------------------------------------------------------------------
-- IntegerNode (number that is a whole number)
-- ---------------------------------------------------------------------------

---@class flemma.schema.IntegerNode : flemma.schema.ScalarNode
---@field _default? integer
local IntegerNode = setmetatable({}, { __index = ScalarNode })
IntegerNode.__index = IntegerNode

---@param value any
---@return boolean, string?
function IntegerNode:validate_value(value)
  if type(value) ~= "number" then
    return false, "expected integer, got " .. type(value)
  elseif value ~= math.floor(value) then
    return false, "expected integer, got float (" .. tostring(value) .. ")"
  end
  return true
end

---@param default? integer
---@return flemma.schema.IntegerNode
function IntegerNode.new(default)
  local node = setmetatable({}, IntegerNode)
  node._lua_type = "number"
  node._default = default
  return node
end

---@return table
function IntegerNode:to_json_schema()
  return add_common_json_schema_fields({ type = "integer" }, self)
end

-- ---------------------------------------------------------------------------
-- EnumNode
-- ---------------------------------------------------------------------------

---@class flemma.schema.EnumNode : flemma.schema.Node
---@field _values string[] Allowed values
---@field _default? any Default enum value
local EnumNode = setmetatable({}, { __index = Node })
EnumNode.__index = EnumNode

---@return boolean
function EnumNode:has_default()
  return self._default ~= nil
end

---@return any
function EnumNode:materialize()
  return self._default
end

---@param value any
---@return boolean, string?
function EnumNode:validate_value(value)
  for _, allowed in ipairs(self._values) do
    if value == allowed then
      return true
    end
  end
  local quoted = {}
  for _, v in ipairs(self._values) do
    table.insert(quoted, '"' .. tostring(v) .. '"')
  end
  return false, "expected one of [" .. table.concat(quoted, ", ") .. "], got " .. tostring(value)
end

---@param values string[]
---@param default? any
---@return flemma.schema.EnumNode
function EnumNode.new(values, default)
  local node = setmetatable({}, EnumNode)
  node._values = values
  node._default = default
  return node
end

---@return table
function EnumNode:to_json_schema()
  local result = { type = "string", enum = vim.deepcopy(self._values) }
  return add_common_json_schema_fields(result, self)
end

-- ---------------------------------------------------------------------------
-- ListNode
-- ---------------------------------------------------------------------------

---@class flemma.schema.ListNode : flemma.schema.Node
---@field _item_schema flemma.schema.Node Schema for each item
---@field _default? any[] Default list value
local ListNode = setmetatable({}, { __index = Node })
ListNode.__index = ListNode

---@return boolean
function ListNode:is_list()
  return true
end

---@return boolean
function ListNode:has_default()
  return self._default ~= nil
end

---@return any[]?
function ListNode:materialize()
  if self._default then
    return vim.deepcopy(self._default)
  end
  return nil
end

---@param value any
---@return boolean, string?
function ListNode:validate_value(value)
  if type(value) ~= "table" then
    return false, "expected list (table), got " .. type(value)
  end
  for i, item in ipairs(value) do
    local ok, err = self._item_schema:validate_value(item)
    if not ok then
      return false, "item[" .. i .. "]: " .. (err or "invalid")
    end
  end
  return true
end

--- Validate a single item against the item schema.
---@param item any
---@return boolean, string?
function ListNode:validate_item(item)
  return self._item_schema:validate_value(item)
end

--- Return the item schema for this list node.
---@return flemma.schema.Node
function ListNode:get_item_schema()
  return self._item_schema
end

---@param item_schema flemma.schema.Node
---@param default? any[]
---@return flemma.schema.ListNode
function ListNode.new(item_schema, default)
  local node = setmetatable({}, ListNode)
  node._item_schema = item_schema
  node._default = default
  return node
end

---@return table
function ListNode:to_json_schema()
  local result = {
    type = "array",
    items = self._item_schema:to_json_schema(),
  }
  return add_common_json_schema_fields(result, self)
end

-- ---------------------------------------------------------------------------
-- MapNode
-- ---------------------------------------------------------------------------

---@class flemma.schema.MapNode : flemma.schema.Node
---@field _key_schema flemma.schema.Node Schema for map keys
---@field _value_schema flemma.schema.Node Schema for map values
---@field _default? table Default map value
local MapNode = setmetatable({}, { __index = Node })
MapNode.__index = MapNode

---@param value any
---@return boolean, string?
function MapNode:validate_value(value)
  if type(value) ~= "table" then
    return false, "expected map (table), got " .. type(value)
  end
  for k, v in pairs(value) do
    local ok, err = self._key_schema:validate_value(k)
    if not ok then
      return false, "key " .. tostring(k) .. ": " .. (err or "invalid")
    end
    ok, err = self._value_schema:validate_value(v)
    if not ok then
      return false, "value[" .. tostring(k) .. "]: " .. (err or "invalid")
    end
  end
  return true
end

---@return boolean
function MapNode:has_default()
  return self._default ~= nil
end

---@return table?
function MapNode:materialize()
  if self._default then
    return vim.deepcopy(self._default)
  end
  return nil
end

---@param key_schema flemma.schema.Node
---@param value_schema flemma.schema.Node
---@param default? table
---@return flemma.schema.MapNode
function MapNode.new(key_schema, value_schema, default)
  local node = setmetatable({}, MapNode)
  node._key_schema = key_schema
  node._value_schema = value_schema
  node._default = default
  return node
end

--- Delegate deferred validator to the key schema. When the key schema has a
--- deferred validator, MapNode wraps it to validate each key in a set op table.
---@return boolean
function MapNode:has_deferred_validator()
  return self._deferred_validator ~= nil or self._key_schema:has_deferred_validator()
end

--- Return a deferred validator that validates map keys when the key schema has
--- one. For set ops with a table value, validate_ops() calls this on the whole
--- table — the wrapper iterates keys and delegates to the key schema's validator.
---@return (fun(value: any, ctx: flemma.schema.CoerceContext): boolean, string?)?
function MapNode:get_deferred_validator()
  if self._deferred_validator then
    return self._deferred_validator
  end
  local key_validator = self._key_schema:get_deferred_validator()
  if not key_validator then
    return nil
  end
  return function(value, ctx)
    if type(value) ~= "table" then
      return true
    end
    for k, _ in pairs(value) do
      local ok, err = key_validator(k, ctx)
      if not ok then
        return false, err
      end
    end
    return true
  end
end

---@return table
function MapNode:to_json_schema()
  local result = {
    type = "object",
    additionalProperties = self._value_schema:to_json_schema(),
  }
  return add_common_json_schema_fields(result, self)
end

-- ---------------------------------------------------------------------------
-- ObjectNode
-- ---------------------------------------------------------------------------

---@class flemma.schema.ObjectNode : flemma.schema.Node
---@field _fields table<string, flemma.schema.Node> Named child schemas
---@field _aliases table<string, string> Alias key → canonical path (dot-delimited; traversed by proxy/store, not schema)
---@field _discover? fun(key: string): flemma.schema.Node? Lazy resolver
---@field _discover_cache table<string, flemma.schema.Node> Cached results
---@field _strict boolean Whether unknown keys are rejected (default true)
---@field _list_schema? flemma.schema.Node Item schema for the list part (set via :allow_list())
local ObjectNode = setmetatable({}, { __index = Node })
ObjectNode.__index = ObjectNode

---@return boolean
function ObjectNode:is_object()
  return true
end

---@return boolean
function ObjectNode:has_default()
  for _, child in pairs(self._fields) do
    if child:has_default() then
      return true
    end
  end
  return false
end

--- Materialize static field defaults only. DISCOVER-resolved schemas are NOT
--- included here — their defaults are materialized separately via
--- `config.register_module_defaults()` after module registration. The runtime
--- `config.materialize(bufnr)` path uses `all_known_fields()` (which includes
--- both static and DISCOVER-cached fields) so resolved config is always complete.
---@return table<string, any>?
function ObjectNode:materialize()
  local result = {}
  local has_any = false
  for k, child in pairs(self._fields) do
    if child:has_default() then
      result[k] = child:materialize()
      has_any = true
    end
  end
  return has_any and result or nil
end

--- Resolve an alias key to its canonical path.
--- Returns the canonical path string (may contain dots) or nil if not an alias.
--- Real fields are not aliases — returns nil for real field names.
---@param key string
---@return string?
function ObjectNode:resolve_alias(key)
  -- Real fields take priority over aliases
  if self._fields[key] then
    return nil
  end
  return self._aliases[key]
end

--- Whether this object has a DISCOVER callback.
---@return boolean
function ObjectNode:has_discover()
  return self._discover ~= nil
end

--- Whether this object has a statically defined field (not DISCOVER-resolved).
---@param key string
---@return boolean
function ObjectNode:has_field(key)
  return self._fields[key] ~= nil
end

--- Iterate over all known fields: static fields first, then DISCOVER-cached entries.
--- Returns (key, schema) pairs for every field the schema currently knows about.
---@return fun(t: table<string, flemma.schema.Node>, k?: string): string, flemma.schema.Node
---@return table<string, flemma.schema.Node>
function ObjectNode:all_known_fields()
  local combined = {}
  for k, v in pairs(self._fields) do
    combined[k] = v
  end
  for k, v in pairs(self._discover_cache) do
    combined[k] = v
  end
  return pairs(combined)
end

--- Get the schema node for a direct child key.
--- Does NOT resolve aliases — call resolve_alias() first if needed.
--- Invokes the DISCOVER callback for unknown keys (cached after first resolution).
---@param key string
---@return flemma.schema.Node?
function ObjectNode:get_child_schema(key)
  -- Real field takes priority
  if self._fields[key] then
    return self._fields[key]
  end
  -- DISCOVER for unknown keys
  if self._discover then
    if self._discover_cache[key] then
      return self._discover_cache[key]
    end
    local discovered = self._discover(key)
    if discovered then
      self._discover_cache[key] = discovered
      return discovered
    end
  end
  return nil
end

--- Validate an object value against this schema.
---
--- Alias keys (defined in symbols.ALIASES) are silently passed through without
--- value validation — alias resolution and value dispatch are the proxy/store's
--- responsibility, not the schema's. Only real fields and DISCOVER-resolved keys
--- have their values validated here.
---@param value any
---@return boolean, string?
function ObjectNode:validate_value(value)
  if type(value) ~= "table" then
    return false, "expected table, got " .. type(value)
  end
  for k, v in pairs(value) do
    -- Skip symbol keys (ALIASES, DISCOVER, etc.) — only validate string keys
    if type(k) == "string" then
      local child = self:get_child_schema(k)
      if child == nil then
        -- Alias keys: the proxy/store redirects these; no value to validate.
        -- Truly unknown keys on strict objects are rejected.
        if not self._aliases[k] and self._strict then
          return false, 'unknown key "' .. k .. '"'
        end
      else
        local ok, err = child:validate_value(v)
        if not ok then
          return false, k .. ": " .. (err or "invalid")
        end
      end
    end
  end
  return true
end

--- Set strict mode (reject unknown keys). This is the default.
---@return flemma.schema.ObjectNode self
function ObjectNode:strict()
  self._strict = true
  return self
end

--- Set passthrough mode (allow unknown keys).
---@return flemma.schema.ObjectNode self
function ObjectNode:passthrough()
  self._strict = false
  return self
end

--- Enable list operations on this object's own path.
--- The object retains its named fields for sub-path navigation while also
--- accepting list ops (set with array, append, remove, prepend) validated
--- against the given item schema. Mirrors Lua's mixed table semantics.
---@param item_schema flemma.schema.Node Schema for each list item
---@return flemma.schema.ObjectNode self
function ObjectNode:allow_list(item_schema)
  self._list_schema = item_schema
  return self
end

--- Whether this object also accepts list operations on its own path.
---@return boolean
function ObjectNode:has_list_part()
  return self._list_schema ~= nil
end

--- Return the list item schema (set via :allow_list()), or nil.
---@return flemma.schema.Node?
function ObjectNode:get_list_item_schema()
  return self._list_schema
end

--- Create a new ObjectNode by cloning self and merging additional fields.
--- Accepts an ObjectNode (merges its fields), a raw table (processed like
--- the s.object() constructor argument, including symbol keys), or nil (clone).
---@param other table?
---@return flemma.schema.ObjectNode
function ObjectNode:extend(other)
  if other ~= nil and type(other) ~= "table" then
    error("ObjectNode:extend(): expected ObjectNode, table, or nil — got " .. type(other), 2)
  end
  local node = setmetatable({}, ObjectNode)
  -- Clone self
  node._fields = {}
  for k, v in pairs(self._fields) do
    node._fields[k] = v
  end
  node._aliases = {}
  for k, v in pairs(self._aliases) do
    node._aliases[k] = v
  end
  node._discover = self._discover
  node._discover_cache = {}
  node._strict = self._strict
  node._list_schema = self._list_schema
  node._coerce = self._coerce
  node._description = self._description
  node._type_as = self._type_as
  if other == nil then
    return node
  end
  -- Merge other
  if getmetatable(other) == ObjectNode then
    for k, v in pairs(other._fields) do
      node._fields[k] = v
    end
  else
    for k, v in pairs(other) do
      if k == symbols.ALIASES then
        for ak, av in pairs(v) do
          node._aliases[ak] = av
        end
      elseif k == symbols.DISCOVER then
        node._discover = v
      else
        node._fields[k] = v
      end
    end
  end
  return node
end

--- Construct an ObjectNode from a fields table.
--- The fields table may include symbol keys:
---   [symbols.ALIASES] = { alias = "canonical.path" }
---   [symbols.DISCOVER] = function(key) return schema_node or nil end
---@param fields table
---@return flemma.schema.ObjectNode
function ObjectNode.new(fields)
  local node = setmetatable({}, ObjectNode)
  node._fields = {}
  node._aliases = {}
  node._discover = nil
  node._discover_cache = {}
  node._strict = true

  for k, v in pairs(fields) do
    if k == symbols.ALIASES then
      node._aliases = v
    elseif k == symbols.DISCOVER then
      node._discover = v
    else
      node._fields[k] = v
    end
  end

  return node
end

--- Serialize this object schema to a JSON Schema table.
--- Fields wrapped in OptionalNode are omitted from `required`.
--- Symbol keys (ALIASES, DISCOVER) are ignored.
--- Properties and required are sorted alphabetically for determinism.
---@return table
function ObjectNode:to_json_schema()
  local properties = {}
  local required = {}

  -- Sort field names alphabetically for deterministic output
  local field_names = {}
  for name, _ in pairs(self._fields) do
    table.insert(field_names, name)
  end
  table.sort(field_names)

  for _, name in ipairs(field_names) do
    local field_schema = self._fields[name]
    if field_schema:is_optional() then
      -- Unwrap OptionalNode — the property type is the inner schema,
      -- and the field is excluded from the required array
      properties[name] = field_schema:get_inner_schema():to_json_schema()
    else
      properties[name] = field_schema:to_json_schema()
      table.insert(required, name)
    end
  end

  local result = {
    type = "object",
    properties = properties,
  }
  if #required > 0 then
    result.required = required
  end
  if self._strict then
    result.additionalProperties = false
  end
  return add_common_json_schema_fields(result, self)
end

-- ---------------------------------------------------------------------------
-- OptionalNode
-- ---------------------------------------------------------------------------

---@class flemma.schema.OptionalNode : flemma.schema.Node
---@field _inner flemma.schema.Node The wrapped schema (nil is also valid)
local OptionalNode = setmetatable({}, { __index = Node })
OptionalNode.__index = OptionalNode

---@return boolean
function OptionalNode:has_default()
  return self._inner:has_default()
end

---@return any
function OptionalNode:materialize()
  return self._inner:materialize()
end

---@return boolean
function OptionalNode:is_list()
  return self._inner:is_list()
end

---@return boolean
function OptionalNode:is_object()
  return self._inner:is_object()
end

---@return boolean
function OptionalNode:has_list_part()
  return self._inner:has_list_part()
end

---@return flemma.schema.Node?
function OptionalNode:get_list_item_schema()
  return self._inner:get_list_item_schema()
end

--- Delegate item schema lookup to inner node.
--- Enables OptionalNode(ListNode) and OptionalNode(UnionNode with list branch)
--- to be detected as list-capable by the proxy's get_item_schema() check.
---@return flemma.schema.Node?
function OptionalNode:get_item_schema()
  return self._inner:get_item_schema()
end

---@return boolean
function OptionalNode:has_discover()
  return self._inner:has_discover()
end

---@return fun(t: table<string, flemma.schema.Node>, k?: string): string, flemma.schema.Node
---@return table<string, flemma.schema.Node>
function OptionalNode:all_known_fields()
  return self._inner:all_known_fields()
end

---@return flemma.schema.Node
function OptionalNode:get_inner_schema()
  return self._inner
end

--- Delegate coerce to the inner schema. Nil values bypass coercion.
---@param value any
---@param ctx flemma.schema.CoerceContext? Context for config lookups (nil during boot)
---@return any
function OptionalNode:apply_coerce(value, ctx)
  if value == nil then
    return nil
  end
  return self._inner:apply_coerce(value, ctx)
end

--- Delegate coerce detection to the inner schema.
---@return boolean
function OptionalNode:has_coerce()
  return self._inner:has_coerce()
end

--- Delegate coerce retrieval to the inner schema.
---@return (fun(value: any, ctx: flemma.schema.CoerceContext?): any)?
function OptionalNode:get_coerce()
  return self._inner:get_coerce()
end

--- Delegate deferred validator detection to the inner schema.
---@return boolean
function OptionalNode:has_deferred_validator()
  return self._inner:has_deferred_validator()
end

--- Delegate deferred validator retrieval to the inner schema.
---@return (fun(value: any, ctx: flemma.schema.CoerceContext): boolean, string?)?
function OptionalNode:get_deferred_validator()
  return self._inner:get_deferred_validator()
end

---@param value any
---@return boolean, string?
function OptionalNode:validate_value(value)
  if value == nil then
    return true
  end
  return self._inner:validate_value(value)
end

---@param inner_schema flemma.schema.Node
---@return flemma.schema.OptionalNode
function OptionalNode.new(inner_schema)
  local node = setmetatable({}, OptionalNode)
  node._inner = inner_schema
  return node
end

--- Serialize the inner schema to JSON Schema.
--- The "optional" aspect is expressed by the parent ObjectNode omitting
--- this field from its `required` array — not in the type itself.
---@return table
function OptionalNode:to_json_schema()
  local result = self._inner:to_json_schema()
  if self._description then
    result.description = self._description
  end
  return result
end

---@return boolean
function OptionalNode:is_optional()
  return true
end

-- ---------------------------------------------------------------------------
-- NullableNode
-- ---------------------------------------------------------------------------

--- Nullable wrapper: the value must match the inner schema OR be null/nil.
--- Unlike OptionalNode (which controls whether a field can be absent),
--- NullableNode means the field is present but its value can be null.
--- In JSON Schema: the field appears in `required`, and `type` includes "null".
---@class flemma.schema.NullableNode : flemma.schema.Node
---@field _inner flemma.schema.Node The wrapped schema (null is also valid)
local NullableNode = setmetatable({}, { __index = Node })
NullableNode.__index = NullableNode

---@return boolean
function NullableNode:has_default()
  return self._inner:has_default()
end

---@return any
function NullableNode:materialize()
  return self._inner:materialize()
end

---@return boolean
function NullableNode:is_list()
  return self._inner:is_list()
end

---@return boolean
function NullableNode:is_object()
  return self._inner:is_object()
end

---@return boolean
function NullableNode:has_list_part()
  return self._inner:has_list_part()
end

---@return flemma.schema.Node?
function NullableNode:get_list_item_schema()
  return self._inner:get_list_item_schema()
end

--- Delegate item schema lookup to inner node.
---@return flemma.schema.Node?
function NullableNode:get_item_schema()
  return self._inner:get_item_schema()
end

---@return boolean
function NullableNode:has_discover()
  return self._inner:has_discover()
end

---@return fun(t: table<string, flemma.schema.Node>, k?: string): string, flemma.schema.Node
---@return table<string, flemma.schema.Node>
function NullableNode:all_known_fields()
  return self._inner:all_known_fields()
end

---@return flemma.schema.Node
function NullableNode:get_inner_schema()
  return self._inner
end

--- Delegate coerce to the inner schema. Nil values bypass coercion.
---@param value any
---@param ctx flemma.schema.CoerceContext?
---@return any
function NullableNode:apply_coerce(value, ctx)
  if value == nil then
    return nil
  end
  return self._inner:apply_coerce(value, ctx)
end

---@return boolean
function NullableNode:has_coerce()
  return self._inner:has_coerce()
end

---@return (fun(value: any, ctx: flemma.schema.CoerceContext?): any)?
function NullableNode:get_coerce()
  return self._inner:get_coerce()
end

---@return boolean
function NullableNode:has_deferred_validator()
  return self._inner:has_deferred_validator()
end

---@return (fun(value: any, ctx: flemma.schema.CoerceContext): boolean, string?)?
function NullableNode:get_deferred_validator()
  return self._inner:get_deferred_validator()
end

---@param value any
---@return boolean, string?
function NullableNode:validate_value(value)
  if value == nil then
    return true
  end
  return self._inner:validate_value(value)
end

--- Serialize to JSON Schema with "null" added to the type.
--- For simple types (string, number, etc.), produces `type: ["string", "null"]`.
--- For complex types (anyOf, etc.), wraps in `anyOf: [inner, {type: "null"}]`.
---@return table
function NullableNode:to_json_schema()
  local inner_schema = self._inner:to_json_schema()
  if inner_schema.type then
    if type(inner_schema.type) == "string" then
      inner_schema.type = { inner_schema.type, "null" }
    elseif type(inner_schema.type) == "table" then
      local has_null = false
      for _, t in ipairs(inner_schema.type) do
        if t == "null" then
          has_null = true
          break
        end
      end
      if not has_null then
        table.insert(inner_schema.type, "null")
      end
    end
  else
    inner_schema = {
      anyOf = { inner_schema, { type = "null" } },
    }
  end
  if self._description then
    inner_schema.description = self._description
  end
  return inner_schema
end

---@param inner_schema flemma.schema.Node
---@return flemma.schema.NullableNode
function NullableNode.new(inner_schema)
  local node = setmetatable({}, NullableNode)
  node._inner = inner_schema
  return node
end

-- ---------------------------------------------------------------------------
-- UnionNode
-- ---------------------------------------------------------------------------

--- Union schema node: value must match one of the given branches.
---
--- **Default semantics:** A union's default is the default of the *first*
--- branch that has one. Branch ordering matters — place the branch whose
--- default you want materialized first. For example:
---
---   s.union(s.boolean(false), s.enum({ "underline", "underdashed" }))
---
--- materializes `false` because the boolean branch is checked first. If
--- the branches were swapped, the enum (which has no default) would be
--- checked first and the union would have no default.
---
--- **List semantics:** A union with a list branch (e.g., `s.union(s.list(...), s.func())`)
--- is treated as a list-capable field. `is_list()` returns true and `get_item_schema()`
--- returns the first list branch's item schema. This enables the store to use list
--- resolution (bottom-up accumulation) and the proxy to return a ListProxy for write
--- access, while still accepting non-list values (functions, strings) via `set` ops.
---@class flemma.schema.UnionNode : flemma.schema.Node
---@field _branches flemma.schema.Node[] Schemas to try in order
local UnionNode = setmetatable({}, { __index = Node })
UnionNode.__index = UnionNode

--- Whether this union has a default (delegates to branches in order).
---@return boolean
function UnionNode:has_default()
  for _, branch in ipairs(self._branches) do
    if branch:has_default() then
      return true
    end
  end
  return false
end

--- Return the default from the first branch that has one.
---@return any
function UnionNode:materialize()
  for _, branch in ipairs(self._branches) do
    if branch:has_default() then
      return branch:materialize()
    end
  end
  return nil
end

---@param value any
---@return boolean, string?
function UnionNode:validate_value(value)
  local errors = {}
  for _, branch in ipairs(self._branches) do
    local ok, err = branch:validate_value(value)
    if ok then
      return true
    end
    table.insert(errors, err or "invalid")
  end
  return false, "no union branch matched: " .. table.concat(errors, "; ")
end

--- Whether this union has a list branch (any branch where is_list() is true).
--- Enables the store to use list resolution and the proxy to offer list ops.
---@return boolean
function UnionNode:is_list()
  for _, branch in ipairs(self._branches) do
    if branch:is_list() then
      return true
    end
  end
  return false
end

--- Return the item schema from the first list branch.
--- Used by the proxy to construct a ListProxy with per-item validation.
--- Returns nil when no branch is a list.
---@return flemma.schema.Node?
function UnionNode:get_item_schema()
  for _, branch in ipairs(self._branches) do
    local item = branch:get_item_schema()
    if item then
      return item
    end
  end
  return nil
end

---@param branches flemma.schema.Node[]
---@return flemma.schema.UnionNode
function UnionNode.new(branches)
  local node = setmetatable({}, UnionNode)
  node._branches = branches
  return node
end

---@return table
function UnionNode:to_json_schema()
  local any_of = {}
  for _, branch in ipairs(self._branches) do
    table.insert(any_of, branch:to_json_schema())
  end
  local result = { anyOf = any_of }
  return add_common_json_schema_fields(result, self)
end

-- ---------------------------------------------------------------------------
-- LoadableNode
-- ---------------------------------------------------------------------------

---@class flemma.schema.LoadableNode : flemma.schema.StringNode
local LoadableNode = setmetatable({}, { __index = StringNode })
LoadableNode.__index = LoadableNode

---@param value any
---@return boolean, string?
function LoadableNode:validate_value(value)
  local ok, err = ScalarNode.validate_value(self, value)
  if not ok then
    return false, err
  end
  local load_ok, load_err = pcall(loader.assert_exists, value)
  if not load_ok then
    return false, tostring(load_err)
  end
  return true
end

---@param default? string
---@return flemma.schema.LoadableNode
function LoadableNode.new(default)
  local node = setmetatable({}, LoadableNode)
  node._lua_type = "string"
  node._default = default
  return node
end

--- Loadable paths are strings in JSON Schema context.
---@return table
function LoadableNode:to_json_schema()
  return add_common_json_schema_fields({ type = "string" }, self)
end

-- ---------------------------------------------------------------------------
-- FuncNode
-- ---------------------------------------------------------------------------

---@class flemma.schema.FuncNode : flemma.schema.Node
local FuncNode = setmetatable({}, { __index = Node })
FuncNode.__index = FuncNode

---@param value any
---@return boolean, string?
function FuncNode:validate_value(value)
  if type(value) ~= "function" then
    return false, "expected function, got " .. type(value)
  end
  return true
end

---@return flemma.schema.FuncNode
function FuncNode.new()
  return setmetatable({}, FuncNode)
end

--- Lua functions have no JSON Schema representation.
---@return table
function FuncNode:to_json_schema()
  error("FuncNode cannot be serialized to JSON Schema (Lua functions have no JSON representation)")
end

-- ---------------------------------------------------------------------------
-- LiteralNode
-- ---------------------------------------------------------------------------

--- Matches exactly one value (by equality). Useful for sentinel values like
--- `false` in unions where a full boolean type would be too permissive.
---
--- Unlike other node types, LiteralNode carries an explicit `_has_default`
--- flag because `nil` is a valid literal value — the `~= nil` shortcut used
--- by ScalarNode/EnumNode/MapNode cannot distinguish "no default" from
--- "default is nil".
---@class flemma.schema.LiteralNode : flemma.schema.Node
---@field _value any The exact value to match
---@field _has_default boolean Whether the literal carries a default
local LiteralNode = setmetatable({}, { __index = Node })
LiteralNode.__index = LiteralNode

---@return boolean
function LiteralNode:has_default()
  return self._has_default
end

---@return any
function LiteralNode:materialize()
  return self._value
end

---@param value any
---@return boolean, string?
function LiteralNode:validate_value(value)
  if value ~= self._value then
    return false, "expected " .. tostring(self._value) .. ", got " .. tostring(value)
  end
  return true
end

---@param value any
---@param opts? { as_default?: boolean } Options (as_default defaults to true)
---@return flemma.schema.LiteralNode
function LiteralNode.new(value, opts)
  local node = setmetatable({}, LiteralNode)
  node._value = value
  node._has_default = not opts or opts.as_default ~= false
  return node
end

---@return table
function LiteralNode:to_json_schema()
  local result = {}
  local value = self._value
  if value == nil then
    result.type = "null"
  elseif type(value) == "string" then
    result.type = "string"
    result.const = value
  elseif type(value) == "number" then
    if value == math.floor(value) then
      result.type = "integer"
    else
      result.type = "number"
    end
    result.const = value
  elseif type(value) == "boolean" then
    result.type = "boolean"
    result.const = value
  else
    result.const = value
  end
  return add_common_json_schema_fields(result, self)
end

-- ---------------------------------------------------------------------------
-- Cross-type chainable modifiers
-- ---------------------------------------------------------------------------

--- Wrap this node in an OptionalNode (field can be absent).
--- Returns a new OptionalNode, not self — the chain continues on the wrapper.
---@return flemma.schema.OptionalNode
function Node:optional()
  return OptionalNode.new(self)
end

--- Wrap this node in a NullableNode (value can be null).
--- Returns a new NullableNode, not self — the chain continues on the wrapper.
---@return flemma.schema.NullableNode
function Node:nullable()
  return NullableNode.new(self)
end

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------

M.Node = Node
M.ScalarNode = ScalarNode
M.StringNode = StringNode
M.NumberNode = NumberNode
M.BooleanNode = BooleanNode
M.IntegerNode = IntegerNode
M.EnumNode = EnumNode
M.ListNode = ListNode
M.MapNode = MapNode
M.ObjectNode = ObjectNode
M.OptionalNode = OptionalNode
M.UnionNode = UnionNode
M.LoadableNode = LoadableNode
M.FuncNode = FuncNode
M.LiteralNode = LiteralNode
M.NullableNode = NullableNode

return M
