local symbols = require("flemma.symbols")

describe("flemma.config.proxy — lenses", function()
  ---@type flemma.config.proxy
  local proxy
  ---@type flemma.config.store
  local store
  ---@type flemma.config.schema
  local s
  ---@type { DEFAULTS: integer, SETUP: integer, RUNTIME: integer, FRONTMATTER: integer }
  local L

  -- Schema with provider-specific sub-objects for composed lens tests.
  -- Mirrors the real config's parameters.<provider> / parameters structure.
  local function make_schema()
    return s.object({
      provider = s.string("anthropic"),
      model = s.optional(s.string()),
      parameters = s.object({
        timeout = s.optional(s.integer()),
        thinking = s.optional(s.string()),
        max_tokens = s.optional(s.integer()),
        anthropic = s.object({
          thinking_budget = s.optional(s.integer()),
          timeout = s.optional(s.integer()),
        }),
        openai = s.object({
          reasoning = s.optional(s.string()),
          timeout = s.optional(s.integer()),
        }),
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
  -- Single-path lens
  -- ---------------------------------------------------------------------------

  describe("single-path lens", function()
    it("reads a scalar relative to the lens root", function()
      local schema = make_schema()
      store.init()
      store.record(L.SETUP, nil, "set", "parameters.timeout", 600)
      local lens = proxy.lens(schema, nil, "parameters")
      assert.equals(600, lens.timeout)
    end)

    it("reads multiple fields from the same lens", function()
      local schema = make_schema()
      store.init()
      store.record(L.SETUP, nil, "set", "parameters.timeout", 600)
      store.record(L.SETUP, nil, "set", "parameters.thinking", "high")
      local lens = proxy.lens(schema, nil, "parameters")
      assert.equals(600, lens.timeout)
      assert.equals("high", lens.thinking)
    end)

    it("returns nil for unset optional fields", function()
      local schema = make_schema()
      store.init()
      local lens = proxy.lens(schema, nil, "parameters")
      assert.is_nil(lens.timeout)
      assert.is_nil(lens.thinking)
    end)

    it("resolves a list field through a lens", function()
      local schema = make_schema()
      store.init()
      store.record(L.DEFAULTS, nil, "set", "tools.auto_approve", { "bash", "grep" })
      local lens = proxy.lens(schema, nil, "tools")
      assert.are.same({ "bash", "grep" }, lens.auto_approve)
    end)

    it("navigates into nested objects through a lens", function()
      local schema = make_schema()
      store.init()
      store.record(L.SETUP, nil, "set", "parameters.anthropic.thinking_budget", 4096)
      local lens = proxy.lens(schema, nil, "parameters")
      assert.equals(4096, lens.anthropic.thinking_budget)
    end)

    it("resolves through buffer layer when bufnr is provided", function()
      local schema = make_schema()
      store.init()
      store.record(L.SETUP, nil, "set", "parameters.timeout", 600)
      store.record(L.FRONTMATTER, 2, "set", "parameters.timeout", 1200)
      local lens = proxy.lens(schema, 2, "parameters")
      assert.equals(1200, lens.timeout)
    end)

    it("buffer layer does not affect a lens with different bufnr", function()
      local schema = make_schema()
      store.init()
      store.record(L.SETUP, nil, "set", "parameters.timeout", 600)
      store.record(L.FRONTMATTER, 2, "set", "parameters.timeout", 1200)
      local lens = proxy.lens(schema, 3, "parameters")
      assert.equals(600, lens.timeout)
    end)

    it("errors on any write attempt", function()
      local schema = make_schema()
      store.init()
      local lens = proxy.lens(schema, nil, "parameters")
      assert.has_error(function()
        lens.timeout = 999
      end)
    end)

    it("errors for an invalid lens path", function()
      local schema = make_schema()
      store.init()
      assert.has_error(function()
        proxy.lens(schema, nil, "nonexistent.path")
      end)
    end)

    it("resolves aliases within a single-path lens", function()
      local schema = make_schema()
      store.init()
      store.record(L.SETUP, nil, "set", "tools.auto_approve", { "bash" })
      local lens = proxy.lens(schema, nil, "tools")
      -- "approve" is an alias for "auto_approve" within tools
      assert.are.same({ "bash" }, lens.approve)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Composed (multi-path) lens
  -- ---------------------------------------------------------------------------

  describe("composed lens — multi-path resolution", function()
    it("returns value from the most specific path", function()
      local schema = make_schema()
      store.init()
      store.record(L.SETUP, nil, "set", "parameters.anthropic.thinking_budget", 4096)
      local lens = proxy.lens(schema, nil, {
        "parameters.anthropic",
        "parameters",
      })
      assert.equals(4096, lens.thinking_budget)
    end)

    it("falls back to general path when specific has no value", function()
      local schema = make_schema()
      store.init()
      store.record(L.SETUP, nil, "set", "parameters.thinking", "high")
      local lens = proxy.lens(schema, nil, {
        "parameters.anthropic",
        "parameters",
      })
      -- "thinking" doesn't exist on anthropic, falls back to parameters
      assert.equals("high", lens.thinking)
    end)

    it("returns nil when no path resolves a value", function()
      local schema = make_schema()
      store.init()
      local lens = proxy.lens(schema, nil, {
        "parameters.anthropic",
        "parameters",
      })
      assert.is_nil(lens.timeout)
    end)

    it("path-first priority: specific path at lower layer beats general at higher layer", function()
      local schema = make_schema()
      store.init()
      -- timeout exists on both parameters.anthropic and parameters
      store.record(L.SETUP, nil, "set", "parameters.anthropic.timeout", 1200)
      store.record(L.RUNTIME, nil, "set", "parameters.timeout", 600)
      local lens = proxy.lens(schema, nil, {
        "parameters.anthropic",
        "parameters",
      })
      -- Specific path (SETUP) is checked first through ALL layers;
      -- the 1200 is found before the general path's 600 is even considered.
      assert.equals(1200, lens.timeout)
    end)

    it("same path at higher layer beats same path at lower layer", function()
      local schema = make_schema()
      store.init()
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
      local schema = make_schema()
      store.init()
      local lens = proxy.lens(schema, nil, {
        "parameters.anthropic",
        "parameters",
      })
      assert.has_error(function()
        lens.timeout = 999
      end)
    end)

    it("errors at construction for an invalid path", function()
      local schema = make_schema()
      store.init()
      assert.has_error(function()
        proxy.lens(schema, nil, {
          "parameters.anthropic",
          "nonexistent.path",
        })
      end)
    end)

    it("resolves through buffer layer", function()
      local schema = make_schema()
      store.init()
      store.record(L.SETUP, nil, "set", "parameters.timeout", 600)
      store.record(L.FRONTMATTER, 5, "set", "parameters.anthropic.timeout", 9999)
      local lens = proxy.lens(schema, 5, {
        "parameters.anthropic",
        "parameters",
      })
      assert.equals(9999, lens.timeout)
    end)

    it("works with three paths in priority order", function()
      local schema = make_schema()
      store.init()
      -- Only the middle path has a value for "timeout"
      store.record(L.SETUP, nil, "set", "parameters.openai.timeout", 3000)
      local lens = proxy.lens(schema, nil, {
        "parameters.anthropic",
        "parameters.openai",
        "parameters",
      })
      assert.equals(3000, lens.timeout)
    end)

    it("skips paths where the key does not exist in schema", function()
      local schema = make_schema()
      store.init()
      -- "reasoning" only exists on openai, not on anthropic or parameters
      store.record(L.SETUP, nil, "set", "parameters.openai.reasoning", "auto")
      local lens = proxy.lens(schema, nil, {
        "parameters.anthropic",
        "parameters.openai",
        "parameters",
      })
      assert.equals("auto", lens.reasoning)
    end)

    it("independent lenses do not share state", function()
      local schema = make_schema()
      store.init()
      store.record(L.SETUP, nil, "set", "parameters.anthropic.thinking_budget", 4096)
      store.record(L.SETUP, nil, "set", "parameters.openai.reasoning", "auto")

      local anthropic_lens = proxy.lens(schema, nil, {
        "parameters.anthropic",
        "parameters",
      })
      local openai_lens = proxy.lens(schema, nil, {
        "parameters.openai",
        "parameters",
      })

      assert.equals(4096, anthropic_lens.thinking_budget)
      assert.is_nil(openai_lens.thinking_budget)
      assert.equals("auto", openai_lens.reasoning)
      assert.is_nil(anthropic_lens.reasoning)
    end)
  end)
end)
