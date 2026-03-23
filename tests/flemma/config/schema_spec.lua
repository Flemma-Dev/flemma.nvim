local symbols = require("flemma.symbols")

describe("flemma.schema", function()
  ---@type flemma.schema
  local s

  before_each(function()
    package.loaded["flemma.schema"] = nil
    package.loaded["flemma.schema.types"] = nil
    -- flemma.loader is required by types.lua; clear it so preload manipulations
    -- in s.loadable() tests don't bleed across test boundaries.
    package.loaded["flemma.loader"] = nil
    s = require("flemma.schema")
  end)

  -- ---------------------------------------------------------------------------
  -- s.string()
  -- ---------------------------------------------------------------------------

  describe("s.string()", function()
    it("materializes to its default", function()
      assert.equals("anthropic", s.string("anthropic"):materialize())
    end)

    it("has_default() is true when default is set", function()
      assert.is_true(s.string("hello"):has_default())
    end)

    it("has_default() is false when created without argument", function()
      assert.is_false(s.string():has_default())
    end)

    it("materialize() returns nil when no default", function()
      assert.is_nil(s.string():materialize())
    end)

    it("is_list() returns false", function()
      assert.is_false(s.string():is_list())
    end)

    it("validates string values", function()
      assert.is_true(s.string():validate_value("hello"))
      assert.is_true(s.string():validate_value(""))
    end)

    it("rejects non-string values with descriptive error", function()
      local ok, err = s.string():validate_value(123)
      assert.is_false(ok)
      assert.matches("string", err)

      ok, err = s.string():validate_value(true)
      assert.is_false(ok)
      assert.matches("string", err)
    end)

    it("supports :describe() and :type_as() chaining", function()
      local node = s.string("x"):describe("A description"):type_as("MyType")
      assert.equals("A description", node._description)
      assert.equals("MyType", node._type_as)
      assert.equals("x", node:materialize())
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- s.integer()
  -- ---------------------------------------------------------------------------

  describe("s.integer()", function()
    it("materializes to its default", function()
      assert.equals(42, s.integer(42):materialize())
    end)

    it("has_default() is true when default is set", function()
      assert.is_true(s.integer(0):has_default())
    end)

    it("validates whole number values", function()
      assert.is_true(s.integer():validate_value(0))
      assert.is_true(s.integer():validate_value(8192))
      assert.is_true(s.integer():validate_value(-1))
    end)

    it("rejects float values", function()
      local ok, err = s.integer():validate_value(3.14)
      assert.is_false(ok)
      assert.matches("integer", err)
    end)

    it("rejects non-number values", function()
      local ok, err = s.integer():validate_value("42")
      assert.is_false(ok)
      assert.matches("integer", err)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- s.number()
  -- ---------------------------------------------------------------------------

  describe("s.number()", function()
    it("materializes to its default", function()
      assert.equals(0.7, s.number(0.7):materialize())
    end)

    it("validates integer values (numbers are numbers)", function()
      assert.is_true(s.number():validate_value(42))
    end)

    it("validates float values", function()
      assert.is_true(s.number():validate_value(3.14))
    end)

    it("rejects non-number values", function()
      local ok, err = s.number():validate_value("3.14")
      assert.is_false(ok)
      assert.matches("number", err)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- s.boolean()
  -- ---------------------------------------------------------------------------

  describe("s.boolean()", function()
    it("materializes true default", function()
      assert.is_true(s.boolean(true):materialize())
    end)

    it("materializes false default", function()
      assert.is_false(s.boolean(false):materialize())
    end)

    it("has_default() is true when default is false", function()
      assert.is_true(s.boolean(false):has_default())
    end)

    it("has_default() is false when created without argument", function()
      assert.is_false(s.boolean():has_default())
    end)

    it("validates boolean values", function()
      assert.is_true(s.boolean():validate_value(true))
      assert.is_true(s.boolean():validate_value(false))
    end)

    it("rejects non-boolean values", function()
      local ok, err = s.boolean():validate_value(1)
      assert.is_false(ok)
      assert.matches("boolean", err)

      ok = s.boolean():validate_value("true")
      assert.is_false(ok)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- s.enum()
  -- ---------------------------------------------------------------------------

  describe("s.enum()", function()
    it("materializes to its default", function()
      assert.equals("low", s.enum({ "low", "medium", "high" }, "low"):materialize())
    end)

    it("has_default() is true when default is set", function()
      assert.is_true(s.enum({ "a", "b" }, "a"):has_default())
    end)

    it("has_default() is false when no default", function()
      assert.is_false(s.enum({ "a", "b" }):has_default())
    end)

    it("validates values in the enum", function()
      local e = s.enum({ "low", "medium", "high" }, "low")
      assert.is_true(e:validate_value("low"))
      assert.is_true(e:validate_value("medium"))
      assert.is_true(e:validate_value("high"))
    end)

    it("rejects values not in the enum", function()
      local e = s.enum({ "low", "high" }, "low")
      local ok, err = e:validate_value("invalid")
      assert.is_false(ok)
      assert.is_string(err)
    end)

    it("rejects nil", function()
      local e = s.enum({ "low", "high" }, "low")
      local ok, err = e:validate_value(nil)
      assert.is_false(ok)
      assert.is_string(err)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- s.list()
  -- ---------------------------------------------------------------------------

  describe("s.list()", function()
    it("is_list() returns true", function()
      assert.is_true(s.list(s.string(), {}):is_list())
    end)

    it("non-list nodes return is_list() false", function()
      assert.is_false(s.string():is_list())
      assert.is_false(s.integer():is_list())
      assert.is_false(s.object({}):is_list())
    end)

    it("materializes to deep copy of default list", function()
      local list = s.list(s.string(), { "a", "b" })
      local result = list:materialize()
      assert.are.same({ "a", "b" }, result)
    end)

    it("materialize() returns independent copy each call", function()
      local list = s.list(s.string(), { "a" })
      local m1 = list:materialize()
      table.insert(m1, "b")
      local m2 = list:materialize()
      assert.equals(1, #m2)
    end)

    it("has_default() is true when default is set", function()
      assert.is_true(s.list(s.string(), {}):has_default())
      assert.is_true(s.list(s.string(), { "x" }):has_default())
    end)

    it("has_default() is false when no default", function()
      assert.is_false(s.list(s.string()):has_default())
    end)

    it("validates a list of valid items", function()
      local list = s.list(s.integer(), {})
      assert.is_true(list:validate_value({ 1, 2, 3 }))
    end)

    it("rejects a list with an invalid item", function()
      local list = s.list(s.integer(), {})
      local ok, err = list:validate_value({ 1, "two", 3 })
      assert.is_false(ok)
      assert.matches("item%[2%]", err)
    end)

    it("rejects non-table values", function()
      local ok, err = s.list(s.string(), {}):validate_value("not a list")
      assert.is_false(ok)
      assert.is_string(err)
    end)

    it("validate_item() validates a single item", function()
      local list = s.list(s.string(), {})
      assert.is_true(list:validate_item("hello"))
      local ok, err = list:validate_item(42)
      assert.is_false(ok)
      assert.matches("string", err)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- s.map()
  -- ---------------------------------------------------------------------------

  describe("s.map()", function()
    it("validates a map with correct key/value types", function()
      local map = s.map(s.string(), s.integer())
      assert.is_true(map:validate_value({ foo = 1, bar = 2 }))
    end)

    it("rejects a map with invalid values", function()
      local map = s.map(s.string(), s.integer())
      local ok, err = map:validate_value({ foo = "not-an-int" })
      assert.is_false(ok)
      assert.is_string(err)
    end)

    it("rejects non-table values", function()
      local ok = s.map(s.string(), s.string()):validate_value("not a map")
      assert.is_false(ok)
    end)

    it("has_default() is false", function()
      assert.is_false(s.map(s.string(), s.string()):has_default())
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- s.object() — materialization and nested defaults
  -- ---------------------------------------------------------------------------

  describe("s.object() — materialization", function()
    it("materializes flat defaults", function()
      local obj = s.object({
        provider = s.string("anthropic"),
        count = s.integer(42),
      })
      local result = obj:materialize()
      assert.equals("anthropic", result.provider)
      assert.equals(42, result.count)
    end)

    it("omits fields without defaults", function()
      local obj = s.object({
        name = s.string("x"),
        optional_val = s.optional(s.string()),
      })
      local result = obj:materialize()
      assert.equals("x", result.name)
      assert.is_nil(result.optional_val)
    end)

    it("handles nested object defaults", function()
      local obj = s.object({
        params = s.object({
          timeout = s.integer(600),
        }),
      })
      local result = obj:materialize()
      assert.equals(600, result.params.timeout)
    end)

    it("has_default() is true when any child has a default", function()
      local obj = s.object({
        name = s.string("hello"),
        count = s.optional(s.integer()),
      })
      assert.is_true(obj:has_default())
    end)

    it("has_default() is false when no child has a default", function()
      local obj = s.object({
        name = s.optional(s.string()),
      })
      assert.is_false(obj:has_default())
    end)

    it("has_default() is false for empty object", function()
      assert.is_false(s.object({}):has_default())
    end)

    it("materialize() returns nil for empty object with no defaults", function()
      assert.is_nil(s.object({}):materialize())
    end)

    it("materialize() returns nil when all fields exist but none have defaults", function()
      local obj = s.object({ name = s.string(), count = s.optional(s.integer()) })
      assert.is_nil(obj:materialize())
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- s.object() — strict validation
  -- ---------------------------------------------------------------------------

  describe("s.object() — strict mode (default)", function()
    it("accepts known keys", function()
      local obj = s.object({ name = s.string() })
      assert.is_true(obj:validate_value({ name = "hello" }))
    end)

    it("rejects unknown keys", function()
      local obj = s.object({ name = s.string() })
      local ok, err = obj:validate_value({ unknown = "value" })
      assert.is_false(ok)
      assert.matches("unknown", err)
    end)

    it("validates nested field types", function()
      local obj = s.object({ count = s.integer() })
      local ok, err = obj:validate_value({ count = "not-an-int" })
      assert.is_false(ok)
      assert.matches("count", err)
    end)

    it("rejects non-table values", function()
      local ok = s.object({ name = s.string() }):validate_value("not a table")
      assert.is_false(ok)
    end)
  end)

  describe("s.object():strict()", function()
    it("returns self for chaining", function()
      local obj = s.object({})
      assert.equals(obj, obj:strict())
    end)
  end)

  describe("s.object():passthrough()", function()
    it("allows unknown keys", function()
      local obj = s.object({}):passthrough()
      assert.is_true(obj:validate_value({ anything = "value", other = 42 }))
    end)

    it("returns self for chaining", function()
      local obj = s.object({})
      assert.equals(obj, obj:passthrough())
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- s.object() — child schema navigation
  -- ---------------------------------------------------------------------------

  describe("s.object():get_child_schema()", function()
    it("returns schema for known field", function()
      local inner = s.string("x")
      local obj = s.object({ name = inner })
      assert.equals(inner, obj:get_child_schema("name"))
    end)

    it("returns nil for unknown field", function()
      local obj = s.object({ name = s.string() })
      assert.is_nil(obj:get_child_schema("unknown"))
    end)

    it("invokes DISCOVER for unknown keys", function()
      local discovered = s.integer(0)
      local obj = s.object({
        [symbols.DISCOVER] = function(key)
          if key == "dynamic_key" then
            return discovered
          end
        end,
      })
      assert.equals(discovered, obj:get_child_schema("dynamic_key"))
    end)

    it("caches DISCOVER results", function()
      local call_count = 0
      local obj = s.object({
        [symbols.DISCOVER] = function(_key)
          call_count = call_count + 1
          return s.string()
        end,
      })
      obj:get_child_schema("foo")
      obj:get_child_schema("foo")
      assert.equals(1, call_count)
    end)

    it("does not cache DISCOVER misses — callback fires again on each lookup", function()
      -- This is intentional: during the two-pass boot, a DISCOVER callback may
      -- return nil on pass 1 (before module registration) but succeed on pass 2.
      -- Caching nil would permanently block future successful resolutions.
      local call_count = 0
      local obj = s.object({
        [symbols.DISCOVER] = function(_key)
          call_count = call_count + 1
          return nil
        end,
      })
      obj:get_child_schema("missing")
      obj:get_child_schema("missing")
      assert.equals(2, call_count)
    end)

    it("returns nil when DISCOVER returns nil", function()
      local obj = s.object({
        [symbols.DISCOVER] = function(_key)
          return nil
        end,
      })
      assert.is_nil(obj:get_child_schema("missing"))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Alias resolution
  -- ---------------------------------------------------------------------------

  describe("alias resolution", function()
    it("resolve_alias() returns canonical path for alias key", function()
      local obj = s.object({
        parameters = s.object({ timeout = s.integer(600) }),
        [symbols.ALIASES] = { timeout = "parameters.timeout" },
      })
      assert.equals("parameters.timeout", obj:resolve_alias("timeout"))
    end)

    it("resolve_alias() returns nil for real fields", function()
      local obj = s.object({
        provider = s.string("anthropic"),
        [symbols.ALIASES] = { timeout = "parameters.timeout" },
      })
      assert.is_nil(obj:resolve_alias("provider"))
    end)

    it("resolve_alias() returns nil for completely unknown keys", function()
      local obj = s.object({
        provider = s.string(),
        [symbols.ALIASES] = { timeout = "parameters.timeout" },
      })
      assert.is_nil(obj:resolve_alias("nonexistent"))
    end)

    it("real field shadows alias with same name", function()
      -- When both a real field and an alias share a name, the real field wins.
      local obj = s.object({
        timeout = s.integer(600), -- real field
        [symbols.ALIASES] = { timeout = "parameters.timeout" }, -- same name alias
      })
      -- resolve_alias returns nil because "timeout" is a real field
      assert.is_nil(obj:resolve_alias("timeout"))
      -- get_child_schema returns the real field schema
      local child = obj:get_child_schema("timeout")
      assert.is_not_nil(child)
      assert.is_true(child:has_default())
    end)

    it("nested object can have its own aliases", function()
      local inner = s.object({
        modules = s.list(s.string(), {}),
        [symbols.ALIASES] = { approve = "auto_approve" },
      })
      assert.equals("auto_approve", inner:resolve_alias("approve"))
      assert.is_nil(inner:resolve_alias("modules"))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Schema reuse
  -- ---------------------------------------------------------------------------

  describe("schema reuse", function()
    it("produces independent materializations (lists are deep-copied)", function()
      local schema = s.object({ items = s.list(s.string(), { "a" }) })
      local mat1 = schema:materialize()
      table.insert(mat1.items, "b")
      local mat2 = schema:materialize()
      assert.equals(1, #mat2.items)
    end)

    it("produces independent materializations (nested tables)", function()
      local schema = s.object({ params = s.object({ name = s.string("x") }) })
      local mat1 = schema:materialize()
      mat1.params.name = "modified"
      local mat2 = schema:materialize()
      assert.equals("x", mat2.params.name)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- s.optional()
  -- ---------------------------------------------------------------------------

  describe("s.optional()", function()
    it("nil is valid", function()
      assert.is_true(s.optional(s.string()):validate_value(nil))
    end)

    it("inner type is also valid", function()
      assert.is_true(s.optional(s.string()):validate_value("hello"))
    end)

    it("other types are rejected", function()
      local ok, err = s.optional(s.string()):validate_value(42)
      assert.is_false(ok)
      assert.matches("string", err)
    end)

    it("has_default() is false when inner has no default", function()
      assert.is_false(s.optional(s.string()):has_default())
    end)

    it("has_default() inherits from inner when inner has default", function()
      assert.is_true(s.optional(s.string("hi")):has_default())
    end)

    it("materialize() inherits from inner", function()
      assert.equals("hi", s.optional(s.string("hi")):materialize())
      assert.is_nil(s.optional(s.string()):materialize())
    end)

    it("is_list() delegates to inner", function()
      assert.is_true(s.optional(s.list(s.string(), {})):is_list())
      assert.is_false(s.optional(s.string()):is_list())
    end)

    it("get_item_schema() delegates to inner ListNode", function()
      local item = s.string()
      local opt = s.optional(s.list(item, {}))
      assert.equals(item, opt:get_item_schema())
    end)

    it("get_item_schema() delegates to inner UnionNode with list branch", function()
      local item = s.string()
      local opt = s.optional(s.union(s.list(item), s.func()))
      assert.equals(item, opt:get_item_schema())
    end)

    it("get_item_schema() returns nil when inner has no list", function()
      assert.is_nil(s.optional(s.string()):get_item_schema())
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- s.union()
  -- ---------------------------------------------------------------------------

  describe("s.union()", function()
    it("accepts a value matching the first branch", function()
      local u = s.union(s.string(), s.integer())
      assert.is_true(u:validate_value("hello"))
    end)

    it("accepts a value matching the second branch", function()
      local u = s.union(s.string(), s.integer())
      assert.is_true(u:validate_value(42))
    end)

    it("accepts a value matching any later branch", function()
      local u = s.union(s.string(), s.integer(), s.boolean())
      assert.is_true(u:validate_value(true))
    end)

    it("rejects a value not matching any branch", function()
      local u = s.union(s.string(), s.integer())
      local ok, err = u:validate_value(true)
      assert.is_false(ok)
      assert.is_string(err)
    end)

    it("has_default() is false", function()
      assert.is_false(s.union(s.string(), s.integer()):has_default())
    end)

    it("is_list() is true when any branch is a list", function()
      local u = s.union(s.list(s.string()), s.func(), s.string())
      assert.is_true(u:is_list())
    end)

    it("is_list() is false when no branch is a list", function()
      local u = s.union(s.string(), s.integer(), s.boolean())
      assert.is_false(u:is_list())
    end)

    it("get_item_schema() returns first list branch's item schema", function()
      local item = s.string()
      local u = s.union(s.list(item), s.func())
      assert.equals(item, u:get_item_schema())
    end)

    it("get_item_schema() returns nil when no branch is a list", function()
      local u = s.union(s.string(), s.func())
      assert.is_nil(u:get_item_schema())
    end)

    it("get_item_schema() returns the first list branch when multiple exist", function()
      local item_a = s.string()
      local item_b = s.integer()
      local u = s.union(s.list(item_a), s.list(item_b))
      assert.equals(item_a, u:get_item_schema())
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- s.loadable()
  -- ---------------------------------------------------------------------------

  describe("s.loadable()", function()
    it("accepts module paths that exist on package.path", function()
      assert.is_true(s.loadable():validate_value("flemma.loader"))
    end)

    it("accepts modules in package.preload", function()
      package.preload["test.schema.loadable"] = function()
        return {}
      end
      assert.is_true(s.loadable():validate_value("test.schema.loadable"))
      package.preload["test.schema.loadable"] = nil
    end)

    it("rejects nonexistent module paths", function()
      local ok = s.loadable():validate_value("nonexistent.module.that.does.not.exist")
      assert.is_false(ok)
    end)

    it("rejects non-string values", function()
      local ok, err = s.loadable():validate_value(42)
      assert.is_false(ok)
      assert.matches("string", err)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- s.func()
  -- ---------------------------------------------------------------------------

  describe("s.func()", function()
    it("accepts function values", function()
      assert.is_true(s.func():validate_value(function() end))
    end)

    it("rejects non-function values", function()
      local ok, err = s.func():validate_value("not a function")
      assert.is_false(ok)
      assert.matches("function", err)

      ok = s.func():validate_value(42)
      assert.is_false(ok)
    end)

    it("has_default() is false", function()
      assert.is_false(s.func():has_default())
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- s.literal()
  -- ---------------------------------------------------------------------------

  describe("s.literal()", function()
    it("accepts the exact value", function()
      assert.is_true(s.literal(false):validate_value(false))
    end)

    it("rejects different values of the same type", function()
      local ok, err = s.literal(false):validate_value(true)
      assert.is_false(ok)
      assert.matches("expected false", err)
    end)

    it("rejects values of different types", function()
      local ok, err = s.literal(false):validate_value("false")
      assert.is_false(ok)
      assert.matches("expected false", err)
    end)

    it("works with string literals", function()
      assert.is_true(s.literal("sentinel"):validate_value("sentinel"))
      local ok = s.literal("sentinel"):validate_value("other")
      assert.is_false(ok)
    end)

    it("works with number literals", function()
      assert.is_true(s.literal(0):validate_value(0))
      local ok = s.literal(0):validate_value(1)
      assert.is_false(ok)
    end)

    it("has_default() is true for non-nil values", function()
      assert.is_true(s.literal(false):has_default())
      assert.is_true(s.literal("x"):has_default())
      assert.is_true(s.literal(0):has_default())
    end)

    it("has_default() is true even for nil literal", function()
      assert.is_true(s.literal(nil):has_default())
      assert.is_nil(s.literal(nil):materialize())
    end)

    it("has_default() can be explicitly disabled", function()
      local types = require("flemma.schema.types")
      local node = types.LiteralNode.new(false, { as_default = false })
      assert.is_false(node:has_default())
      assert.is_true(node:validate_value(false))
    end)

    it("materializes to the literal value", function()
      assert.equals(false, s.literal(false):materialize())
      assert.equals("x", s.literal("x"):materialize())
    end)

    it("works in unions as a false-sentinel", function()
      local node = s.union(s.string("m"), s.literal(false))
      assert.is_true(node:validate_value("m"))
      assert.is_true(node:validate_value("custom"))
      assert.is_true(node:validate_value(false))
      assert.is_false(node:validate_value(true))
      assert.is_false(node:validate_value(42))
      -- Default comes from string branch
      assert.equals("m", node:materialize())
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- symbols.DISCOVER integration in object validation
  -- ---------------------------------------------------------------------------

  describe("symbols.DISCOVER in validate_value()", function()
    it("discovered schema validates writes to that key", function()
      local obj = s.object({
        [symbols.DISCOVER] = function(key)
          if key == "dynamic" then
            return s.integer()
          end
        end,
      })
      assert.is_true(obj:validate_value({ dynamic = 42 }))
      local ok, err = obj:validate_value({ dynamic = "not-an-int" })
      assert.is_false(ok)
      assert.matches("dynamic", err)
    end)

    it("nil DISCOVER result causes strict rejection", function()
      local obj = s.object({
        [symbols.DISCOVER] = function(_key)
          return nil
        end,
      })
      local ok, err = obj:validate_value({ unknown_key = "value" })
      assert.is_false(ok)
      assert.matches("unknown", err)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- :coerce()
  -- ---------------------------------------------------------------------------

  describe(":coerce()", function()
    it("returns self for chaining", function()
      local node = s.object({ enabled = s.boolean(true) })
      local result = node:coerce(function(v)
        return v
      end)
      assert.equals(node, result)
    end)

    it("apply_coerce transforms value when coerce is set", function()
      local node = s.object({ enabled = s.boolean(true) }):coerce(function(v, _ctx)
        if type(v) == "boolean" then
          return { enabled = v }
        end
        return v
      end)
      local result = node:apply_coerce(false, nil)
      assert.same({ enabled = false }, result)
    end)

    it("apply_coerce passes through when no coerce is set", function()
      local node = s.string()
      assert.equals("hello", node:apply_coerce("hello", nil))
    end)

    it("apply_coerce passes through non-matching values", function()
      local node = s.object({ enabled = s.boolean(true) }):coerce(function(v, _ctx)
        if type(v) == "boolean" then
          return { enabled = v }
        end
        return v
      end)
      local tbl = { enabled = false }
      assert.same(tbl, node:apply_coerce(tbl, nil))
    end)

    it("apply_coerce passes ctx to the coerce function", function()
      local received_ctx = nil
      local node = s.string():coerce(function(v, ctx)
        received_ctx = ctx
        return v
      end)
      local mock_ctx = { get = function() end }
      node:apply_coerce("test", mock_ctx)
      assert.equals(mock_ctx, received_ctx)
    end)

    it("apply_coerce passes nil ctx when not provided", function()
      local received_ctx = "sentinel"
      local node = s.string():coerce(function(v, ctx)
        received_ctx = ctx
        return v
      end)
      node:apply_coerce("test")
      assert.is_nil(received_ctx)
    end)

    it("has_coerce() is false by default", function()
      assert.is_false(s.string():has_coerce())
      assert.is_false(s.list(s.string()):has_coerce())
      assert.is_false(s.object({}):has_coerce())
    end)

    it("has_coerce() is true when coerce is set", function()
      local node = s.list(s.string()):coerce(function(v, _ctx)
        return v
      end)
      assert.is_true(node:has_coerce())
    end)

    it("get_coerce() returns the function", function()
      local fn = function(v, _ctx)
        return v
      end
      local node = s.string():coerce(fn)
      assert.equals(fn, node:get_coerce())
    end)

    it("get_coerce() returns nil when not set", function()
      assert.is_nil(s.string():get_coerce())
    end)

    it("optional delegates coerce to inner schema", function()
      local inner = s.object({ enabled = s.boolean(true) }):coerce(function(v, _ctx)
        if type(v) == "boolean" then
          return { enabled = v }
        end
        return v
      end)
      local opt = s.optional(inner)
      assert.same({ enabled = true }, opt:apply_coerce(true, nil))
    end)

    it("optional returns nil without coercing", function()
      local inner = s.string():coerce(function(_v, _ctx)
        return "coerced"
      end)
      local opt = s.optional(inner)
      assert.is_nil(opt:apply_coerce(nil, nil))
    end)

    it("optional delegates has_coerce to inner", function()
      local inner = s.string():coerce(function(v, _ctx)
        return v
      end)
      local opt = s.optional(inner)
      assert.is_true(opt:has_coerce())
    end)

    it("optional delegates get_coerce to inner", function()
      local fn = function(v, _ctx)
        return v
      end
      local inner = s.string():coerce(fn)
      local opt = s.optional(inner)
      assert.equals(fn, opt:get_coerce())
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- :allow_list()
  -- ---------------------------------------------------------------------------

  describe(":allow_list()", function()
    it("returns self for chaining", function()
      local node = s.object({ name = s.string() })
      local result = node:allow_list(s.string())
      assert.equals(node, result)
    end)

    it("has_list_part() is false by default", function()
      assert.is_false(s.object({}):has_list_part())
    end)

    it("has_list_part() is true when allow_list is set", function()
      local node = s.object({}):allow_list(s.string())
      assert.is_true(node:has_list_part())
    end)

    it("get_list_item_schema() returns the item schema", function()
      local item = s.string()
      local node = s.object({}):allow_list(item)
      assert.equals(item, node:get_list_item_schema())
    end)

    it("get_list_item_schema() returns nil when not set", function()
      assert.is_nil(s.object({}):get_list_item_schema())
    end)

    it("is_object() remains true", function()
      local node = s.object({ name = s.string() }):allow_list(s.string())
      assert.is_true(node:is_object())
    end)

    it("is_list() remains false (list part is separate)", function()
      local node = s.object({}):allow_list(s.string())
      assert.is_false(node:is_list())
    end)

    it("named field access still works", function()
      local node = s.object({ name = s.string("default") }):allow_list(s.string())
      assert.equals("default", node:materialize().name)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- s.nullable()
  -- ---------------------------------------------------------------------------

  describe("s.nullable()", function()
    it("nil is valid", function()
      assert.is_true(s.nullable(s.string()):validate_value(nil))
    end)

    it("inner type is also valid", function()
      assert.is_true(s.nullable(s.string()):validate_value("hello"))
    end)

    it("other types are rejected", function()
      local ok, err = s.nullable(s.string()):validate_value(42)
      assert.is_false(ok)
      assert.matches("string", err)
    end)

    it("has_default() delegates to inner", function()
      assert.is_false(s.nullable(s.string()):has_default())
      assert.is_true(s.nullable(s.string("hi")):has_default())
    end)

    it("materialize() delegates to inner", function()
      assert.equals("hi", s.nullable(s.string("hi")):materialize())
      assert.is_nil(s.nullable(s.string()):materialize())
    end)

    it("is_list() delegates to inner", function()
      assert.is_true(s.nullable(s.list(s.string(), {})):is_list())
      assert.is_false(s.nullable(s.string()):is_list())
    end)

    it("get_inner_schema() returns inner node", function()
      local inner = s.string()
      assert.equals(inner, s.nullable(inner):get_inner_schema())
    end)

    it("is_optional() returns false (nullable is not optional)", function()
      assert.is_false(s.nullable(s.string()):is_optional())
    end)

    it("apply_coerce bypasses nil", function()
      local inner = s.string():coerce(function(_v, _ctx)
        return "coerced"
      end)
      local n = s.nullable(inner)
      assert.is_nil(n:apply_coerce(nil, nil))
      assert.equals("coerced", n:apply_coerce("x", nil))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- :optional() / :nullable() chainable modifiers
  -- ---------------------------------------------------------------------------

  describe("chainable modifiers", function()
    it(":optional() returns an OptionalNode", function()
      local node = s.string():optional()
      assert.is_true(node:is_optional())
      assert.is_true(node:validate_value(nil))
      assert.is_true(node:validate_value("hello"))
    end)

    it(":nullable() returns a NullableNode", function()
      local node = s.string():nullable()
      assert.is_false(node:is_optional())
      assert.is_true(node:validate_value(nil))
      assert.is_true(node:validate_value("hello"))
    end)

    it(":describe() works on wrapper nodes", function()
      local opt = s.string():optional():describe("opt desc")
      assert.equals("opt desc", opt._description)

      local nul = s.string():nullable():describe("nul desc")
      assert.equals("nul desc", nul._description)
    end)

    it("chaining :nullable():optional() composes correctly", function()
      local node = s.number():nullable():optional()
      assert.is_true(node:is_optional())
      assert.is_true(node:validate_value(nil))
      assert.is_true(node:validate_value(42))
    end)

    it("chaining :optional():nullable() composes correctly", function()
      local node = s.number():optional():nullable()
      assert.is_false(node:is_optional())
      assert.is_true(node:validate_value(nil))
      assert.is_true(node:validate_value(42))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- to_json_schema() — scalar types
  -- ---------------------------------------------------------------------------

  describe("to_json_schema() — scalars", function()
    it("s.string() → { type = 'string' }", function()
      assert.same({ type = "string" }, s.string():to_json_schema())
    end)

    it("s.string() with default", function()
      assert.same({ type = "string", default = "hello" }, s.string("hello"):to_json_schema())
    end)

    it("s.string():describe()", function()
      local result = s.string():describe("A name"):to_json_schema()
      assert.same({ type = "string", description = "A name" }, result)
    end)

    it("s.number() → { type = 'number' }", function()
      assert.same({ type = "number" }, s.number():to_json_schema())
    end)

    it("s.number() with default", function()
      assert.same({ type = "number", default = 0.7 }, s.number(0.7):to_json_schema())
    end)

    it("s.boolean() → { type = 'boolean' }", function()
      assert.same({ type = "boolean" }, s.boolean():to_json_schema())
    end)

    it("s.boolean(false) emits default", function()
      assert.same({ type = "boolean", default = false }, s.boolean(false):to_json_schema())
    end)

    it("s.integer() → { type = 'integer' }", function()
      assert.same({ type = "integer" }, s.integer():to_json_schema())
    end)

    it("s.integer() with default", function()
      assert.same({ type = "integer", default = 8192 }, s.integer(8192):to_json_schema())
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- to_json_schema() — enum
  -- ---------------------------------------------------------------------------

  describe("to_json_schema() — enum", function()
    it("basic enum", function()
      local result = s.enum({ "low", "medium", "high" }):to_json_schema()
      assert.same({ type = "string", enum = { "low", "medium", "high" } }, result)
    end)

    it("enum with default", function()
      local result = s.enum({ "a", "b" }, "a"):to_json_schema()
      assert.same({ type = "string", enum = { "a", "b" }, default = "a" }, result)
    end)

    it("enum with description", function()
      local result = s.enum({ "x", "y" }):describe("Pick one"):to_json_schema()
      assert.equals("Pick one", result.description)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- to_json_schema() — list
  -- ---------------------------------------------------------------------------

  describe("to_json_schema() — list", function()
    it("s.list(s.string())", function()
      local result = s.list(s.string()):to_json_schema()
      assert.same({ type = "array", items = { type = "string" } }, result)
    end)

    it("nested list with description", function()
      local result = s.list(s.integer()):describe("Numbers"):to_json_schema()
      assert.same({
        type = "array",
        items = { type = "integer" },
        description = "Numbers",
      }, result)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- to_json_schema() — map
  -- ---------------------------------------------------------------------------

  describe("to_json_schema() — map", function()
    it("s.map(s.string(), s.string())", function()
      local result = s.map(s.string(), s.string()):to_json_schema()
      assert.same({
        type = "object",
        additionalProperties = { type = "string" },
      }, result)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- to_json_schema() — object
  -- ---------------------------------------------------------------------------

  describe("to_json_schema() — object", function()
    it("simple strict object", function()
      local result = s.object({
        name = s.string(),
        count = s.integer(),
      }):to_json_schema()
      assert.equals("object", result.type)
      assert.same({ type = "string" }, result.properties.name)
      assert.same({ type = "integer" }, result.properties.count)
      assert.same({ "count", "name" }, result.required)
      assert.equals(false, result.additionalProperties)
    end)

    it("object with optional field excluded from required", function()
      local result = s.object({
        label = s.string(),
        hint = s.optional(s.string()),
      }):to_json_schema()
      assert.same({ "label" }, result.required)
      assert.same({ type = "string" }, result.properties.hint)
    end)

    it("object with nullable field stays in required", function()
      local result = s.object({
        label = s.string(),
        timeout = s.nullable(s.number()),
      }):to_json_schema()
      assert.same({ "label", "timeout" }, result.required)
      assert.same({ type = { "number", "null" } }, result.properties.timeout)
    end)

    it("passthrough object omits additionalProperties", function()
      local result = s.object({}):passthrough():to_json_schema()
      assert.is_nil(result.additionalProperties)
    end)

    it("empty object has no required array", function()
      local result = s.object({}):to_json_schema()
      assert.is_nil(result.required)
    end)

    it("nested object", function()
      local result = s.object({
        params = s.object({
          timeout = s.integer(600),
        }),
      }):to_json_schema()
      assert.equals("object", result.properties.params.type)
      assert.same({ type = "integer", default = 600 }, result.properties.params.properties.timeout)
    end)

    it("object with optional(nullable()) — not required, type includes null", function()
      local result = s.object({
        value = s.optional(s.nullable(s.number())),
      }):to_json_schema()
      assert.is_nil(result.required)
      assert.same({ type = { "number", "null" } }, result.properties.value)
    end)

    it("object with description", function()
      local result = s.object({}):describe("A container"):to_json_schema()
      assert.equals("A container", result.description)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- to_json_schema() — nullable
  -- ---------------------------------------------------------------------------

  describe("to_json_schema() — nullable", function()
    it("s.nullable(s.number()) → type = {'number', 'null'}", function()
      local result = s.nullable(s.number()):to_json_schema()
      assert.same({ type = { "number", "null" } }, result)
    end)

    it("s.nullable(s.string()) → type = {'string', 'null'}", function()
      local result = s.nullable(s.string()):to_json_schema()
      assert.same({ type = { "string", "null" } }, result)
    end)

    it("nullable preserves inner description", function()
      local result = s.nullable(s.number():describe("A timeout")):to_json_schema()
      assert.same({ type = { "number", "null" }, description = "A timeout" }, result)
    end)

    it("nullable with own description overrides inner", function()
      local result = s.nullable(s.number():describe("inner")):describe("outer"):to_json_schema()
      assert.equals("outer", result.description)
    end)

    it("nullable with default", function()
      local result = s.nullable(s.number(30)):to_json_schema()
      assert.same({ type = { "number", "null" }, default = 30 }, result)
    end)

    it("double nullable does not duplicate 'null'", function()
      local result = s.nullable(s.nullable(s.number())):to_json_schema()
      local null_count = 0
      for _, t in ipairs(result.type) do
        if t == "null" then
          null_count = null_count + 1
        end
      end
      assert.equals(1, null_count)
    end)

    it("nullable union uses anyOf with null branch", function()
      local result = s.nullable(s.union(s.string(), s.integer())):to_json_schema()
      assert.is_not_nil(result.anyOf)
      assert.equals(2, #result.anyOf)
      assert.equals("null", result.anyOf[2].type)
    end)

    it(":nullable() chainable modifier", function()
      local result = s.number():nullable():to_json_schema()
      assert.same({ type = { "number", "null" } }, result)
    end)

    it(":nullable():describe() applies description", function()
      local result = s.number():nullable():describe("Timeout"):to_json_schema()
      assert.same({ type = { "number", "null" }, description = "Timeout" }, result)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- to_json_schema() — optional
  -- ---------------------------------------------------------------------------

  describe("to_json_schema() — optional", function()
    it("delegates to inner schema", function()
      local result = s.optional(s.string()):to_json_schema()
      assert.same({ type = "string" }, result)
    end)

    it("wrapper description overrides inner", function()
      local result = s.optional(s.string():describe("inner")):describe("outer"):to_json_schema()
      assert.equals("outer", result.description)
    end)

    it(":optional() chainable modifier", function()
      local result = s.string():optional():to_json_schema()
      assert.same({ type = "string" }, result)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- to_json_schema() — union
  -- ---------------------------------------------------------------------------

  describe("to_json_schema() — union", function()
    it("produces anyOf", function()
      local result = s.union(s.string(), s.integer()):to_json_schema()
      assert.same({
        anyOf = {
          { type = "string" },
          { type = "integer" },
        },
      }, result)
    end)

    it("union with description", function()
      local result = s.union(s.string(), s.number()):describe("A value"):to_json_schema()
      assert.equals("A value", result.description)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- to_json_schema() — loadable
  -- ---------------------------------------------------------------------------

  describe("to_json_schema() — loadable", function()
    it("serializes as string", function()
      assert.same({ type = "string" }, s.loadable():to_json_schema())
    end)

    it("loadable with default", function()
      assert.same({ type = "string", default = "my.module" }, s.loadable("my.module"):to_json_schema())
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- to_json_schema() — func
  -- ---------------------------------------------------------------------------

  describe("to_json_schema() — func", function()
    it("errors on serialization", function()
      assert.has_error(function()
        s.func():to_json_schema()
      end)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- to_json_schema() — literal
  -- ---------------------------------------------------------------------------

  describe("to_json_schema() — literal", function()
    it("string literal", function()
      local result = s.literal("sentinel"):to_json_schema()
      assert.same({ type = "string", const = "sentinel", default = "sentinel" }, result)
    end)

    it("boolean literal", function()
      local result = s.literal(false):to_json_schema()
      assert.same({ type = "boolean", const = false, default = false }, result)
    end)

    it("integer literal", function()
      local result = s.literal(42):to_json_schema()
      assert.same({ type = "integer", const = 42, default = 42 }, result)
    end)

    it("nil literal", function()
      local result = s.literal(nil):to_json_schema()
      assert.same({ type = "null", default = nil }, result)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- to_json_schema() — real-world tool schema pattern
  -- ---------------------------------------------------------------------------

  describe("to_json_schema() — tool schema pattern", function()
    it("produces correct bash-tool-style schema", function()
      local schema = s.object({
        label = s.string():describe("A short human-readable label for this operation"),
        command = s.string():describe("The bash command to execute"),
        timeout = s.number():nullable():describe("Timeout in seconds (default: 30)"),
      }):strict()

      local result = schema:to_json_schema()

      assert.equals("object", result.type)
      assert.same(
        { type = "string", description = "A short human-readable label for this operation" },
        result.properties.label
      )
      assert.same({ type = "string", description = "The bash command to execute" }, result.properties.command)
      assert.same({
        type = { "number", "null" },
        description = "Timeout in seconds (default: 30)",
      }, result.properties.timeout)
      assert.same({ "command", "label", "timeout" }, result.required)
      assert.equals(false, result.additionalProperties)
    end)
  end)
end)
