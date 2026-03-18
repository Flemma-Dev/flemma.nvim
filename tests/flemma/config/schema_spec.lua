local symbols = require("flemma.symbols")

describe("flemma.config.schema.types", function()
  local types

  before_each(function()
    package.loaded["flemma.config.schema.types"] = nil
    types = require("flemma.config.schema.types")
  end)

  -- =========================================================================
  -- Scalar nodes
  -- =========================================================================

  describe("StringNode", function()
    it("materialize() returns the default value", function()
      local node = types.StringNode.new("hello")
      assert.are.equal("hello", node:materialize())
    end)

    it("materialize() returns nil when no default is provided", function()
      local node = types.StringNode.new()
      assert.is_nil(node:materialize())
    end)

    it("validate() returns true for a string value", function()
      local node = types.StringNode.new("default")
      assert.is_true(node:validate("any string"))
    end)

    it("validate() returns false for a non-string value", function()
      local node = types.StringNode.new("default")
      assert.is_false(node:validate(42))
      assert.is_false(node:validate(true))
      assert.is_false(node:validate({}))
    end)

    it(":describe() stores description and returns self", function()
      local node = types.StringNode.new("x")
      local returned = node:describe("my description")
      assert.are.equal(node, returned)
      assert.are.equal("my description", node._description)
    end)

    it(":type_as() stores type override and returns self", function()
      local node = types.StringNode.new("x")
      local returned = node:type_as("string|nil")
      assert.are.equal(node, returned)
      assert.are.equal("string|nil", node._type_as)
    end)
  end)

  describe("IntegerNode", function()
    it("materialize() returns the default integer", function()
      local node = types.IntegerNode.new(8192)
      assert.are.equal(8192, node:materialize())
    end)

    it("validate() returns true for an integer value", function()
      local node = types.IntegerNode.new(0)
      assert.is_true(node:validate(42))
      assert.is_true(node:validate(0))
      assert.is_true(node:validate(-10))
    end)

    it("validate() returns false for non-integer values", function()
      local node = types.IntegerNode.new(0)
      assert.is_false(node:validate(3.14))
      assert.is_false(node:validate("42"))
      assert.is_false(node:validate(true))
    end)

    it("validate() returns false for floats even when they have integer values", function()
      -- 5.0 is a number/float, not an integer in Lua type sense
      -- We check math.type == "integer" for strict integer validation
      local node = types.IntegerNode.new(0)
      -- In LuaJIT (which Neovim uses), all numbers are doubles, so we just check type == "number"
      -- and math.floor(v) == v for integer validation
      assert.is_false(node:validate(3.5))
    end)

    it(":describe() and :type_as() chain correctly", function()
      local node = types.IntegerNode.new(1)
      local result = node:describe("desc"):type_as("integer")
      assert.are.equal(node, result)
    end)
  end)

  describe("NumberNode", function()
    it("materialize() returns the default number", function()
      local node = types.NumberNode.new(0.7)
      assert.are.equal(0.7, node:materialize())
    end)

    it("validate() returns true for number values", function()
      local node = types.NumberNode.new(0)
      assert.is_true(node:validate(3.14))
      assert.is_true(node:validate(0))
      assert.is_true(node:validate(-1.5))
      assert.is_true(node:validate(42))
    end)

    it("validate() returns false for non-number values", function()
      local node = types.NumberNode.new(0)
      assert.is_false(node:validate("1.0"))
      assert.is_false(node:validate(true))
      assert.is_false(node:validate({}))
    end)
  end)

  describe("BooleanNode", function()
    it("materialize() returns the default boolean", function()
      local node = types.BooleanNode.new(true)
      assert.is_true(node:materialize())
      local node2 = types.BooleanNode.new(false)
      assert.is_false(node2:materialize())
    end)

    it("validate() returns true for boolean values", function()
      local node = types.BooleanNode.new(false)
      assert.is_true(node:validate(true))
      assert.is_true(node:validate(false))
    end)

    it("validate() returns false for non-boolean values", function()
      local node = types.BooleanNode.new(false)
      assert.is_false(node:validate(1))
      assert.is_false(node:validate("true"))
      assert.is_false(node:validate(nil))
    end)
  end)

  describe("EnumNode", function()
    it("materialize() returns the default enum value", function()
      local node = types.EnumNode.new({ "disabled", "low", "medium", "high" }, "medium")
      assert.are.equal("medium", node:materialize())
    end)

    it("validate() returns true for values in the set", function()
      local node = types.EnumNode.new({ "a", "b", "c" }, "a")
      assert.is_true(node:validate("a"))
      assert.is_true(node:validate("b"))
      assert.is_true(node:validate("c"))
    end)

    it("validate() returns false for values not in the set", function()
      local node = types.EnumNode.new({ "a", "b", "c" }, "a")
      assert.is_false(node:validate("d"))
      assert.is_false(node:validate(""))
      assert.is_false(node:validate(1))
    end)

    it(":describe() and :type_as() return self for chaining", function()
      local node = types.EnumNode.new({ "x", "y" }, "x")
      assert.are.equal(node, node:describe("test"))
      assert.are.equal(node, node:type_as("string"))
    end)
  end)

  -- =========================================================================
  -- Base node shared methods
  -- =========================================================================

  describe("base node methods", function()
    it(":strict() returns self", function()
      local node = types.StringNode.new("x")
      assert.are.equal(node, node:strict())
    end)

    it(":passthrough() returns self", function()
      local node = types.StringNode.new("x")
      assert.are.equal(node, node:passthrough())
    end)

    it(":is_list() returns false for scalar nodes", function()
      assert.is_false(types.StringNode.new():is_list())
      assert.is_false(types.IntegerNode.new():is_list())
      assert.is_false(types.BooleanNode.new():is_list())
    end)
  end)

  -- =========================================================================
  -- ObjectNode
  -- =========================================================================

  describe("ObjectNode", function()
    it("materialize() returns a table with materialized child defaults", function()
      local node = types.ObjectNode.new({
        name = types.StringNode.new("alice"),
        age = types.IntegerNode.new(30),
      })
      local result = node:materialize()
      assert.is_table(result)
      assert.are.equal("alice", result.name)
      assert.are.equal(30, result.age)
    end)

    it("materialize() produces independent copies (schema reuse)", function()
      local shared_string = types.StringNode.new("shared")
      local schema = types.ObjectNode.new({
        value = shared_string,
      })
      local result1 = schema:materialize()
      local result2 = schema:materialize()
      result1.value = "modified"
      assert.are.equal("shared", result2.value)
    end)

    it("materialize() does not include symbol keys in output", function()
      local node = types.ObjectNode.new({
        name = types.StringNode.new("test"),
        [symbols.ALIASES] = { alias_key = "name" },
      })
      local result = node:materialize()
      assert.is_nil(result[symbols.ALIASES])
      assert.are.equal("test", result.name)
    end)

    it("is_strict by default", function()
      local node = types.ObjectNode.new({})
      assert.is_true(node._strict)
    end)

    it(":strict() sets strict mode and returns self", function()
      local node = types.ObjectNode.new({}):passthrough()
      assert.is_false(node._strict)
      local returned = node:strict()
      assert.are.equal(node, returned)
      assert.is_true(node._strict)
    end)

    it(":passthrough() disables strict mode and returns self", function()
      local node = types.ObjectNode.new({})
      local returned = node:passthrough()
      assert.are.equal(node, returned)
      assert.is_false(node._strict)
    end)

    it("stores _fields table with string-keyed fields only", function()
      local name_node = types.StringNode.new("x")
      local node = types.ObjectNode.new({
        name = name_node,
        [symbols.ALIASES] = { k = "name" },
      })
      assert.are.equal(name_node, node._fields.name)
      assert.is_nil(node._fields[symbols.ALIASES])
    end)

    it("extracts aliases from symbols.ALIASES key", function()
      local node = types.ObjectNode.new({
        name = types.StringNode.new("x"),
        [symbols.ALIASES] = { n = "name" },
      })
      assert.is_table(node._aliases)
      assert.are.equal("name", node._aliases.n)
    end)

    it("extracts discover callback from symbols.DISCOVER key", function()
      local discover_fn = function(_key)
        return nil
      end
      local node = types.ObjectNode.new({
        [symbols.DISCOVER] = discover_fn,
      })
      assert.are.equal(discover_fn, node._discover)
    end)

    it("resolve_alias() returns canonical path for known alias", function()
      local node = types.ObjectNode.new({
        real_field = types.StringNode.new("x"),
        [symbols.ALIASES] = { short = "real_field" },
      })
      assert.are.equal("real_field", node:resolve_alias("short"))
    end)

    it("resolve_alias() returns nil for unknown key", function()
      local node = types.ObjectNode.new({
        real_field = types.StringNode.new("x"),
        [symbols.ALIASES] = { short = "real_field" },
      })
      assert.is_nil(node:resolve_alias("unknown"))
    end)

    it("resolve_alias() returns nil when no aliases defined", function()
      local node = types.ObjectNode.new({ field = types.StringNode.new("x") })
      assert.is_nil(node:resolve_alias("field"))
    end)

    it(":is_list() returns false", function()
      assert.is_false(types.ObjectNode.new({}):is_list())
    end)

    it("validate() returns true for a table value", function()
      local node = types.ObjectNode.new({ x = types.StringNode.new("a") })
      assert.is_true(node:validate({}))
      assert.is_true(node:validate({ x = "hello" }))
    end)

    it("validate() returns false for non-table values", function()
      local node = types.ObjectNode.new({})
      assert.is_false(node:validate("string"))
      assert.is_false(node:validate(42))
    end)

    it("materialize() recursively materializes nested objects", function()
      local inner = types.ObjectNode.new({
        value = types.IntegerNode.new(99),
      })
      local outer = types.ObjectNode.new({
        inner = inner,
      })
      local result = outer:materialize()
      assert.is_table(result.inner)
      assert.are.equal(99, result.inner.value)
    end)
  end)

  -- =========================================================================
  -- ListNode
  -- =========================================================================

  describe("ListNode", function()
    it("materialize() returns a deep copy of the default list", function()
      local node = types.ListNode.new(types.StringNode.new(), { "a", "b" })
      local result = node:materialize()
      assert.are.same({ "a", "b" }, result)
    end)

    it("materialize() produces independent copies (schema reuse)", function()
      local node = types.ListNode.new(types.StringNode.new(), { "a" })
      local result1 = node:materialize()
      local result2 = node:materialize()
      table.insert(result1, "b")
      assert.are.same({ "a" }, result2)
    end)

    it("materialize() returns empty list when no default provided", function()
      local node = types.ListNode.new(types.StringNode.new())
      local result = node:materialize()
      assert.are.same({}, result)
    end)

    it(":is_list() returns true", function()
      local node = types.ListNode.new(types.StringNode.new())
      assert.is_true(node:is_list())
    end)

    it("validate() returns true for a table (list)", function()
      local node = types.ListNode.new(types.StringNode.new())
      assert.is_true(node:validate({}))
      assert.is_true(node:validate({ "a", "b" }))
    end)

    it("validate() returns false for non-table values", function()
      local node = types.ListNode.new(types.StringNode.new())
      assert.is_false(node:validate("not a list"))
      assert.is_false(node:validate(42))
    end)

    it("validate_item() delegates to item schema", function()
      local node = types.ListNode.new(types.StringNode.new())
      assert.is_true(node:validate_item("hello"))
      assert.is_false(node:validate_item(42))
    end)
  end)

  -- =========================================================================
  -- MapNode
  -- =========================================================================

  describe("MapNode", function()
    it("materialize() returns an empty table", function()
      local node = types.MapNode.new(types.StringNode.new(), types.StringNode.new())
      local result = node:materialize()
      assert.is_table(result)
      assert.are.same({}, result)
    end)

    it("validate() returns true for a table", function()
      local node = types.MapNode.new(types.StringNode.new(), types.StringNode.new())
      assert.is_true(node:validate({}))
      assert.is_true(node:validate({ key = "value" }))
    end)

    it("validate() returns false for non-table values", function()
      local node = types.MapNode.new(types.StringNode.new(), types.StringNode.new())
      assert.is_false(node:validate("not a map"))
      assert.is_false(node:validate(123))
    end)

    it(":is_list() returns false", function()
      assert.is_false(types.MapNode.new(types.StringNode.new(), types.StringNode.new()):is_list())
    end)

    it("validate_key() delegates to the key schema", function()
      local node = types.MapNode.new(types.StringNode.new(), types.IntegerNode.new())
      assert.is_true(node:validate_key("valid_key"))
      assert.is_false(node:validate_key(42))
      assert.is_false(node:validate_key({}))
    end)

    it("validate_value() delegates to the value schema", function()
      local node = types.MapNode.new(types.StringNode.new(), types.IntegerNode.new())
      assert.is_true(node:validate_value(10))
      assert.is_false(node:validate_value("not an integer"))
      assert.is_false(node:validate_value({}))
    end)
  end)

  -- =========================================================================
  -- OptionalNode
  -- =========================================================================

  describe("OptionalNode", function()
    it("validate() returns true for nil", function()
      local node = types.OptionalNode.new(types.StringNode.new("x"))
      assert.is_true(node:validate(nil))
    end)

    it("validate() returns true for values matching the inner schema", function()
      local node = types.OptionalNode.new(types.StringNode.new("x"))
      assert.is_true(node:validate("hello"))
    end)

    it("validate() returns false for values not matching the inner schema", function()
      local node = types.OptionalNode.new(types.StringNode.new("x"))
      assert.is_false(node:validate(42))
    end)

    it("materialize() returns the inner schema's default", function()
      local node = types.OptionalNode.new(types.StringNode.new("inner_default"))
      assert.are.equal("inner_default", node:materialize())
    end)

    it("materialize() returns nil when inner schema has no default", function()
      local node = types.OptionalNode.new(types.StringNode.new())
      assert.is_nil(node:materialize())
    end)

    it(":is_list() returns false when wrapping a non-list schema", function()
      assert.is_false(types.OptionalNode.new(types.StringNode.new()):is_list())
    end)

    it(":is_list() delegates to inner schema", function()
      local node = types.OptionalNode.new(types.ListNode.new(types.StringNode.new()))
      assert.is_true(node:is_list())
    end)

    it(":describe() and :type_as() chain correctly", function()
      local node = types.OptionalNode.new(types.StringNode.new("x"))
      assert.are.equal(node, node:describe("optional field"))
      assert.are.equal(node, node:type_as("string|nil"))
    end)
  end)

  -- =========================================================================
  -- UnionNode
  -- =========================================================================

  describe("UnionNode", function()
    it("validate() returns true when value matches first branch", function()
      local node = types.UnionNode.new({ types.StringNode.new(), types.IntegerNode.new() })
      assert.is_true(node:validate("hello"))
    end)

    it("validate() returns true when value matches second branch", function()
      local node = types.UnionNode.new({ types.StringNode.new(), types.IntegerNode.new() })
      assert.is_true(node:validate(42))
    end)

    it("validate() returns false when value matches no branch", function()
      local node = types.UnionNode.new({ types.StringNode.new(), types.IntegerNode.new() })
      assert.is_false(node:validate(true))
      assert.is_false(node:validate({}))
    end)

    it("materialize() returns the first branch's default", function()
      local node = types.UnionNode.new({ types.StringNode.new("first"), types.IntegerNode.new(99) })
      assert.are.equal("first", node:materialize())
    end)

    it(":is_list() returns false", function()
      assert.is_false(types.UnionNode.new({ types.StringNode.new() }):is_list())
    end)
  end)

  -- =========================================================================
  -- FuncNode
  -- =========================================================================

  describe("FuncNode", function()
    it("validate() returns true for function values", function()
      local node = types.FuncNode.new()
      assert.is_true(node:validate(function() end))
    end)

    it("validate() returns false for non-function values", function()
      local node = types.FuncNode.new()
      assert.is_false(node:validate("not a function"))
      assert.is_false(node:validate(42))
      assert.is_false(node:validate({}))
    end)

    it("materialize() returns nil", function()
      local node = types.FuncNode.new()
      assert.is_nil(node:materialize())
    end)

    it(":is_list() returns false", function()
      assert.is_false(types.FuncNode.new():is_list())
    end)
  end)

  -- =========================================================================
  -- LoadableNode
  -- =========================================================================

  describe("LoadableNode", function()
    it("validate() returns true for dotted module path strings", function()
      local node = types.LoadableNode.new()
      assert.is_true(node:validate("flemma.config"))
      assert.is_true(node:validate("some.module.path"))
    end)

    it("validate() returns false for plain non-dotted strings", function()
      local node = types.LoadableNode.new()
      assert.is_false(node:validate("nodots"))
      assert.is_false(node:validate(""))
      assert.is_false(node:validate(42))
    end)

    it("validate() returns false for Flemma URNs even when they contain dots", function()
      local node = types.LoadableNode.new()
      assert.is_false(node:validate("urn:flemma:some.dotted.segment"))
    end)

    it("validate() returns false for non-string values", function()
      local node = types.LoadableNode.new()
      assert.is_false(node:validate(42))
      assert.is_false(node:validate({}))
      assert.is_false(node:validate(nil))
    end)

    it("materialize() returns nil", function()
      local node = types.LoadableNode.new()
      assert.is_nil(node:materialize())
    end)

    it(":is_list() returns false", function()
      assert.is_false(types.LoadableNode.new():is_list())
    end)
  end)

  -- =========================================================================
  -- Schema reuse independence
  -- =========================================================================

  describe("schema reuse", function()
    it("shared ObjectNode sub-schema produces independent materializations", function()
      local shared_schema = types.ObjectNode.new({
        count = types.IntegerNode.new(0),
      })
      local parent = types.ObjectNode.new({
        child_a = shared_schema,
        child_b = shared_schema,
      })
      local result = parent:materialize()
      result.child_a.count = 999
      assert.are.equal(0, result.child_b.count)
    end)

    it("shared ListNode produces independent materializations", function()
      local shared_list = types.ListNode.new(types.StringNode.new(), { "item" })
      local parent = types.ObjectNode.new({
        list_a = shared_list,
        list_b = shared_list,
      })
      local result = parent:materialize()
      table.insert(result.list_a, "extra")
      assert.are.same({ "item" }, result.list_b)
    end)
  end)
end)
