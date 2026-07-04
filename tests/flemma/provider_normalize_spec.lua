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

  describe("resolve_thinking", function()
    local normalize

    before_each(function()
      package.loaded["flemma.provider.normalize"] = nil
      normalize = require("flemma.provider.normalize")
    end)

    describe("budget-based provider (Anthropic-like)", function()
      local caps = {
        supports_thinking_budget = true,
        supports_reasoning = false,
        outputs_thinking = true,
        output_has_thoughts = true,
        min_thinking_budget = 1024,
      }

      it("thinking_budget takes priority over unified thinking", function()
        local result = normalize.resolve_thinking({ thinking_budget = 8192 }, caps)
        assert.is_true(result.enabled)
        assert.are.equal(8192, result.budget)
        assert.are.equal("medium", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking_budget takes priority even when thinking is also set", function()
        local result = normalize.resolve_thinking({
          thinking_budget = 8192,
          thinking = { level = "high", foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal(8192, result.budget)
        assert.are.equal("medium", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking_budget=0 disables", function()
        local result = normalize.resolve_thinking({ thinking_budget = 0 }, caps)
        assert.is_false(result.enabled)
        assert.is_nil(result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking='max' maps to 32768", function()
        local result = normalize.resolve_thinking({
          thinking = { level = "max", foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal(32768, result.budget)
        assert.are.equal("max", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking='high' maps to 16384", function()
        local result = normalize.resolve_thinking({
          thinking = { level = "high", foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal(16384, result.budget)
        assert.are.equal("high", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking='medium' maps to 8192", function()
        local result = normalize.resolve_thinking({
          thinking = { level = "medium", foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal(8192, result.budget)
        assert.are.equal("medium", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking='low' maps to 2048", function()
        local result = normalize.resolve_thinking({
          thinking = { level = "low", foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal(2048, result.budget)
        assert.are.equal("low", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking='minimal' clamps to min 1024 but preserves level", function()
        local result = normalize.resolve_thinking({
          thinking = { level = "minimal", foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal(1024, result.budget)
        assert.are.equal("minimal", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking=500 clamps to min 1024", function()
        local result = normalize.resolve_thinking({
          thinking = { level = 500, foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal(1024, result.budget)
        assert.are.equal("low", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking=5000 (numeric) uses exact value", function()
        local result = normalize.resolve_thinking({
          thinking = { level = 5000, foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal(5000, result.budget)
        assert.are.equal("medium", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking=false disables", function()
        local result = normalize.resolve_thinking({
          thinking = { level = false, foreign = "preserve" },
        }, caps)
        assert.is_false(result.enabled)
        assert.is_nil(result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking=0 disables", function()
        local result = normalize.resolve_thinking({
          thinking = { level = 0, foreign = "preserve" },
        }, caps)
        assert.is_false(result.enabled)
        assert.is_nil(result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("nil thinking means disabled", function()
        local result = normalize.resolve_thinking({}, caps)
        assert.is_false(result.enabled)
        assert.is_nil(result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("floors float budget to integer", function()
        local result = normalize.resolve_thinking({
          thinking = { level = 5000.7, foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal(5000, result.budget)
        assert.are.equal("medium", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("high thinking_budget maps to max level", function()
        local result = normalize.resolve_thinking({ thinking_budget = 32768 }, caps)
        assert.is_true(result.enabled)
        assert.are.equal(32768, result.budget)
        assert.are.equal("max", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking_budget=16384 maps to high level", function()
        local result = normalize.resolve_thinking({ thinking_budget = 16384 }, caps)
        assert.is_true(result.enabled)
        assert.are.equal(16384, result.budget)
        assert.are.equal("high", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("low thinking_budget maps to low level", function()
        local result = normalize.resolve_thinking({ thinking_budget = 1024 }, caps)
        assert.is_true(result.enabled)
        assert.are.equal(1024, result.budget)
        assert.are.equal("low", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("foreign is preserved from thinking table", function()
        local result = normalize.resolve_thinking({
          thinking = { level = "high", foreign = "drop" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal("drop", result.foreign)
      end)

      it("foreign defaults to preserve when thinking is nil", function()
        local result = normalize.resolve_thinking({}, caps)
        assert.are.equal("preserve", result.foreign)
      end)

      it("foreign is preserved even when thinking is disabled", function()
        local result = normalize.resolve_thinking({
          thinking = { level = false, foreign = "drop" },
        }, caps)
        assert.is_false(result.enabled)
        assert.are.equal("drop", result.foreign)
      end)

      it("partial table { foreign = 'drop' } keeps thinking enabled at default level", function()
        local result = normalize.resolve_thinking({
          thinking = { level = "high", foreign = "drop" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal(16384, result.budget)
        assert.are.equal("high", result.level)
        assert.are.equal("drop", result.foreign)
      end)
    end)

    describe("budget-based provider with min_thinking_budget=1 (Vertex-like)", function()
      local caps = {
        supports_thinking_budget = true,
        supports_reasoning = false,
        outputs_thinking = true,
        output_has_thoughts = false,
        min_thinking_budget = 1,
      }

      it("thinking='low' maps to 2048 (no clamping needed)", function()
        local result = normalize.resolve_thinking({
          thinking = { level = "low", foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal(2048, result.budget)
        assert.are.equal("low", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking='minimal' maps to 128 (no clamping with min=1)", function()
        local result = normalize.resolve_thinking({
          thinking = { level = "minimal", foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal(128, result.budget)
        assert.are.equal("minimal", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking=1 uses exact value (min is 1)", function()
        local result = normalize.resolve_thinking({
          thinking = { level = 1, foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal(1, result.budget)
        assert.are.equal("minimal", result.level)
        assert.are.equal("preserve", result.foreign)
      end)
    end)

    describe("effort-based provider (OpenAI-like)", function()
      local caps = {
        supports_reasoning = true,
        supports_thinking_budget = false,
        outputs_thinking = true,
        output_has_thoughts = true,
      }

      it("reasoning takes priority over unified thinking", function()
        local result = normalize.resolve_thinking({ reasoning = "high" }, caps)
        assert.is_true(result.enabled)
        assert.are.equal("high", result.effort)
        assert.are.equal("high", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("reasoning takes priority even when thinking is also set", function()
        local result = normalize.resolve_thinking({
          reasoning = "high",
          thinking = { level = "low", foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal("high", result.effort)
        assert.are.equal("high", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking='medium' falls through when no reasoning", function()
        local result = normalize.resolve_thinking({
          thinking = { level = "medium", foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal("medium", result.effort)
        assert.are.equal("medium", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking=5000 maps to medium effort", function()
        local result = normalize.resolve_thinking({
          thinking = { level = 5000, foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal("medium", result.effort)
        assert.are.equal("medium", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking=1024 maps to low effort", function()
        local result = normalize.resolve_thinking({
          thinking = { level = 1024, foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal("low", result.effort)
        assert.are.equal("low", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking=32768 maps to max effort", function()
        local result = normalize.resolve_thinking({
          thinking = { level = 32768, foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal("max", result.effort)
        assert.are.equal("max", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking='max' passes through as max effort", function()
        local result = normalize.resolve_thinking({
          thinking = { level = "max", foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal("max", result.effort)
        assert.are.equal("max", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking='minimal' passes through as minimal effort", function()
        local result = normalize.resolve_thinking({
          thinking = { level = "minimal", foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal("minimal", result.effort)
        assert.are.equal("minimal", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking=100 maps to minimal effort", function()
        local result = normalize.resolve_thinking({
          thinking = { level = 100, foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal("minimal", result.effort)
        assert.are.equal("minimal", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking=false disables with explicit flag", function()
        local result = normalize.resolve_thinking({
          thinking = { level = false, foreign = "preserve" },
        }, caps)
        assert.is_false(result.enabled)
        assert.is_true(result.explicit)
        assert.is_nil(result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("thinking=0 disables with explicit flag", function()
        local result = normalize.resolve_thinking({
          thinking = { level = 0, foreign = "preserve" },
        }, caps)
        assert.is_false(result.enabled)
        assert.is_true(result.explicit)
        assert.are.equal("preserve", result.foreign)
      end)

      it("nil thinking means disabled without explicit flag", function()
        local result = normalize.resolve_thinking({}, caps)
        assert.is_false(result.enabled)
        assert.is_nil(result.explicit)
        assert.is_nil(result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("empty reasoning string falls through to thinking", function()
        local result = normalize.resolve_thinking({
          reasoning = "",
          thinking = { level = "high", foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal("high", result.effort)
        assert.are.equal("high", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("foreign is preserved from thinking table", function()
        local result = normalize.resolve_thinking({
          thinking = { level = "high", foreign = "drop" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal("drop", result.foreign)
      end)

      it("foreign defaults to preserve when thinking is nil", function()
        local result = normalize.resolve_thinking({}, caps)
        assert.are.equal("preserve", result.foreign)
      end)

      it("foreign is preserved even when thinking is disabled", function()
        local result = normalize.resolve_thinking({
          thinking = { level = false, foreign = "drop" },
        }, caps)
        assert.is_false(result.enabled)
        assert.are.equal("drop", result.foreign)
      end)

      it("partial table { foreign = 'drop' } keeps thinking enabled at default level", function()
        local result = normalize.resolve_thinking({
          thinking = { level = "high", foreign = "drop" },
        }, caps)
        assert.is_true(result.enabled)
        assert.are.equal("high", result.effort)
        assert.are.equal("high", result.level)
        assert.are.equal("drop", result.foreign)
      end)

      describe("with thinking_effort_map", function()
        it("maps minimal to low via effort map", function()
          local model_info = {
            thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "high" },
          }
          local result = normalize.resolve_thinking({
            thinking = { level = "minimal", foreign = "preserve" },
          }, caps, model_info)
          assert.is_true(result.enabled)
          assert.are.equal("low", result.effort)
          assert.are.equal("minimal", result.level)
          assert.are.equal("preserve", result.foreign)
        end)

        it("maps max to xhigh via effort map", function()
          local model_info = {
            thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "xhigh" },
          }
          local result = normalize.resolve_thinking({
            thinking = { level = "max", foreign = "preserve" },
          }, caps, model_info)
          assert.is_true(result.enabled)
          assert.are.equal("xhigh", result.effort)
          assert.are.equal("max", result.level)
          assert.are.equal("preserve", result.foreign)
        end)

        it("maps numeric budget through budget_to_effort then effort map", function()
          local model_info = {
            thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "high" },
          }
          -- 100 maps to "minimal" via budget_to_effort, then "minimal" -> "low" via effort map
          local result = normalize.resolve_thinking({
            thinking = { level = 100, foreign = "preserve" },
          }, caps, model_info)
          assert.is_true(result.enabled)
          assert.are.equal("low", result.effort)
          assert.are.equal("minimal", result.level)
          assert.are.equal("preserve", result.foreign)
        end)

        it("raw reasoning param is also mapped through effort map", function()
          local model_info = {
            thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "xhigh" },
          }
          local result = normalize.resolve_thinking({ reasoning = "minimal" }, caps, model_info)
          assert.is_true(result.enabled)
          assert.are.equal("low", result.effort)
          assert.are.equal("minimal", result.level)
          assert.are.equal("preserve", result.foreign)
        end)

        it("falls back to raw effort when no effort map", function()
          local result = normalize.resolve_thinking({
            thinking = { level = "minimal", foreign = "preserve" },
          }, caps, nil)
          assert.is_true(result.enabled)
          assert.are.equal("minimal", result.effort)
          assert.are.equal("minimal", result.level)
          assert.are.equal("preserve", result.foreign)
        end)
      end)
    end)

    describe("per-model thinking budgets", function()
      local caps = {
        supports_thinking_budget = true,
        supports_reasoning = false,
        outputs_thinking = true,
        output_has_thoughts = true,
        min_thinking_budget = 1024,
      }

      it("uses model thinking_budgets when available", function()
        local model_info = {
          thinking_budgets = { minimal = 512, low = 2048, medium = 8192, high = 24576 },
          min_thinking_budget = 512,
          max_thinking_budget = 24576,
        }
        local result = normalize.resolve_thinking({
          thinking = { level = "minimal", foreign = "preserve" },
        }, caps, model_info)
        assert.is_true(result.enabled)
        assert.are.equal(512, result.budget)
        assert.are.equal("preserve", result.foreign)
      end)

      it("falls back to hardcoded budgets when model_info is nil", function()
        local result = normalize.resolve_thinking({
          thinking = { level = "minimal", foreign = "preserve" },
        }, caps, nil)
        assert.is_true(result.enabled)
        assert.are.equal(1024, result.budget) -- clamped to caps.min_thinking_budget
        assert.are.equal("preserve", result.foreign)
      end)

      it("clamps numeric budget to model max_thinking_budget", function()
        local model_info = {
          thinking_budgets = { minimal = 512, low = 2048, medium = 8192, high = 24576 },
          min_thinking_budget = 512,
          max_thinking_budget = 24576,
        }
        local result = normalize.resolve_thinking({
          thinking = { level = 50000, foreign = "preserve" },
        }, caps, model_info)
        assert.is_true(result.enabled)
        assert.are.equal(24576, result.budget)
        assert.are.equal("preserve", result.foreign)
      end)

      it("clamps numeric budget to model min_thinking_budget", function()
        local model_info = {
          thinking_budgets = { minimal = 512, low = 2048, medium = 8192, high = 24576 },
          min_thinking_budget = 512,
          max_thinking_budget = 24576,
        }
        local result = normalize.resolve_thinking({
          thinking = { level = 100, foreign = "preserve" },
        }, caps, model_info)
        assert.is_true(result.enabled)
        assert.are.equal(512, result.budget)
        assert.are.equal("preserve", result.foreign)
      end)

      it("uses model max_thinking_budget for 'max' level", function()
        local model_info = {
          thinking_budgets = { minimal = 512, low = 2048, medium = 8192, high = 24576 },
          min_thinking_budget = 512,
          max_thinking_budget = 24576,
        }
        local result = normalize.resolve_thinking({
          thinking = { level = "max", foreign = "preserve" },
        }, caps, model_info)
        assert.is_true(result.enabled)
        assert.are.equal(24576, result.budget)
        assert.are.equal("preserve", result.foreign)
      end)

      it("clamps thinking_budget to model max", function()
        local model_info = {
          thinking_budgets = { minimal = 512, low = 2048, medium = 8192, high = 24576 },
          min_thinking_budget = 512,
          max_thinking_budget = 24576,
        }
        local result = normalize.resolve_thinking({ thinking_budget = 99999 }, caps, model_info)
        assert.is_true(result.enabled)
        assert.are.equal(24576, result.budget)
        assert.are.equal("preserve", result.foreign)
      end)
    end)

    describe("mapped_effort for budget-based providers", function()
      local caps = {
        supports_thinking_budget = true,
        supports_reasoning = false,
        outputs_thinking = true,
        output_has_thoughts = true,
        min_thinking_budget = 1024,
      }

      it("is nil when model has no effort map", function()
        local result = normalize.resolve_thinking({
          thinking = { level = "high", foreign = "preserve" },
        }, caps)
        assert.is_true(result.enabled)
        assert.is_nil(result.mapped_effort)
        assert.are.equal("preserve", result.foreign)
      end)

      it("maps string level through effort map", function()
        local model_info = {
          thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "max" },
        }
        local result = normalize.resolve_thinking({
          thinking = { level = "high", foreign = "preserve" },
        }, caps, model_info)
        assert.is_true(result.enabled)
        assert.are.equal("high", result.mapped_effort)
        assert.are.equal("high", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("preserves level when budget is clamped (no roundtrip bug)", function()
        local model_info = {
          thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "max" },
          max_thinking_budget = 20000,
        }
        -- "max" -> budget clamped to 20000 -> budget_to_effort would return "high"
        -- but level should still be "max" (user's intent)
        local result = normalize.resolve_thinking({
          thinking = { level = "max", foreign = "preserve" },
        }, caps, model_info)
        assert.is_true(result.enabled)
        assert.are.equal("max", result.level)
        assert.are.equal("max", result.mapped_effort)
        assert.are.equal("preserve", result.foreign)
      end)

      it("maps numeric input through budget_to_effort then effort map", function()
        local model_info = {
          thinking_effort_map = { minimal = "LOW", low = "LOW", medium = "MEDIUM", high = "HIGH", max = "HIGH" },
        }
        -- 5000 -> budget_to_effort -> "medium" -> effort_map -> "MEDIUM"
        local result = normalize.resolve_thinking({
          thinking = { level = 5000, foreign = "preserve" },
        }, caps, model_info)
        assert.is_true(result.enabled)
        assert.are.equal("MEDIUM", result.mapped_effort)
        assert.are.equal("medium", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("maps thinking_budget through effort map", function()
        local model_info = {
          thinking_effort_map = { minimal = "LOW", low = "LOW", medium = "MEDIUM", high = "HIGH", max = "HIGH" },
        }
        -- 16384 -> budget_to_effort -> "high" -> effort_map -> "HIGH"
        local result = normalize.resolve_thinking({ thinking_budget = 16384 }, caps, model_info)
        assert.is_true(result.enabled)
        assert.are.equal("HIGH", result.mapped_effort)
        assert.are.equal("high", result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("is nil when effort map does not contain the level", function()
        local model_info = {
          thinking_effort_map = { low = "low", medium = "medium", high = "high" },
        }
        -- "minimal" not in map -> mapped_effort is nil
        local result = normalize.resolve_thinking({
          thinking = { level = "minimal", foreign = "preserve" },
        }, caps, model_info)
        assert.is_true(result.enabled)
        assert.is_nil(result.mapped_effort)
        assert.are.equal("minimal", result.level)
        assert.are.equal("preserve", result.foreign)
      end)
    end)

    describe("provider with neither capability", function()
      local caps = {
        supports_reasoning = false,
        supports_thinking_budget = false,
        outputs_thinking = false,
        output_has_thoughts = false,
      }

      it("always returns disabled", function()
        local result = normalize.resolve_thinking({
          thinking = { level = "high", foreign = "preserve" },
        }, caps)
        assert.is_false(result.enabled)
        assert.is_nil(result.level)
        assert.are.equal("preserve", result.foreign)
      end)

      it("returns disabled even with thinking_budget", function()
        local result = normalize.resolve_thinking({ thinking_budget = 4096 }, caps)
        assert.is_false(result.enabled)
        assert.is_nil(result.level)
        assert.are.equal("preserve", result.foreign)
      end)
    end)
  end)
end)
