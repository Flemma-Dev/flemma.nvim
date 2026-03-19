local symbols = require("flemma.symbols")

describe("flemma.config — integration", function()
  ---@type flemma.config.facade
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
    package.loaded["flemma.config.facade"] = nil
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.schema"] = nil
    package.loaded["flemma.config.schema.types"] = nil
    package.loaded["flemma.config.schema.navigation"] = nil
    package.loaded["flemma.loader"] = nil
    config = require("flemma.config.facade")
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
end)
