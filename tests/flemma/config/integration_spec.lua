local symbols = require("flemma.symbols")

describe("flemma.config — integration", function()
  ---@type flemma.config.Facade
  local config
  ---@type flemma.config.schema
  local s
  ---@type { DEFAULTS: integer, SETUP: integer, RUNTIME: integer, FRONTMATTER: integer }
  local L

  -- Schema that mirrors the real config structure (simplified).
  -- Covers scalars with/without defaults, optional fields, nested objects,
  -- provider-specific sub-objects, lists, and root-level aliases.
  local function make_schema()
    return s.object({
      provider = s.string("anthropic"),
      model = s.string("claude-sonnet-4-20250514"),
      parameters = s.object({
        max_tokens = s.optional(s.integer()),
        timeout = s.optional(s.integer()),
        thinking = s.optional(s.string()),
        anthropic = s.object({
          thinking_budget = s.optional(s.integer()),
          timeout = s.optional(s.integer()),
        }),
      }),
      tools = s.object({
        modules = s.list(s.string(), {}),
        auto_approve = s.list(s.string(), { "$default" }),
        timeout = s.integer(120000),
      }),
      [symbols.ALIASES] = {
        timeout = "parameters.timeout",
        thinking = "parameters.thinking",
        max_tokens = "parameters.max_tokens",
      },
    })
  end

  before_each(function()
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.schema"] = nil
    package.loaded["flemma.config.schema.types"] = nil
    package.loaded["flemma.config.schema.navigation"] = nil
    package.loaded["flemma.loader"] = nil
    config = require("flemma.config")
    s = require("flemma.config.schema")
    L = config.LAYERS
  end)

  -- ---------------------------------------------------------------------------
  -- Defaults materialization
  -- ---------------------------------------------------------------------------

  describe("defaults materialization", function()
    it("schema defaults populate the DEFAULTS layer", function()
      config.init(make_schema())
      local cfg = config.get()
      assert.equals("anthropic", cfg.provider)
      assert.equals("claude-sonnet-4-20250514", cfg.model)
      assert.equals(120000, cfg.tools.timeout)
      assert.are.same({ "$default" }, cfg.tools.auto_approve)
      assert.are.same({}, cfg.tools.modules)
    end)

    it("optional fields without defaults resolve to nil", function()
      config.init(make_schema())
      local cfg = config.get()
      assert.is_nil(cfg.parameters.timeout)
      assert.is_nil(cfg.parameters.thinking)
      assert.is_nil(cfg.parameters.max_tokens)
    end)

    it("defaults are inspectable with source 'D'", function()
      config.init(make_schema())
      local result = config.inspect(nil, "provider")
      assert.equals("anthropic", result.value)
      assert.equals("D", result.layer)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Setup from plain Lua table
  -- ---------------------------------------------------------------------------

  describe("setup from plain Lua table", function()
    it("apply converts a nested table into individual set ops", function()
      config.init(make_schema())
      config.apply(L.SETUP, {
        provider = "vertex",
        model = "gemini-pro",
        parameters = {
          timeout = 30000,
          thinking = "medium",
        },
        tools = {
          auto_approve = { "bash", "grep" },
          timeout = 60000,
        },
      })

      local cfg = config.get()
      assert.equals("vertex", cfg.provider)
      assert.equals("gemini-pro", cfg.model)
      assert.equals(30000, cfg.parameters.timeout)
      assert.equals("medium", cfg.parameters.thinking)
      assert.are.same({ "bash", "grep" }, cfg.tools.auto_approve)
      assert.equals(60000, cfg.tools.timeout)
    end)

    it("apply resolves aliases in input", function()
      config.init(make_schema())
      config.apply(L.SETUP, {
        timeout = 600,
        thinking = "high",
      })

      local cfg = config.get()
      assert.equals(600, cfg.parameters.timeout)
      assert.equals("high", cfg.parameters.thinking)
    end)

    it("apply returns error for wrong type", function()
      config.init(make_schema())
      local ok, err = config.apply(L.SETUP, { provider = 42 })
      assert.is_nil(ok)
      assert.is_truthy(err)
      assert.matches("validation error", err)
    end)

    it("apply returns error for unknown keys", function()
      config.init(make_schema())
      local ok, err = config.apply(L.SETUP, { nonexistent = "value" })
      assert.is_nil(ok)
      assert.is_truthy(err)
      assert.matches("unknown key", err)
    end)

    it("setup values are inspectable with source 'S'", function()
      config.init(make_schema())
      config.apply(L.SETUP, { provider = "openai" })
      local result = config.inspect(nil, "provider")
      assert.equals("openai", result.value)
      assert.equals("S", result.layer)
    end)

    it("setup overrides defaults", function()
      config.init(make_schema())
      config.apply(L.SETUP, { provider = "openai" })
      assert.equals("openai", config.get().provider)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Multi-layer composition
  -- ---------------------------------------------------------------------------

  describe("multi-layer composition", function()
    it("init + setup + runtime + frontmatter compose correctly", function()
      config.init(make_schema())

      -- Setup
      config.apply(L.SETUP, {
        provider = "openai",
        parameters = { timeout = 600 },
      })

      -- Runtime
      local runtime_w = config.writer(nil, L.RUNTIME)
      runtime_w.model = "gpt-4"

      -- Frontmatter for buffer 1
      local fm_w = config.writer(1, L.FRONTMATTER)
      fm_w.parameters.thinking = "high"

      -- Global: no frontmatter
      local global = config.get()
      assert.equals("openai", global.provider)
      assert.equals("gpt-4", global.model)
      assert.equals(600, global.parameters.timeout)
      assert.is_nil(global.parameters.thinking)

      -- Buffer 1: includes frontmatter
      local buf = config.get(1)
      assert.equals("openai", buf.provider)
      assert.equals("gpt-4", buf.model)
      assert.equals(600, buf.parameters.timeout)
      assert.equals("high", buf.parameters.thinking)
    end)

    it("higher layers override lower layers for the same path", function()
      config.init(make_schema())
      config.apply(L.SETUP, { provider = "openai" })
      config.writer(nil, L.RUNTIME).provider = "vertex"
      assert.equals("vertex", config.get().provider)
    end)

    it("clearing frontmatter removes buffer overrides", function()
      config.init(make_schema())
      config.apply(L.SETUP, { provider = "anthropic" })

      local w = config.writer(1, L.FRONTMATTER)
      w.provider = "vertex"
      assert.equals("vertex", config.get(1).provider)

      w[symbols.CLEAR]()
      assert.equals("anthropic", config.get(1).provider)
    end)

    it("runtime ops accumulate across multiple writes", function()
      config.init(make_schema())

      local w = config.writer(nil, L.RUNTIME)
      w.provider = "anthropic"
      w.model = "claude-haiku"
      w.parameters.timeout = 1200

      -- Second round of writes: overrides provider and model, timeout persists
      w.provider = "vertex"
      w.model = "gemini-pro"

      local cfg = config.get()
      assert.equals("vertex", cfg.provider)
      assert.equals("gemini-pro", cfg.model)
      assert.equals(1200, cfg.parameters.timeout) -- persists from first write
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Alias flow end-to-end
  -- ---------------------------------------------------------------------------

  describe("alias flow end-to-end", function()
    it("write via alias, read via canonical path", function()
      config.init(make_schema())
      local w = config.writer(1, L.FRONTMATTER)
      w.thinking = "low"
      assert.equals("low", config.get(1).parameters.thinking)
    end)

    it("write via canonical path, read via alias", function()
      config.init(make_schema())
      local w = config.writer(nil, L.SETUP)
      w.parameters.thinking = "high"
      assert.equals("high", config.get().thinking)
    end)

    it("apply via alias, read via both alias and canonical", function()
      config.init(make_schema())
      config.apply(L.SETUP, { thinking = "medium" })
      local cfg = config.get()
      assert.equals("medium", cfg.thinking)
      assert.equals("medium", cfg.parameters.thinking)
    end)

    it("alias in frontmatter overrides canonical in setup", function()
      config.init(make_schema())
      config.apply(L.SETUP, { parameters = { timeout = 600 } })
      config.writer(1, L.FRONTMATTER).timeout = 1200
      assert.equals(1200, config.get(1).parameters.timeout)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Provider lens composition end-to-end
  -- ---------------------------------------------------------------------------

  describe("provider lens composition end-to-end", function()
    it("composed lens resolves from specific path first", function()
      config.init(make_schema())
      config.apply(L.SETUP, {
        parameters = {
          anthropic = { thinking_budget = 4096 },
        },
      })

      local params = config.lens(nil, {
        "parameters.anthropic",
        "parameters",
      })
      assert.equals(4096, params.thinking_budget)
    end)

    it("composed lens falls back to general path", function()
      config.init(make_schema())
      config.apply(L.SETUP, {
        parameters = { thinking = "high" },
      })

      local params = config.lens(nil, {
        "parameters.anthropic",
        "parameters",
      })
      -- "thinking" doesn't exist on anthropic, falls back to parameters
      assert.equals("high", params.thinking)
    end)

    it("path-first priority: specific at lower layer beats general at higher layer", function()
      config.init(make_schema())

      -- Specific path: setup layer
      config.apply(L.SETUP, {
        parameters = {
          anthropic = { timeout = 1200 },
        },
      })

      -- General path: runtime layer (higher priority, but less specific)
      config.writer(nil, L.RUNTIME).parameters.timeout = 600

      local params = config.lens(nil, {
        "parameters.anthropic",
        "parameters",
      })
      -- Specific path checked first through all layers
      assert.equals(1200, params.timeout)
    end)

    it("frontmatter overrides specific lens path", function()
      config.init(make_schema())
      config.apply(L.SETUP, {
        parameters = {
          anthropic = { thinking_budget = 4096 },
        },
      })
      config.writer(1, L.FRONTMATTER).parameters.anthropic.thinking_budget = 8192

      local params = config.lens(1, {
        "parameters.anthropic",
        "parameters",
      })
      assert.equals(8192, params.thinking_budget)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Buffer isolation
  -- ---------------------------------------------------------------------------

  describe("buffer isolation", function()
    it("multiple buffers have independent frontmatter layers", function()
      config.init(make_schema())
      config.apply(L.SETUP, { provider = "anthropic" })

      config.writer(1, L.FRONTMATTER).model = "claude-haiku"
      config.writer(2, L.FRONTMATTER).model = "claude-opus"

      assert.equals("claude-haiku", config.get(1).model)
      assert.equals("claude-opus", config.get(2).model)
    end)

    it("global config is unaffected by buffer frontmatter", function()
      config.init(make_schema())
      config.writer(1, L.FRONTMATTER).provider = "vertex"
      assert.equals("anthropic", config.get().provider)
    end)

    it("clearing one buffer does not affect another", function()
      config.init(make_schema())
      config.writer(1, L.FRONTMATTER).model = "claude-haiku"
      config.writer(2, L.FRONTMATTER).model = "claude-opus"

      config.writer(1, L.FRONTMATTER)[symbols.CLEAR]()
      assert.equals("claude-sonnet-4-20250514", config.get(1).model)
      assert.equals("claude-opus", config.get(2).model)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Introspection
  -- ---------------------------------------------------------------------------

  describe("introspection", function()
    it("inspect returns value and source layer", function()
      config.init(make_schema())
      config.apply(L.SETUP, { provider = "openai" })
      config.writer(nil, L.RUNTIME).provider = "vertex"

      local result = config.inspect(nil, "provider")
      assert.equals("vertex", result.value)
      assert.equals("R", result.layer)
    end)

    it("inspect returns combined source for multi-layer lists", function()
      config.init(make_schema())
      -- Defaults layer has auto_approve = { "$default" } from materialization.
      -- Setup layer appends "bash" via writer proxy.
      config.writer(nil, L.SETUP).tools.auto_approve:append("bash")

      local result = config.inspect(nil, "tools.auto_approve")
      assert.are.same({ "$default", "bash" }, result.value)
      assert.equals("D+S", result.layer)
    end)

    it("dump_layer returns raw ops for a layer", function()
      config.init(make_schema())
      config.apply(L.SETUP, { provider = "openai" })
      local ops = config.dump_layer(L.SETUP, nil)
      assert.equals(1, #ops)
      assert.equals("set", ops[1].op)
      assert.equals("provider", ops[1].path)
      assert.equals("openai", ops[1].value)
    end)

    it("inspect returns nil value and nil layer for unset fields", function()
      config.init(make_schema())
      local result = config.inspect(nil, "parameters.timeout")
      assert.is_nil(result.value)
      assert.is_nil(result.layer)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- defer_discover two-pass boot
  -- ---------------------------------------------------------------------------

  describe("defer_discover two-pass boot", function()
    -- Schema with a DISCOVER-backed object for testing two-pass boot.
    -- The DISCOVER callback resolves keys from a mutable registry table,
    -- simulating provider/tool registration between pass 1 and pass 2.
    local function make_discover_schema()
      local registry = {}
      local schema = s.object({
        provider = s.string("default"),
        parameters = s.object({
          timeout = s.optional(s.integer()),
          -- Built-in provider (statically defined)
          builtin = s.object({
            key_a = s.optional(s.string()),
          }),
          -- Dynamic providers resolved lazily
          [symbols.DISCOVER] = function(key)
            return registry[key]
          end,
        }),
        tools = s.object({
          modules = s.list(s.string(), {}),
          timeout = s.integer(30),
          -- Dynamic tool config resolved lazily
          [symbols.DISCOVER] = function(key)
            return registry["tool_" .. key]
          end,
        }),
        [symbols.ALIASES] = {
          timeout = "parameters.timeout",
        },
      })
      return schema, registry
    end

    it("defers writes to DISCOVER-backed objects", function()
      local schema, registry = make_discover_schema()
      config.init(schema)

      -- Pass 1: custom_provider is unknown (not in registry yet)
      local ok, err, deferred = config.apply(L.SETUP, {
        provider = "test",
        parameters = {
          timeout = 600,
          custom_provider = { special_key = "value" },
        },
      }, { defer_discover = true })

      assert.is_true(ok)
      assert.is_nil(err)
      assert.is_truthy(deferred)
      assert.equals(1, #deferred)
      assert.equals("parameters.custom_provider", deferred[1].path)

      -- Known keys were applied immediately
      assert.equals("test", config.get().provider)
      assert.equals(600, config.get().parameters.timeout)

      -- Register the schema
      registry.custom_provider = s.object({
        special_key = s.optional(s.string()),
      })

      -- Pass 2: deferred writes now resolve
      local failures = config.apply_deferred(L.SETUP, deferred)
      assert.is_nil(failures)

      -- Value is accessible
      assert.equals("value", config.get().parameters.custom_provider.special_key)
    end)

    it("defers multiple DISCOVER writes across different objects", function()
      local schema, registry = make_discover_schema()
      config.init(schema)

      local ok, err, deferred = config.apply(L.SETUP, {
        parameters = {
          custom_provider = { key = "a" },
        },
        tools = {
          bash = { shell = "/bin/zsh" },
        },
      }, { defer_discover = true })

      assert.is_true(ok)
      assert.is_nil(err)
      assert.is_truthy(deferred)
      assert.equals(2, #deferred)

      -- Register both schemas
      registry.custom_provider = s.object({ key = s.optional(s.string()) })
      registry.tool_bash = s.object({ shell = s.optional(s.string()) })

      local failures = config.apply_deferred(L.SETUP, deferred)
      assert.is_nil(failures)

      assert.equals("a", config.get().parameters.custom_provider.key)
      assert.equals("/bin/zsh", config.get().tools.bash.shell)
    end)

    it("returns nil deferred when nothing needs deferring", function()
      local schema = make_discover_schema()
      config.init(schema)

      local ok, err, deferred = config.apply(L.SETUP, {
        provider = "openai",
        parameters = { timeout = 1200 },
      }, { defer_discover = true })

      assert.is_true(ok)
      assert.is_nil(err)
      assert.is_nil(deferred)
    end)

    it("non-DISCOVER errors are still fatal in pass 1", function()
      local schema = make_discover_schema()
      config.init(schema)

      -- Root object has no DISCOVER, so unknown root keys are immediate errors
      local ok, err, deferred = config.apply(L.SETUP, {
        completely_unknown = "value",
      }, { defer_discover = true })

      assert.is_nil(ok)
      assert.is_truthy(err)
      assert.matches("unknown key", err)
      assert.is_nil(deferred)
    end)

    it("pass 2 fails for genuinely unknown keys", function()
      local schema = make_discover_schema()
      config.init(schema)

      local ok, _, deferred = config.apply(L.SETUP, {
        parameters = { nonexistent = "value" },
      }, { defer_discover = true })

      assert.is_true(ok)
      assert.is_truthy(deferred)

      -- Don't register anything — DISCOVER still returns nil
      local failures = config.apply_deferred(L.SETUP, deferred)
      assert.is_truthy(failures)
      assert.equals(1, #failures)
      assert.matches("unknown key", failures[1].error)
    end)

    it("known keys on DISCOVER objects are not deferred", function()
      local schema = make_discover_schema()
      config.init(schema)

      -- "builtin" is a statically defined field on the parameters object
      local ok, err, deferred = config.apply(L.SETUP, {
        parameters = {
          builtin = { key_a = "known" },
        },
      }, { defer_discover = true })

      assert.is_true(ok)
      assert.is_nil(err)
      assert.is_nil(deferred)
      assert.equals("known", config.get().parameters.builtin.key_a)
    end)

    it("without defer_discover, unknown DISCOVER keys fail immediately", function()
      local schema = make_discover_schema()
      config.init(schema)

      -- Normal mode (no defer) — DISCOVER returns nil → error
      local ok, err = config.apply(L.SETUP, {
        parameters = { custom_provider = { key = "a" } },
      })

      assert.is_nil(ok)
      assert.is_truthy(err)
      assert.matches("unknown key", err)
    end)

    it("alias keys at root level are not deferred", function()
      local schema = make_discover_schema()
      config.init(schema)

      local ok, err, deferred = config.apply(L.SETUP, {
        timeout = 1200, -- alias for parameters.timeout
      }, { defer_discover = true })

      assert.is_true(ok)
      assert.is_nil(err)
      assert.is_nil(deferred)
      assert.equals(1200, config.get().parameters.timeout)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Materialization
  -- ---------------------------------------------------------------------------

  describe("materialize", function()
    it("produces a plain table from defaults", function()
      config.init(make_schema())
      local result = config.materialize()
      assert.equals("table", type(result))
      assert.equals("anthropic", result.provider)
      assert.equals("claude-sonnet-4-20250514", result.model)
      assert.equals(120000, result.tools.timeout)
      assert.are.same({ "$default" }, result.tools.auto_approve)
      assert.are.same({}, result.tools.modules)
    end)

    it("includes setup layer values", function()
      config.init(make_schema())
      config.apply(L.SETUP, {
        provider = "vertex",
        parameters = { timeout = 600, thinking = "high" },
      })
      local result = config.materialize()
      assert.equals("vertex", result.provider)
      assert.equals(600, result.parameters.timeout)
      assert.equals("high", result.parameters.thinking)
    end)

    it("includes runtime layer overrides", function()
      config.init(make_schema())
      config.apply(L.SETUP, { provider = "anthropic" })
      config.writer(nil, L.RUNTIME).provider = "vertex"
      local result = config.materialize()
      assert.equals("vertex", result.provider)
    end)

    it("includes buffer-specific frontmatter values", function()
      config.init(make_schema())
      config.writer(1, L.FRONTMATTER).parameters.thinking = "low"
      local global = config.materialize()
      local buf1 = config.materialize(1)
      assert.is_nil(global.parameters.thinking)
      assert.equals("low", buf1.parameters.thinking)
    end)

    it("returns an independent copy safe for mutation", function()
      config.init(make_schema())
      local a = config.materialize()
      local b = config.materialize()
      a.provider = "mutated"
      assert.equals("anthropic", b.provider)
    end)

    it("includes DISCOVER-cached fields after resolution", function()
      local registry = {}
      local schema = s.object({
        extensions = s.object({
          known = s.string("x"),
          [symbols.DISCOVER] = function(key)
            return registry[key]
          end,
        }),
      })
      config.init(schema)

      -- Register and write through a discover-backed key
      registry.custom = s.object({ value = s.optional(s.string()) })
      config.writer(nil, L.SETUP).extensions.custom.value = "y"

      local result = config.materialize()
      assert.equals("x", result.extensions.known)
      assert.equals("y", result.extensions.custom.value)
    end)

    it("resolves lists correctly", function()
      config.init(make_schema())
      config.writer(nil, L.SETUP).tools.auto_approve:append("bash")
      local result = config.materialize()
      assert.are.same({ "$default", "bash" }, result.tools.auto_approve)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- layer_has_set
  -- ---------------------------------------------------------------------------

  describe("layer_has_set", function()
    it("detects set op on FRONTMATTER layer", function()
      config.init(make_schema())
      local w = config.writer(1, L.FRONTMATTER)
      w.tools.auto_approve = { "bash" }
      assert.is_true(config.layer_has_set(L.FRONTMATTER, 1, "tools.auto_approve"))
    end)

    it("returns false when only append ops exist", function()
      config.init(make_schema())
      config.writer(1, L.FRONTMATTER).tools.auto_approve:append("bash")
      assert.is_false(config.layer_has_set(L.FRONTMATTER, 1, "tools.auto_approve"))
    end)

    it("returns false for different buffer", function()
      config.init(make_schema())
      config.writer(1, L.FRONTMATTER).tools.auto_approve = { "bash" }
      assert.is_false(config.layer_has_set(L.FRONTMATTER, 2, "tools.auto_approve"))
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- config.finalize()
  -- ---------------------------------------------------------------------------

  describe("config.finalize()", function()
    it("applies deferred writes", function()
      local discovered_schema = s.object({
        custom_param = s.optional(s.integer()),
      })
      -- Simulate module not yet registered: DISCOVER returns nil on pass 1
      local registered = false
      local schema = s.object({
        provider = s.string("anthropic"),
        parameters = s.object({
          timeout = s.optional(s.integer()),
          [symbols.DISCOVER] = function(key)
            if key == "custom" and registered then
              return discovered_schema
            end
            return nil
          end,
        }),
      })
      config.init(schema)
      -- Pass 1: deferred because custom is not yet discoverable
      local ok, _, deferred = config.apply(L.SETUP, {
        parameters = { custom = { custom_param = 42 } },
      }, { defer_discover = true })
      assert.is_true(ok)
      assert.is_not_nil(deferred)

      -- Simulate module registration
      registered = true

      -- Finalize replays deferred (DISCOVER now resolves)
      local failures = config.finalize(L.SETUP, deferred)
      assert.is_nil(failures)
      assert.equals(42, config.get().parameters.custom.custom_param)
    end)

    it("runs coerce transforms on stored ops", function()
      local preset_data = {
        ["$default"] = { "bash", "grep", "find" },
      }
      local schema = s.object({
        tools = s.object({
          auto_approve = s.list(s.string(), { "$default" }):coerce(function(value, ctx)
            if not ctx then
              return value
            end
            if type(value) == "string" and vim.startswith(value, "$") then
              return preset_data[value] or value
            end
            return value
          end),
        }),
      })
      config.init(schema)
      -- After init, L10 has set(["$default"])
      -- Finalize should expand $default (ctx now available)
      config.finalize(L.DEFAULTS)
      local result = config.get().tools.auto_approve
      assert.are.same({ "bash", "grep", "find" }, result)
    end)

    it("coerce expands preset removes across layers", function()
      local preset_data = {
        ["$default"] = { "bash", "grep" },
      }
      local coerce_fn = function(value, ctx)
        if not ctx then
          return value
        end
        if type(value) == "string" and vim.startswith(value, "$") then
          return preset_data[value] or value
        end
        return value
      end
      local schema = s.object({
        items = s.list(s.string(), { "$default" }):coerce(coerce_fn),
      })
      config.init(schema)
      -- L10: set(["$default"]), FRONTMATTER: remove("$default")
      config.writer(1, L.FRONTMATTER).items:remove("$default")
      config.finalize(L.DEFAULTS)
      -- $default expanded in both layers:
      -- L10: set(["bash","grep"]), F(1): remove("bash"), remove("grep")
      assert.are.same({}, config.get(1).items)
    end)

    it("coerce with context can read other config values", function()
      local schema = s.object({
        presets = s.object({
          fast = s.object({
            names = s.list(s.string(), { "a", "b" }),
          }),
        }),
        items = s.list(s.string(), { "$fast" }):coerce(function(value, ctx)
          if not ctx then
            return value
          end
          if type(value) == "string" and vim.startswith(value, "$") then
            local preset_names = ctx.get("presets." .. value:sub(2) .. ".names")
            return preset_names or value
          end
          return value
        end),
      })
      config.init(schema)
      config.finalize(L.DEFAULTS)
      assert.are.same({ "a", "b" }, config.get().items)
    end)

    it("returns failures from deferred writes", function()
      local schema = s.object({
        provider = s.string("anthropic"),
      })
      config.init(schema)
      local failures = config.finalize(L.SETUP, { { path = "nonexistent", value = "x" } })
      assert.is_not_nil(failures)
      assert.equals(1, #failures)
      assert.matches("nonexistent", failures[1].path)
    end)

    it("returns nil when no deferred writes provided", function()
      config.init(make_schema())
      local failures = config.finalize(L.SETUP)
      assert.is_nil(failures)
    end)

    it("deferred writes and coerce transforms interact correctly", function()
      local preset_data = {
        ["$default"] = { "bash", "grep" },
      }
      local registered = false
      local discovered_schema = s.object({
        custom_param = s.optional(s.integer()),
      })
      local schema = s.object({
        tools = s.object({
          auto_approve = s.list(s.string(), { "$default" }):coerce(function(value, ctx)
            if not ctx then
              return value
            end
            if type(value) == "string" and vim.startswith(value, "$") then
              return preset_data[value] or value
            end
            return value
          end),
          [symbols.DISCOVER] = function(key)
            if key == "custom" and registered then
              return discovered_schema
            end
            return nil
          end,
        }),
      })
      config.init(schema)
      -- Pass 1: deferred because "custom" not yet discoverable
      local ok, _, deferred = config.apply(L.SETUP, {
        tools = { custom = { custom_param = 99 } },
      }, { defer_discover = true })
      assert.is_true(ok)
      assert.is_not_nil(deferred)

      -- Simulate module registration
      registered = true

      -- Finalize: replays deferred (custom now resolves) AND runs coerce ($default expands)
      local failures = config.finalize(L.SETUP, deferred)
      assert.is_nil(failures)
      assert.equals(99, config.get().tools.custom.custom_param)
      assert.are.same({ "bash", "grep" }, config.get().tools.auto_approve)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Coerce expansion + frontmatter remove across layers
  -- ---------------------------------------------------------------------------

  describe("coerce expansion + frontmatter remove", function()
    -- Simulates tools.auto_approve with $preset expansion:
    -- $default expands to { "bash", "ls" }, "search" is a plain tool name.
    -- Frontmatter :remove("$default") expands at write time to
    -- remove("bash") + remove("ls"), leaving only "search".
    local function make_coerce_schema()
      local presets = {
        ["$default"] = { "bash", "ls" },
      }
      local coerce_fn = function(value, ctx)
        if not ctx then
          return value
        end
        if type(value) == "string" and vim.startswith(value, "$") then
          return presets[value] or value
        end
        return value
      end
      return s.object({
        items = s.list(s.string(), { "$default", "search" }):coerce(coerce_fn),
      })
    end

    it("finalize expands $default in defaults layer", function()
      local schema = make_coerce_schema()
      config.init(schema)
      config.finalize(L.DEFAULTS)
      -- After finalize, "$default" in L10 should be expanded to "bash", "ls"
      assert.are.same({ "bash", "ls", "search" }, config.get().items)
    end)

    it("frontmatter remove of $default expands at write time, no second finalize needed", function()
      local schema = make_coerce_schema()
      config.init(schema)
      -- Boot: finalize expands L10 "$default" → ["bash", "ls", "search"]
      config.finalize(L.DEFAULTS)
      assert.are.same({ "bash", "ls", "search" }, config.get().items)

      -- Frontmatter: remove("$default") coerces at write time → remove("bash") + remove("ls")
      config.writer(1, L.FRONTMATTER).items:remove("$default")
      -- No second finalize — per-op coerce expanded the remove immediately
      assert.are.same({ "search" }, config.get(1).items)
    end)

    it("frontmatter remove does not affect buffers without the remove", function()
      local schema = make_coerce_schema()
      config.init(schema)
      config.finalize(L.DEFAULTS)

      config.writer(1, L.FRONTMATTER).items:remove("$default")
      -- Buffer 1: $default removed, only "search" remains
      assert.are.same({ "search" }, config.get(1).items)
      -- Buffer 2 (no frontmatter): full expanded list
      assert.are.same({ "bash", "ls", "search" }, config.get(2).items)
    end)

    it("frontmatter list set expands per-item at write time", function()
      local schema = make_coerce_schema()
      config.init(schema)
      config.finalize(L.DEFAULTS)

      -- Assign a list with a $preset reference — expanded at write time
      config.writer(1, L.FRONTMATTER).items = { "$default" }
      assert.are.same({ "bash", "ls" }, config.get(1).items)
    end)
  end)
end)
