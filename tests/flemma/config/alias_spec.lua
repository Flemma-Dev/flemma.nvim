local symbols = require("flemma.symbols")

describe("flemma.config alias resolution", function()
  ---@type flemma.config.proxy
  local proxy
  ---@type flemma.config.store
  local store
  ---@type flemma.config.schema
  local s
  ---@type { DEFAULTS: integer, SETUP: integer, RUNTIME: integer, FRONTMATTER: integer }
  local L

  -- Schema with top-level and nested aliases covering the real config shape:
  --   root aliases: timeout -> parameters.timeout, thinking -> parameters.thinking
  --   tools aliases: approve -> auto_approve
  local function make_alias_schema()
    return s.object({
      provider = s.string("anthropic"),
      model = s.optional(s.string()),
      parameters = s.object({
        timeout = s.optional(s.integer()),
        thinking = s.optional(s.string()),
        max_tokens = s.optional(s.integer()),
      }),
      tools = s.object({
        auto_approve = s.list(s.string(), {}),
        timeout = s.integer(120000),
        modules = s.list(s.string(), {}),
        [symbols.ALIASES] = {
          approve = "auto_approve",
        },
      }),
      [symbols.ALIASES] = {
        timeout = "parameters.timeout",
        thinking = "parameters.thinking",
        max_tokens = "parameters.max_tokens",
      },
    })
  end

  before_each(function()
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.schema"] = nil
    package.loaded["flemma.config.schema.types"] = nil
    package.loaded["flemma.config.schema.navigation"] = nil
    package.loaded["flemma.loader"] = nil
    proxy = require("flemma.config.proxy")
    store = require("flemma.config.store")
    s = require("flemma.config.schema")
    L = store.LAYERS
  end)

  -- ---------------------------------------------------------------------------
  -- Top-level aliases
  -- ---------------------------------------------------------------------------

  describe("top-level aliases", function()
    it("reads a value set at canonical path via the alias key", function()
      local schema = make_alias_schema()
      store.init(schema)
      store.record(L.SETUP, nil, "set", "parameters.timeout", 600)
      local cfg = proxy.read_proxy(schema, nil)
      assert.equals(600, cfg.timeout)
    end)

    it("writes through alias store the op at the canonical path", function()
      local schema = make_alias_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.timeout = 900
      local ops = store.dump_layer(L.SETUP, nil)
      assert.equals(1, #ops)
      assert.equals("parameters.timeout", ops[1].path)
      assert.equals(900, ops[1].value)
    end)

    it("multiple top-level aliases coexist independently", function()
      local schema = make_alias_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.timeout = 1200
      w.thinking = "high"
      w.max_tokens = 8192
      local ops = store.dump_layer(L.SETUP, nil)
      assert.equals(3, #ops)
      -- All ops recorded at canonical paths
      local paths = {}
      for _, op in ipairs(ops) do
        paths[op.path] = op.value
      end
      assert.equals(1200, paths["parameters.timeout"])
      assert.equals("high", paths["parameters.thinking"])
      assert.equals(8192, paths["parameters.max_tokens"])
    end)

    it("validates alias writes against the canonical path's schema", function()
      local schema = make_alias_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      -- timeout is optional(integer); string should be rejected
      assert.has_error(function()
        w.timeout = "not-an-integer"
      end)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Nested aliases (within sub-objects)
  -- ---------------------------------------------------------------------------

  describe("nested aliases", function()
    it("reads through a nested alias within a sub-object", function()
      local schema = make_alias_schema()
      store.init(schema)
      store.record(L.SETUP, nil, "set", "tools.auto_approve", { "bash", "grep" })
      local cfg = proxy.read_proxy(schema, nil)
      assert.are.same({ "bash", "grep" }, cfg.tools.approve)
    end)

    it("writes through a nested alias store the op at the canonical sub-path", function()
      local schema = make_alias_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.tools.approve = { "bash" }
      local ops = store.dump_layer(L.SETUP, nil)
      assert.equals(1, #ops)
      assert.equals("tools.auto_approve", ops[1].path)
    end)

    it("list ops through a nested alias work correctly", function()
      local schema = make_alias_schema()
      store.init(schema)
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default" })
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.tools.approve:append("bash")
      w.tools.approve:append("grep")
      assert.are.same({ "$default", "bash", "grep" }, store.resolve("tools.auto_approve", nil))
    end)

    it("remove via nested alias removes from the canonical list", function()
      local schema = make_alias_schema()
      store.init(schema)
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default", "bash" })
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.tools.approve:remove("$default")
      assert.are.same({ "bash" }, store.resolve("tools.auto_approve", nil))
    end)

    it("prepend via nested alias prepends to the canonical list", function()
      local schema = make_alias_schema()
      store.init(schema)
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "bash" })
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.tools.approve:prepend("find")
      assert.are.same({ "find", "bash" }, store.resolve("tools.auto_approve", nil))
    end)

    it("operator chaining via nested alias records all ops at canonical path", function()
      local schema = make_alias_schema()
      store.init(schema)
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default" })
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.tools.approve = w.tools.approve + "bash" + "grep" - "$default"
      assert.are.same({ "bash", "grep" }, store.resolve("tools.auto_approve", nil))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Reads through aliases
  -- ---------------------------------------------------------------------------

  describe("reads through aliases", function()
    it("alias read resolves value set at canonical path in a lower layer", function()
      local schema = make_alias_schema()
      store.init(schema)
      store.record(L.DEFAULTS, nil, "set", "parameters.timeout", 120000)
      store.record(L.SETUP, nil, "set", "parameters.timeout", 600)
      local cfg = proxy.read_proxy(schema, nil)
      -- Higher layer wins
      assert.equals(600, cfg.timeout)
    end)

    it("alias read resolves across all four layers", function()
      local schema = make_alias_schema()
      store.init(schema)
      store.record(L.DEFAULTS, nil, "set", "parameters.thinking", "disabled")
      store.record(L.SETUP, nil, "set", "parameters.thinking", "low")
      store.record(L.RUNTIME, nil, "set", "parameters.thinking", "medium")
      store.record(L.FRONTMATTER, 1, "set", "parameters.thinking", "high")
      local cfg = proxy.read_proxy(schema, 1)
      assert.equals("high", cfg.thinking)
    end)

    it("alias read without buffer layer skips frontmatter", function()
      local schema = make_alias_schema()
      store.init(schema)
      store.record(L.SETUP, nil, "set", "parameters.timeout", 600)
      store.record(L.FRONTMATTER, 1, "set", "parameters.timeout", 1200)
      local cfg = proxy.read_proxy(schema, nil)
      assert.equals(600, cfg.timeout)
    end)

    it("alias to list field returns the resolved list value", function()
      local schema = make_alias_schema()
      store.init(schema)
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default" })
      store.record(L.SETUP, nil, "append", "tools.auto_approve", "bash")
      local cfg = proxy.read_proxy(schema, nil)
      assert.are.same({ "$default", "bash" }, cfg.tools.approve)
    end)

    it("alias returns nil when no ops exist at the canonical path", function()
      local schema = make_alias_schema()
      store.init(schema)
      local cfg = proxy.read_proxy(schema, nil)
      assert.is_nil(cfg.timeout)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Writes through aliases store at canonical path
  -- ---------------------------------------------------------------------------

  describe("writes through aliases store at canonical path", function()
    it("write via alias, read via canonical path", function()
      local schema = make_alias_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.thinking = "medium"
      local cfg = proxy.read_proxy(schema, nil)
      assert.equals("medium", cfg.parameters.thinking)
    end)

    it("write via canonical path, read via alias", function()
      local schema = make_alias_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.parameters.timeout = 300
      local cfg = proxy.read_proxy(schema, nil)
      assert.equals(300, cfg.timeout)
    end)

    it("alias write at one layer overridden by canonical write at higher layer", function()
      local schema = make_alias_schema()
      store.init(schema)
      local w_setup = proxy.write_proxy(schema, nil, L.SETUP)
      w_setup.timeout = 600
      local w_runtime = proxy.write_proxy(schema, nil, L.RUNTIME)
      w_runtime.parameters.timeout = 1200
      local cfg = proxy.read_proxy(schema, nil)
      assert.equals(1200, cfg.timeout)
    end)

    it("canonical write at one layer overridden by alias write at higher layer", function()
      local schema = make_alias_schema()
      store.init(schema)
      local w_setup = proxy.write_proxy(schema, nil, L.SETUP)
      w_setup.parameters.timeout = 600
      local w_runtime = proxy.write_proxy(schema, nil, L.RUNTIME)
      w_runtime.timeout = 1200
      local cfg = proxy.read_proxy(schema, nil)
      assert.equals(1200, cfg.timeout)
    end)

    it("clearing a layer removes alias-targeted ops", function()
      local schema = make_alias_schema()
      store.init(schema)
      store.record(L.DEFAULTS, nil, "set", "parameters.timeout", 120000)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.timeout = 600
      w[symbols.CLEAR]()
      local cfg = proxy.read_proxy(schema, nil)
      -- Falls back to defaults layer
      assert.equals(120000, cfg.timeout)
    end)

    it("alias write to buffer layer is independent per buffer", function()
      local schema = make_alias_schema()
      store.init(schema)
      store.record(L.SETUP, nil, "set", "parameters.timeout", 600)
      local w1 = proxy.write_proxy(schema, 1, L.FRONTMATTER)
      w1.timeout = 1200
      local w2 = proxy.write_proxy(schema, 2, L.FRONTMATTER)
      w2.timeout = 300
      local cfg1 = proxy.read_proxy(schema, 1)
      local cfg2 = proxy.read_proxy(schema, 2)
      assert.equals(1200, cfg1.timeout)
      assert.equals(300, cfg2.timeout)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Real fields shadow aliases with same name
  -- ---------------------------------------------------------------------------

  describe("real fields shadow aliases with same name", function()
    it("real field on the same object takes priority over alias", function()
      -- 'timeout' is a real field on tools AND an alias at root.
      -- Accessing cfg.tools.timeout reads the real tools.timeout field.
      local schema = make_alias_schema()
      store.init(schema)
      store.record(L.SETUP, nil, "set", "tools.timeout", 5000)
      store.record(L.SETUP, nil, "set", "parameters.timeout", 600)
      local cfg = proxy.read_proxy(schema, nil)
      -- tools.timeout is the real field, not the root alias
      assert.equals(5000, cfg.tools.timeout)
      -- root alias resolves to parameters.timeout
      assert.equals(600, cfg.timeout)
    end)

    it("write to shadowed field writes to the real field, not the alias target", function()
      -- Schema where an object has both a real field "timeout" and an alias
      -- "timeout" at the parent level pointing elsewhere.
      local schema = make_alias_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.tools.timeout = 9999
      -- Op should be at tools.timeout (real field), not parameters.timeout (alias target)
      local ops = store.dump_layer(L.SETUP, nil)
      assert.equals(1, #ops)
      assert.equals("tools.timeout", ops[1].path)
    end)

    it("schema resolve_alias returns nil for real field even when alias exists", function()
      -- ObjectNode with a real field and an alias of the same name
      local obj = s.object({
        timeout = s.integer(600),
        [symbols.ALIASES] = { timeout = "parameters.timeout" },
      })
      assert.is_nil(obj:resolve_alias("timeout"))
      -- get_child_schema returns the real field
      assert.is_not_nil(obj:get_child_schema("timeout"))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Alias targets are canonical paths (no chaining)
  -- ---------------------------------------------------------------------------

  describe("aliases target canonical paths only", function()
    it("alias target must resolve through real fields in the schema", function()
      -- An alias that targets a path where every segment is a real field works.
      local schema = s.object({
        nested = s.object({
          deep = s.object({
            value = s.optional(s.string()),
          }),
        }),
        [symbols.ALIASES] = {
          shortcut = "nested.deep.value",
        },
      })
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.shortcut = "hello"
      assert.equals("hello", store.resolve("nested.deep.value", nil))
    end)

    it("alias targeting another alias name errors because the path has no real field", function()
      -- Schema where alias "a" targets "b", but "b" is also an alias, not a real field.
      -- Accessing "a" resolves to path "b", but navigate_schema("b") finds no real field.
      local schema = s.object({
        parameters = s.object({
          timeout = s.optional(s.integer()),
        }),
        [symbols.ALIASES] = {
          a = "b",
          b = "parameters.timeout",
        },
      })
      store.init(schema)
      local cfg = proxy.read_proxy(schema, nil)
      -- "a" resolves to path "b", but "b" is not a real field on the root object.
      -- navigate_schema will fail, causing an error.
      assert.has_error(function()
        local _ = cfg.a
      end)
    end)
  end)
end)
