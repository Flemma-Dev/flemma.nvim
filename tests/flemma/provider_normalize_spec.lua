describe("flemma.provider.normalize", function()
  describe("resolve_max_tokens", function()
    local normalize

    before_each(function()
      package.loaded["flemma.provider.normalize"] = nil
      package.loaded["flemma.provider.registry"] = nil

      -- Ensure registry is initialized with built-in providers
      local registry = require("flemma.provider.registry")
      registry.setup()

      normalize = require("flemma.provider.normalize")
    end)

    it("resolves percentage with known model", function()
      -- claude-sonnet-4-6 has max_output_tokens = 64000
      local params = { max_tokens = "50%" }
      normalize.resolve_max_tokens("anthropic", "claude-sonnet-4-6", params)
      assert.equals(32000, params.max_tokens)
    end)

    it("resolves percentage with unknown model to fallback", function()
      local params = { max_tokens = "50%" }
      normalize.resolve_max_tokens("anthropic", "custom-model", params)
      assert.equals(4000, params.max_tokens)
    end)

    it("clamps small percentage to minimum", function()
      -- 1% of 64000 = 640, below MIN_MAX_TOKENS (1024)
      local params = { max_tokens = "1%" }
      normalize.resolve_max_tokens("anthropic", "claude-haiku-4-5", params)
      assert.equals(1024, params.max_tokens)
    end)

    it("resolves 100% to full max", function()
      -- claude-sonnet-4-6 has max_output_tokens = 64000
      local params = { max_tokens = "100%" }
      normalize.resolve_max_tokens("anthropic", "claude-sonnet-4-6", params)
      assert.equals(64000, params.max_tokens)
    end)

    it("passes through integer within limits", function()
      local params = { max_tokens = 8000 }
      normalize.resolve_max_tokens("anthropic", "claude-sonnet-4-6", params)
      assert.equals(8000, params.max_tokens)
    end)

    it("clamps integer over limit", function()
      -- claude-sonnet-4-6 has max_output_tokens = 64000
      local params = { max_tokens = 100000 }
      normalize.resolve_max_tokens("anthropic", "claude-sonnet-4-6", params)
      assert.equals(64000, params.max_tokens)
    end)

    it("raises integer below model minimum", function()
      -- kimi-k2.6 has min_output_tokens = 16000
      local params = { max_tokens = 8000 }
      normalize.resolve_max_tokens("moonshot", "kimi-k2.6", params)
      assert.equals(16000, params.max_tokens)
    end)

    it("percentage respects model minimum floor", function()
      -- kimi-k2.6 has max=65536, min=16000; 10% of 65536 = 6553 → raised to 16000
      local params = { max_tokens = "10%" }
      normalize.resolve_max_tokens("moonshot", "kimi-k2.6", params)
      assert.equals(16000, params.max_tokens)
    end)

    it("passes through integer with unknown model (no data to clamp)", function()
      local params = { max_tokens = 999999 }
      normalize.resolve_max_tokens("anthropic", "custom-model", params)
      assert.equals(999999, params.max_tokens)
    end)

    it("falls back when model info has no max_output_tokens", function()
      -- Register a custom provider with a model that has pricing but no max_output_tokens
      local registry = require("flemma.provider.registry")
      registry.register("partial", {
        module = "flemma.provider.adapters.openai",
        capabilities = {
          supports_reasoning = false,
          supports_thinking_budget = false,
          outputs_thinking = false,
          output_has_thoughts = false,
        },
        display_name = "Partial",
        default_model = "partial-model",
        models = {
          ["partial-model"] = {
            pricing = { input = 1.0, output = 2.0 },
            -- no max_output_tokens
          },
        },
      })

      local params = { max_tokens = "50%" }
      normalize.resolve_max_tokens("partial", "partial-model", params)
      assert.equals(4000, params.max_tokens)
    end)

    it("falls back for invalid string format", function()
      local params = { max_tokens = "abc" }
      normalize.resolve_max_tokens("anthropic", "claude-sonnet-4-6", params)
      assert.equals(4000, params.max_tokens)
    end)

    it("is a no-op for nil max_tokens", function()
      local params = {}
      normalize.resolve_max_tokens("anthropic", "claude-sonnet-4-6", params)
      assert.is_nil(params.max_tokens)
    end)
  end)

  describe("merge_parameters", function()
    local registry = require("flemma.provider.registry")
    local normalize = require("flemma.provider.normalize")
    local config_facade = require("flemma.config")
    local schema_definition = require("flemma.config.schema")

    before_each(function()
      package.loaded["flemma.config"] = nil
      package.loaded["flemma.config.store"] = nil
      package.loaded["flemma.provider.registry"] = nil
      package.loaded["flemma.provider.normalize"] = nil
      config_facade = require("flemma.config")
      registry = require("flemma.provider.registry")
      normalize = require("flemma.provider.normalize")

      config_facade.init(schema_definition)
      registry.setup()
    end)

    it("copies scalar parameters", function()
      local config = config_facade.materialize()
      local flat = normalize.merge_parameters("anthropic", config)
      assert.are.equal("50%", flat.max_tokens)
      assert.are.equal(600, flat.timeout)
      assert.are.equal("short", flat.cache_retention)
    end)

    it("copies table params that are not provider sub-tables", function()
      config_facade.apply(config_facade.LAYERS.SETUP, {
        parameters = { thinking = { level = "high", foreign = "preserve" } },
      })
      local config = config_facade.materialize()
      local flat = normalize.merge_parameters("anthropic", config)
      assert.are.same({ level = "high", foreign = "preserve" }, flat.thinking)
    end)

    it("excludes provider sub-tables from general copy", function()
      config_facade.apply(config_facade.LAYERS.SETUP, {
        parameters = { anthropic = { thinking_budget = 4096 } },
      })
      local config = config_facade.materialize()
      local flat = normalize.merge_parameters("openai", config)
      -- anthropic sub-table should not leak into openai's flattened params
      assert.is_nil(flat.anthropic)
    end)

    it("overlays provider-specific scalar values", function()
      config_facade.apply(config_facade.LAYERS.SETUP, {
        parameters = { anthropic = { thinking_budget = 4096 } },
      })
      local config = config_facade.materialize()
      local flat = normalize.merge_parameters("anthropic", config)
      assert.are.equal(4096, flat.thinking_budget)
    end)

    it("deep merges table values from provider-specific section", function()
      -- Test deep merge directly with a raw config table (bypassing the facade)
      -- to exercise the code path where both general and provider-specific have
      -- table values for the same key.
      local config = {
        model = "test-model",
        parameters = {
          thinking = { level = "high", foreign = "preserve" },
          anthropic = { thinking = { level = "low" } },
        },
      }
      local flat = normalize.merge_parameters("anthropic", config)
      -- Provider-specific "level" should override, but "foreign" should be preserved
      assert.are.same({ level = "low", foreign = "preserve" }, flat.thinking)
    end)

    it("provider scalar overwrites general table", function()
      -- Test scalar overwrite directly with a raw config table (bypassing the facade)
      -- to exercise the code path where provider-specific has a scalar for a key
      -- that is a table in the general section.
      local config = {
        model = "test-model",
        parameters = {
          thinking = { level = "high", foreign = "preserve" },
          openai = { thinking = false },
        },
      }
      local flat = normalize.merge_parameters("openai", config)
      -- Provider-specific scalar (false) should fully overwrite the general table
      assert.are.equal(false, flat.thinking)
    end)

    it("includes model from config", function()
      config_facade.apply(config_facade.LAYERS.SETUP, { model = "claude-sonnet-4-5" })
      local config = config_facade.materialize()
      local flat = normalize.merge_parameters("anthropic", config)
      assert.are.equal("claude-sonnet-4-5", flat.model)
    end)

    it("provider sub-table accepts general parameters through DISCOVER", function()
      config_facade.apply(config_facade.LAYERS.SETUP, {
        parameters = {
          thinking = { level = "high", foreign = "preserve" },
          openai = { thinking = { level = "low", foreign = "drop" } },
        },
      })
      local config = config_facade.materialize()
      local flat = normalize.merge_parameters("openai", config)
      assert.are.same({ level = "low", foreign = "drop" }, flat.thinking)
    end)

    it("provider sub-table accepts max_tokens override", function()
      config_facade.apply(config_facade.LAYERS.SETUP, {
        parameters = {
          openai = { max_tokens = 2048 },
        },
      })
      local config = config_facade.materialize()
      local flat = normalize.merge_parameters("openai", config)
      assert.are.equal(2048, flat.max_tokens)
    end)

    it("provider sub-table retains adapter-specific keys alongside general parameters", function()
      config_facade.apply(config_facade.LAYERS.SETUP, {
        parameters = {
          openai = { reasoning = "high", temperature = 0.5 },
        },
      })
      local config = config_facade.materialize()
      local flat = normalize.merge_parameters("openai", config)
      assert.are.equal("high", flat.reasoning)
      assert.are.equal(0.5, flat.temperature)
    end)
  end)
end)
