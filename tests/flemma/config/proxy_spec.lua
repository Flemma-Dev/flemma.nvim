local symbols = require("flemma.symbols")

describe("flemma.config.proxy", function()
  ---@type flemma.config.proxy
  local proxy
  ---@type flemma.config.store
  local store
  ---@type flemma.config.schema
  local s
  ---@type { DEFAULTS: integer, SETUP: integer, RUNTIME: integer, FRONTMATTER: integer }
  local L

  -- Minimal schema covering scalars, nested objects, lists, aliases, and
  -- an optional DISCOVER callback for dynamic key tests.
  local function make_test_schema()
    return s.object({
      provider = s.string("anthropic"),
      model = s.optional(s.string()),
      parameters = s.object({
        timeout = s.optional(s.integer()),
        thinking = s.optional(s.string()),
      }),
      tools = s.object({
        auto_approve = s.list(s.string(), {}),
        timeout = s.integer(120000),
        [symbols.ALIASES] = {
          approve = "auto_approve",
        },
      }),
      [symbols.ALIASES] = {
        timeout = "parameters.timeout",
        thinking = "parameters.thinking",
      },
    })
  end

  -- Schema with provider-specific sub-objects for composed lens tests.
  -- Mirrors the real config's parameters.anthropic / parameters structure.
  local function make_composed_lens_schema()
    return s.object({
      parameters = s.object({
        timeout = s.optional(s.integer()),
        thinking = s.optional(s.string()),
        anthropic = s.object({
          thinking_budget = s.optional(s.integer()),
          timeout = s.optional(s.integer()),
        }),
      }),
    })
  end

  -- Schema variant with a DISCOVER callback on parameters, used for DISCOVER tests.
  -- Returns (schema, call_count_fn) so tests can assert on callback invocations.
  local function make_schema_with_discover()
    local count = 0
    local schema = s.object({
      parameters = s.object({
        timeout = s.optional(s.integer()),
        [symbols.DISCOVER] = function(key)
          count = count + 1
          if key == "dynamic_key" then
            return s.optional(s.string())
          end
          return nil
        end,
      }),
    })
    return schema, function()
      return count
    end
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
    store.init(make_test_schema())
  end)

  -- ---------------------------------------------------------------------------
  -- Read proxy: scalar reads, nested reads, errors on write
  -- ---------------------------------------------------------------------------

  describe("read proxy — scalar and nested reads", function()
    it("reads a top-level scalar from the store", function()
      store.record(L.SETUP, nil, "set", "provider", "openai")
      local cfg = proxy.read_proxy(make_test_schema(), nil)
      assert.equals("openai", cfg.provider)
    end)

    it("returns nil for a top-level field with no ops", function()
      local cfg = proxy.read_proxy(make_test_schema(), nil)
      assert.is_nil(cfg.model)
    end)

    it("reads a nested scalar via dot navigation", function()
      store.record(L.SETUP, nil, "set", "parameters.timeout", 600)
      local cfg = proxy.read_proxy(make_test_schema(), nil)
      assert.equals(600, cfg.parameters.timeout)
    end)

    it("each intermediate navigation returns a new proxy", function()
      store.record(L.SETUP, nil, "set", "parameters.timeout", 300)
      local cfg = proxy.read_proxy(make_test_schema(), nil)
      local params = cfg.parameters
      assert.equals(300, params.timeout)
    end)

    it("reads a list field from the store", function()
      store.record(L.SETUP, nil, "set", "tools.auto_approve", { "bash", "grep" })
      local cfg = proxy.read_proxy(make_test_schema(), nil)
      assert.are.same({ "bash", "grep" }, cfg.tools.auto_approve)
    end)

    it("returns nil for list field with no ops", function()
      local cfg = proxy.read_proxy(make_test_schema(), nil)
      assert.is_nil(cfg.tools.auto_approve)
    end)

    it("resolves through buffer layer when bufnr is provided", function()
      local schema = make_test_schema()
      store.init(schema)
      store.record(L.SETUP, nil, "set", "provider", "openai")
      store.record(L.FRONTMATTER, 7, "set", "provider", "vertex")
      local cfg = proxy.read_proxy(schema, 7)
      assert.equals("vertex", cfg.provider)
    end)

    it("ignores buffer layer when bufnr is nil", function()
      local schema = make_test_schema()
      store.init(schema)
      store.record(L.SETUP, nil, "set", "provider", "openai")
      store.record(L.FRONTMATTER, 7, "set", "provider", "vertex")
      local cfg = proxy.read_proxy(schema, nil)
      assert.equals("openai", cfg.provider)
    end)

    it("errors on unknown key", function()
      local cfg = proxy.read_proxy(make_test_schema(), nil)
      assert.has_error(function()
        local _ = cfg.nonexistent_key
      end)
    end)

    it("errors on any write attempt", function()
      local cfg = proxy.read_proxy(make_test_schema(), nil)
      assert.has_error(function()
        cfg.provider = "openai"
      end)
    end)

    it("errors on write to nested field via sub-proxy", function()
      local cfg = proxy.read_proxy(make_test_schema(), nil)
      assert.has_error(function()
        cfg.parameters.timeout = 500
      end)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Write proxy: __newindex records set ops, validates types, rejects unknown keys
  -- ---------------------------------------------------------------------------

  describe("write proxy — __newindex records set ops", function()
    it("records a set op for a top-level scalar", function()
      local schema = make_test_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.provider = "vertex"
      assert.equals("vertex", store.resolve("provider", nil))
    end)

    it("records a set op for a nested scalar via sub-proxy navigation", function()
      local schema = make_test_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.parameters.timeout = 1200
      assert.equals(1200, store.resolve("parameters.timeout", nil))
    end)

    it("records a set op for a list field (full replace)", function()
      local schema = make_test_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.tools.auto_approve = { "bash", "grep" }
      assert.are.same({ "bash", "grep" }, store.resolve("tools.auto_approve", nil))
    end)

    it("records to the correct layer", function()
      local schema = make_test_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.RUNTIME)
      w.provider = "openai"
      assert.equals(0, #store.dump_layer(L.SETUP, nil))
      assert.equals(1, #store.dump_layer(L.RUNTIME, nil))
    end)

    it("records to the buffer layer when bufnr is provided", function()
      local schema = make_test_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, 3, L.FRONTMATTER)
      w.provider = "anthropic"
      local ops = store.dump_layer(L.FRONTMATTER, 3)
      assert.equals(1, #ops)
      assert.equals("provider", ops[1].path)
    end)

    it("validates type: rejects wrong type for string field", function()
      local schema = make_test_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      assert.has_error(function()
        w.provider = 42
      end)
    end)

    it("validates type: rejects float for integer field", function()
      local schema = make_test_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      assert.has_error(function()
        w.parameters.timeout = 1.5
      end)
    end)

    it("rejects unknown keys on strict objects", function()
      local schema = make_test_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      assert.has_error(function()
        w.totally_unknown = "value"
      end)
    end)

    it("allows table assignment to object field (recursive sub-field writes)", function()
      local schema = make_test_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.parameters = { timeout = 500 }
      assert.equals(500, store.resolve("parameters.timeout", nil))
    end)

    it("rejects non-table assignment to an object field", function()
      local schema = make_test_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      assert.has_error(function()
        w.parameters = "not a table"
      end)
    end)

    it("accepts nil for optional fields", function()
      local schema = make_test_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      -- nil is a valid value for optional(integer)
      assert.has_no.error(function()
        w.parameters.timeout = nil
      end)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Write proxy: DISCOVER callback for unknown keys
  -- ---------------------------------------------------------------------------

  describe("write proxy — DISCOVER callback", function()
    it("DISCOVER callback invoked for unknown key, write succeeds", function()
      local schema, _ = make_schema_with_discover()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      assert.has_no.error(function()
        w.parameters.dynamic_key = "hello"
      end)
      assert.equals("hello", store.resolve("parameters.dynamic_key", nil))
    end)

    it("DISCOVER returning nil triggers validation error", function()
      local schema, _ = make_schema_with_discover()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      assert.has_error(function()
        w.parameters.unknown_key = "value"
      end)
    end)

    it("DISCOVER schema validates writes: wrong type rejected", function()
      local schema, _ = make_schema_with_discover()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      -- dynamic_key is optional(string); integer should be rejected
      assert.has_error(function()
        w.parameters.dynamic_key = 42
      end)
    end)

    it("DISCOVER schema is cached after first resolution", function()
      local schema, get_count = make_schema_with_discover()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.parameters.dynamic_key = "first"
      w.parameters.dynamic_key = "second"
      -- DISCOVER was called once; subsequent navigations use the cache
      assert.equals(1, get_count())
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- List proxy: append/remove/prepend methods, +/-/^ operators, assignment
  -- ---------------------------------------------------------------------------

  describe("list proxy — mutation ops", function()
    it("append records an append op", function()
      local schema = make_test_schema()
      store.init(schema)
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default" })
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.tools.auto_approve:append("bash")
      assert.are.same({ "$default", "bash" }, store.resolve("tools.auto_approve", nil))
    end)

    it("remove records a remove op", function()
      local schema = make_test_schema()
      store.init(schema)
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default", "bash" })
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.tools.auto_approve:remove("$default")
      assert.are.same({ "bash" }, store.resolve("tools.auto_approve", nil))
    end)

    it("prepend records a prepend op", function()
      local schema = make_test_schema()
      store.init(schema)
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "bash", "grep" })
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.tools.auto_approve:prepend("find")
      assert.are.same({ "find", "bash", "grep" }, store.resolve("tools.auto_approve", nil))
    end)

    it("+ operator appends an item", function()
      local schema = make_test_schema()
      store.init(schema)
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default" })
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.tools.auto_approve = w.tools.auto_approve + "bash"
      assert.are.same({ "$default", "bash" }, store.resolve("tools.auto_approve", nil))
    end)

    it("- operator removes an item", function()
      local schema = make_test_schema()
      store.init(schema)
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default", "bash" })
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.tools.auto_approve = w.tools.auto_approve - "$default"
      assert.are.same({ "bash" }, store.resolve("tools.auto_approve", nil))
    end)

    it("^ operator prepends an item", function()
      local schema = make_test_schema()
      store.init(schema)
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "bash", "grep" })
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.tools.auto_approve = w.tools.auto_approve ^ "find"
      assert.are.same({ "find", "bash", "grep" }, store.resolve("tools.auto_approve", nil))
    end)

    it("operator chaining: + then -", function()
      local schema = make_test_schema()
      store.init(schema)
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default" })
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.tools.auto_approve = w.tools.auto_approve + "bash" + "grep" - "$default"
      assert.are.same({ "bash", "grep" }, store.resolve("tools.auto_approve", nil))
    end)

    it("direct assignment to list field records a set op (full replace)", function()
      local schema = make_test_schema()
      store.init(schema)
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "$default" })
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.tools.auto_approve = { "bash" }
      assert.are.same({ "bash" }, store.resolve("tools.auto_approve", nil))
    end)

    it("append validates item against item schema", function()
      local schema = make_test_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      -- auto_approve is list(string): integer item should be rejected
      assert.has_error(function()
        w.tools.auto_approve:append(42)
      end)
    end)

    it("prepend validates item against item schema", function()
      local schema = make_test_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      assert.has_error(function()
        w.tools.auto_approve:prepend(false)
      end)
    end)

    it("read proxy returns resolved list value (not a ListProxy)", function()
      local schema = make_test_schema()
      store.init(schema)
      store.record(L.SETUP, nil, "set", "tools.auto_approve", { "bash" })
      local cfg = proxy.read_proxy(schema, nil)
      local result = cfg.tools.auto_approve
      -- Should be the raw list, not a ListProxy object
      assert.are.same({ "bash" }, result)
      assert.is_nil(getmetatable(result))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Frozen proxy (lens): errors on write, reads through scoped path
  -- ---------------------------------------------------------------------------

  describe("frozen lens — reads through scoped path, errors on write", function()
    it("reads a field relative to the lens root path", function()
      local schema = make_test_schema()
      store.init(schema)
      store.record(L.SETUP, nil, "set", "parameters.timeout", 600)
      local lens = proxy.lens(schema, nil, "parameters")
      assert.equals(600, lens.timeout)
    end)

    it("reads a deeply nested field relative to lens root", function()
      local schema = make_test_schema()
      store.init(schema)
      store.record(L.SETUP, nil, "set", "tools.timeout", 5000)
      local lens = proxy.lens(schema, nil, "tools")
      assert.equals(5000, lens.timeout)
    end)

    it("resolves through buffer layer", function()
      local schema = make_test_schema()
      store.init(schema)
      store.record(L.SETUP, nil, "set", "parameters.timeout", 600)
      store.record(L.FRONTMATTER, 2, "set", "parameters.timeout", 1200)
      local lens = proxy.lens(schema, 2, "parameters")
      assert.equals(1200, lens.timeout)
    end)

    it("errors on any write attempt", function()
      local schema = make_test_schema()
      store.init(schema)
      local lens = proxy.lens(schema, nil, "parameters")
      assert.has_error(function()
        lens.timeout = 999
      end)
    end)

    it("errors for an invalid lens path", function()
      local schema = make_test_schema()
      store.init(schema)
      assert.has_error(function()
        proxy.lens(schema, nil, "nonexistent.path")
      end)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Alias resolution in both read and write proxies
  -- ---------------------------------------------------------------------------

  describe("alias resolution", function()
    it("read proxy resolves a top-level alias to the canonical path", function()
      local schema = make_test_schema()
      store.init(schema)
      store.record(L.SETUP, nil, "set", "parameters.timeout", 800)
      local cfg = proxy.read_proxy(schema, nil)
      -- 'timeout' at root is an alias for 'parameters.timeout'
      assert.equals(800, cfg.timeout)
    end)

    it("write proxy records set op at the canonical path for a top-level alias", function()
      local schema = make_test_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.timeout = 900
      -- op must be recorded at the canonical path, not the alias
      local ops = store.dump_layer(L.SETUP, nil)
      assert.equals(1, #ops)
      assert.equals("parameters.timeout", ops[1].path)
      assert.equals(900, ops[1].value)
    end)

    it("write via alias and write via canonical path are equivalent", function()
      local schema = make_test_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.timeout = 500
      assert.equals(500, store.resolve("parameters.timeout", nil))
    end)

    it("read proxy resolves a nested alias within a sub-object", function()
      local schema = make_test_schema()
      store.init(schema)
      store.record(L.SETUP, nil, "set", "tools.auto_approve", { "bash" })
      local cfg = proxy.read_proxy(schema, nil)
      -- 'approve' in tools is an alias for 'auto_approve'
      assert.are.same({ "bash" }, cfg.tools.approve)
    end)

    it("write proxy resolves a nested alias within a sub-object", function()
      local schema = make_test_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.tools.approve = { "grep" }
      local ops = store.dump_layer(L.SETUP, nil)
      assert.equals(1, #ops)
      assert.equals("tools.auto_approve", ops[1].path)
    end)

    it("real fields shadow aliases with the same name", function()
      -- 'timeout' is a real field on the tools object AND an alias on root.
      -- Accessing cfg.tools.timeout should read the real field, not the root alias.
      local schema = make_test_schema()
      store.init(schema)
      store.record(L.SETUP, nil, "set", "tools.timeout", 999)
      local cfg = proxy.read_proxy(schema, nil)
      assert.equals(999, cfg.tools.timeout)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Writer symbols.CLEAR returns self (chaining)
  -- ---------------------------------------------------------------------------

  describe("writer symbols.CLEAR", function()
    it("clear wipes all ops from the target layer", function()
      local schema = make_test_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.provider = "openai"
      w[symbols.CLEAR]()
      assert.is_nil(store.resolve("provider", nil))
    end)

    it("clear returns self for chaining", function()
      local schema = make_test_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      local returned = w[symbols.CLEAR]()
      assert.equals(w, returned)
    end)

    it("chained clear + write records the new op only", function()
      local schema = make_test_schema()
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.provider = "openai"
      w[symbols.CLEAR]().provider = "vertex"
      local ops = store.dump_layer(L.SETUP, nil)
      assert.equals(1, #ops)
      assert.equals("vertex", ops[1].value)
    end)

    it("clear clears only the target layer, not other layers", function()
      local schema = make_test_schema()
      store.init(schema)
      store.record(L.DEFAULTS, nil, "set", "provider", "anthropic")
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.provider = "openai"
      w[symbols.CLEAR]()
      -- DEFAULTS still has its op; SETUP is empty
      assert.equals("anthropic", store.resolve("provider", nil))
    end)

    it("read proxy errors on clear", function()
      local schema = make_test_schema()
      store.init(schema)
      local cfg = proxy.read_proxy(schema, nil)
      assert.has_error(function()
        local _ = cfg[symbols.CLEAR]
      end)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Composed lens: multi-path, path-first priority
  -- ---------------------------------------------------------------------------

  describe("composed lens — multi-path resolution", function()
    it("returns value from the most specific path", function()
      local schema = make_composed_lens_schema()
      store.init(schema)
      store.record(L.SETUP, nil, "set", "parameters.anthropic.thinking_budget", 4096)
      local lens = proxy.lens(schema, nil, {
        "parameters.anthropic",
        "parameters",
      })
      assert.equals(4096, lens.thinking_budget)
    end)

    it("falls back to general path when specific has no value", function()
      local schema = make_composed_lens_schema()
      store.init(schema)
      -- 'thinking' exists on parameters but not on parameters.anthropic
      store.record(L.SETUP, nil, "set", "parameters.thinking", "high")
      local lens = proxy.lens(schema, nil, {
        "parameters.anthropic",
        "parameters",
      })
      assert.equals("high", lens.thinking)
    end)

    it("returns nil when no path resolves a value", function()
      local schema = make_composed_lens_schema()
      store.init(schema)
      local lens = proxy.lens(schema, nil, {
        "parameters.anthropic",
        "parameters",
      })
      assert.is_nil(lens.timeout)
    end)

    it("path-first priority: specific path at lower layer beats general at higher layer", function()
      local schema = make_composed_lens_schema()
      store.init(schema)
      -- 'timeout' exists on both parameters and parameters.anthropic
      store.record(L.SETUP, nil, "set", "parameters.anthropic.timeout", 1200)
      store.record(L.RUNTIME, nil, "set", "parameters.timeout", 600)
      local lens = proxy.lens(schema, nil, {
        "parameters.anthropic",
        "parameters",
      })
      -- Specific path (SETUP) is checked first through all layers; the 1200
      -- is found before the general path's 600 is even considered.
      assert.equals(1200, lens.timeout)
    end)

    it("same path at higher layer beats same path at lower layer", function()
      local schema = make_composed_lens_schema()
      store.init(schema)
      store.record(L.SETUP, nil, "set", "parameters.timeout", 600)
      store.record(L.RUNTIME, nil, "set", "parameters.timeout", 1200)
      local lens = proxy.lens(schema, nil, {
        "parameters.anthropic",
        "parameters",
      })
      -- Within the same path, normal layer priority applies (RUNTIME > SETUP)
      assert.equals(1200, lens.timeout)
    end)

    it("errors on any write attempt", function()
      local schema = make_composed_lens_schema()
      store.init(schema)
      local lens = proxy.lens(schema, nil, {
        "parameters.anthropic",
        "parameters",
      })
      assert.has_error(function()
        lens.timeout = 999
      end)
    end)

    it("errors at construction for an invalid path", function()
      local schema = make_composed_lens_schema()
      store.init(schema)
      assert.has_error(function()
        proxy.lens(schema, nil, {
          "parameters.anthropic",
          "nonexistent.path",
        })
      end)
    end)

    it("resolves through buffer layer", function()
      local schema = make_composed_lens_schema()
      store.init(schema)
      store.record(L.SETUP, nil, "set", "parameters.timeout", 600)
      store.record(L.FRONTMATTER, 5, "set", "parameters.anthropic.timeout", 9999)
      local lens = proxy.lens(schema, 5, {
        "parameters.anthropic",
        "parameters",
      })
      assert.equals(9999, lens.timeout)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- :coerce() integration with write proxy
  -- ---------------------------------------------------------------------------

  describe("write proxy with :coerce()", function()
    it("coerces value before validation and recording", function()
      local schema = s.object({
        autopilot = s.object({
          enabled = s.boolean(true),
          max_turns = s.integer(100),
        }):coerce(function(v, _ctx)
          if type(v) == "boolean" then
            return { enabled = v }
          end
          return v
        end),
      })
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.autopilot = false
      -- The coerced value { enabled = false } was recorded, not the boolean
      assert.equals(false, store.resolve("autopilot.enabled", nil))
    end)

    it("coerce does not affect read proxy", function()
      local schema = s.object({
        autopilot = s.object({
          enabled = s.boolean(true),
        }):coerce(function(v, _ctx)
          if type(v) == "boolean" then
            return { enabled = v }
          end
          return v
        end),
      })
      store.init(schema)
      store.record(L.SETUP, nil, "set", "autopilot.enabled", false)
      local r = proxy.read_proxy(schema, nil)
      assert.equals(false, r.autopilot.enabled)
    end)

    it("coerce runs before validation — invalid raw value becomes valid after coerce", function()
      local schema = s.object({
        setting = s.object({
          enabled = s.boolean(true),
        }):coerce(function(v, _ctx)
          if type(v) == "boolean" then
            return { enabled = v }
          end
          return v
        end),
      })
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      -- boolean would fail object validation, but coerce transforms it first
      assert.has_no.errors(function()
        w.setting = true
      end)
      assert.equals(true, store.resolve("setting.enabled", nil))
    end)

    it("coerce receives ctx from the proxy", function()
      local received_ctx = nil
      local schema = s.object({
        name = s.string():coerce(function(v, ctx)
          received_ctx = ctx
          return v
        end),
      })
      store.init(schema)
      -- Write a value so ctx.get can return something
      store.record(L.DEFAULTS, nil, "set", "name", "default")
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.name = "hello"
      assert.is_not_nil(received_ctx)
      assert.is_not_nil(received_ctx.get)
      assert.equals("function", type(received_ctx.get))
    end)

    it("coerce ctx.get resolves values from the store", function()
      local resolved_value = nil
      local schema = s.object({
        source = s.string("original"),
        target = s.string():coerce(function(v, ctx)
          resolved_value = ctx.get("source")
          return v
        end),
      })
      store.init(schema)
      store.record(L.DEFAULTS, nil, "set", "source", "original")
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.target = "test"
      assert.equals("original", resolved_value)
    end)

    it("coerce with optional wrapping", function()
      local schema = s.object({
        feature = s.optional(s.object({
          enabled = s.boolean(true),
        }):coerce(function(v, _ctx)
          if type(v) == "boolean" then
            return { enabled = v }
          end
          return v
        end)),
      })
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.feature = false
      assert.equals(false, store.resolve("feature.enabled", nil))
    end)

    it("coerce nil on optional node bypasses coerce", function()
      local coerce_called = false
      local schema = s.object({
        feature = s.optional(s.string():coerce(function(v, _ctx)
          coerce_called = true
          return v
        end)),
      })
      store.init(schema)
      local w = proxy.write_proxy(schema, nil, L.SETUP)
      w.feature = nil
      assert.is_false(coerce_called)
    end)
  end)
end)
