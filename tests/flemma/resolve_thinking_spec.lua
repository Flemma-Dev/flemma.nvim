describe("normalize.resolve_thinking", function()
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
    end)

    it("thinking_budget takes priority even when thinking is also set", function()
      local result = normalize.resolve_thinking({ thinking_budget = 8192, thinking = "high" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(8192, result.budget)
      assert.are.equal("medium", result.level)
    end)

    it("thinking_budget=0 disables", function()
      local result = normalize.resolve_thinking({ thinking_budget = 0 }, caps)
      assert.is_false(result.enabled)
      assert.is_nil(result.level)
    end)

    it("thinking='max' maps to 32768", function()
      local result = normalize.resolve_thinking({ thinking = "max" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(32768, result.budget)
      assert.are.equal("max", result.level)
    end)

    it("thinking='high' maps to 16384", function()
      local result = normalize.resolve_thinking({ thinking = "high" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(16384, result.budget)
      assert.are.equal("high", result.level)
    end)

    it("thinking='medium' maps to 8192", function()
      local result = normalize.resolve_thinking({ thinking = "medium" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(8192, result.budget)
      assert.are.equal("medium", result.level)
    end)

    it("thinking='low' maps to 2048", function()
      local result = normalize.resolve_thinking({ thinking = "low" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(2048, result.budget)
      assert.are.equal("low", result.level)
    end)

    it("thinking='minimal' clamps to min 1024 but preserves level", function()
      local result = normalize.resolve_thinking({ thinking = "minimal" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(1024, result.budget)
      assert.are.equal("minimal", result.level)
    end)

    it("thinking=500 clamps to min 1024", function()
      local result = normalize.resolve_thinking({ thinking = 500 }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(1024, result.budget)
      assert.are.equal("low", result.level)
    end)

    it("thinking=5000 (numeric) uses exact value", function()
      local result = normalize.resolve_thinking({ thinking = 5000 }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(5000, result.budget)
      assert.are.equal("medium", result.level)
    end)

    it("thinking=false disables", function()
      local result = normalize.resolve_thinking({ thinking = false }, caps)
      assert.is_false(result.enabled)
      assert.is_nil(result.level)
    end)

    it("thinking=0 disables", function()
      local result = normalize.resolve_thinking({ thinking = 0 }, caps)
      assert.is_false(result.enabled)
      assert.is_nil(result.level)
    end)

    it("nil thinking means disabled", function()
      local result = normalize.resolve_thinking({}, caps)
      assert.is_false(result.enabled)
      assert.is_nil(result.level)
    end)

    it("floors float budget to integer", function()
      local result = normalize.resolve_thinking({ thinking = 5000.7 }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(5000, result.budget)
      assert.are.equal("medium", result.level)
    end)

    it("high thinking_budget maps to max level", function()
      local result = normalize.resolve_thinking({ thinking_budget = 32768 }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(32768, result.budget)
      assert.are.equal("max", result.level)
    end)

    it("thinking_budget=16384 maps to high level", function()
      local result = normalize.resolve_thinking({ thinking_budget = 16384 }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(16384, result.budget)
      assert.are.equal("high", result.level)
    end)

    it("low thinking_budget maps to low level", function()
      local result = normalize.resolve_thinking({ thinking_budget = 1024 }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(1024, result.budget)
      assert.are.equal("low", result.level)
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
      local result = normalize.resolve_thinking({ thinking = "low" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(2048, result.budget)
      assert.are.equal("low", result.level)
    end)

    it("thinking='minimal' maps to 128 (no clamping with min=1)", function()
      local result = normalize.resolve_thinking({ thinking = "minimal" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(128, result.budget)
      assert.are.equal("minimal", result.level)
    end)

    it("thinking=1 uses exact value (min is 1)", function()
      local result = normalize.resolve_thinking({ thinking = 1 }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(1, result.budget)
      assert.are.equal("minimal", result.level)
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
    end)

    it("reasoning takes priority even when thinking is also set", function()
      local result = normalize.resolve_thinking({ reasoning = "high", thinking = "low" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal("high", result.effort)
      assert.are.equal("high", result.level)
    end)

    it("thinking='medium' falls through when no reasoning", function()
      local result = normalize.resolve_thinking({ thinking = "medium" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal("medium", result.effort)
      assert.are.equal("medium", result.level)
    end)

    it("thinking=5000 maps to medium effort", function()
      local result = normalize.resolve_thinking({ thinking = 5000 }, caps)
      assert.is_true(result.enabled)
      assert.are.equal("medium", result.effort)
      assert.are.equal("medium", result.level)
    end)

    it("thinking=1024 maps to low effort", function()
      local result = normalize.resolve_thinking({ thinking = 1024 }, caps)
      assert.is_true(result.enabled)
      assert.are.equal("low", result.effort)
      assert.are.equal("low", result.level)
    end)

    it("thinking=32768 maps to max effort", function()
      local result = normalize.resolve_thinking({ thinking = 32768 }, caps)
      assert.is_true(result.enabled)
      assert.are.equal("max", result.effort)
      assert.are.equal("max", result.level)
    end)

    it("thinking='max' passes through as max effort", function()
      local result = normalize.resolve_thinking({ thinking = "max" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal("max", result.effort)
      assert.are.equal("max", result.level)
    end)

    it("thinking='minimal' passes through as minimal effort", function()
      local result = normalize.resolve_thinking({ thinking = "minimal" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal("minimal", result.effort)
      assert.are.equal("minimal", result.level)
    end)

    it("thinking=100 maps to minimal effort", function()
      local result = normalize.resolve_thinking({ thinking = 100 }, caps)
      assert.is_true(result.enabled)
      assert.are.equal("minimal", result.effort)
      assert.are.equal("minimal", result.level)
    end)

    it("thinking=false disables", function()
      local result = normalize.resolve_thinking({ thinking = false }, caps)
      assert.is_false(result.enabled)
      assert.is_nil(result.level)
    end)

    it("nil thinking means disabled", function()
      local result = normalize.resolve_thinking({}, caps)
      assert.is_false(result.enabled)
      assert.is_nil(result.level)
    end)

    it("empty reasoning string falls through to thinking", function()
      local result = normalize.resolve_thinking({ reasoning = "", thinking = "high" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal("high", result.effort)
      assert.are.equal("high", result.level)
    end)

    describe("with thinking_effort_map", function()
      it("maps minimal to low via effort map", function()
        local model_info = {
          thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "high" },
        }
        local result = normalize.resolve_thinking({ thinking = "minimal" }, caps, model_info)
        assert.is_true(result.enabled)
        assert.are.equal("low", result.effort)
        assert.are.equal("minimal", result.level)
      end)

      it("maps max to xhigh via effort map", function()
        local model_info = {
          thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "xhigh" },
        }
        local result = normalize.resolve_thinking({ thinking = "max" }, caps, model_info)
        assert.is_true(result.enabled)
        assert.are.equal("xhigh", result.effort)
        assert.are.equal("max", result.level)
      end)

      it("maps numeric budget through budget_to_effort then effort map", function()
        local model_info = {
          thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "high" },
        }
        -- 100 maps to "minimal" via budget_to_effort, then "minimal" -> "low" via effort map
        local result = normalize.resolve_thinking({ thinking = 100 }, caps, model_info)
        assert.is_true(result.enabled)
        assert.are.equal("low", result.effort)
        assert.are.equal("minimal", result.level)
      end)

      it("raw reasoning param is also mapped through effort map", function()
        local model_info = {
          thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "xhigh" },
        }
        local result = normalize.resolve_thinking({ reasoning = "minimal" }, caps, model_info)
        assert.is_true(result.enabled)
        assert.are.equal("low", result.effort)
        assert.are.equal("minimal", result.level)
      end)

      it("falls back to raw effort when no effort map", function()
        local result = normalize.resolve_thinking({ thinking = "minimal" }, caps, nil)
        assert.is_true(result.enabled)
        assert.are.equal("minimal", result.effort)
        assert.are.equal("minimal", result.level)
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
      local result = normalize.resolve_thinking({ thinking = "minimal" }, caps, model_info)
      assert.is_true(result.enabled)
      assert.are.equal(512, result.budget)
    end)

    it("falls back to hardcoded budgets when model_info is nil", function()
      local result = normalize.resolve_thinking({ thinking = "minimal" }, caps, nil)
      assert.is_true(result.enabled)
      assert.are.equal(1024, result.budget) -- clamped to caps.min_thinking_budget
    end)

    it("clamps numeric budget to model max_thinking_budget", function()
      local model_info = {
        thinking_budgets = { minimal = 512, low = 2048, medium = 8192, high = 24576 },
        min_thinking_budget = 512,
        max_thinking_budget = 24576,
      }
      local result = normalize.resolve_thinking({ thinking = 50000 }, caps, model_info)
      assert.is_true(result.enabled)
      assert.are.equal(24576, result.budget)
    end)

    it("clamps numeric budget to model min_thinking_budget", function()
      local model_info = {
        thinking_budgets = { minimal = 512, low = 2048, medium = 8192, high = 24576 },
        min_thinking_budget = 512,
        max_thinking_budget = 24576,
      }
      local result = normalize.resolve_thinking({ thinking = 100 }, caps, model_info)
      assert.is_true(result.enabled)
      assert.are.equal(512, result.budget)
    end)

    it("uses model max_thinking_budget for 'max' level", function()
      local model_info = {
        thinking_budgets = { minimal = 512, low = 2048, medium = 8192, high = 24576 },
        min_thinking_budget = 512,
        max_thinking_budget = 24576,
      }
      local result = normalize.resolve_thinking({ thinking = "max" }, caps, model_info)
      assert.is_true(result.enabled)
      assert.are.equal(24576, result.budget)
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
      local result = normalize.resolve_thinking({ thinking = "high" }, caps)
      assert.is_true(result.enabled)
      assert.is_nil(result.mapped_effort)
    end)

    it("maps string level through effort map", function()
      local model_info = {
        thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "max" },
      }
      local result = normalize.resolve_thinking({ thinking = "high" }, caps, model_info)
      assert.is_true(result.enabled)
      assert.are.equal("high", result.mapped_effort)
      assert.are.equal("high", result.level)
    end)

    it("preserves level when budget is clamped (no roundtrip bug)", function()
      local model_info = {
        thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "max" },
        max_thinking_budget = 20000,
      }
      -- "max" → budget clamped to 20000 → budget_to_effort would return "high"
      -- but level should still be "max" (user's intent)
      local result = normalize.resolve_thinking({ thinking = "max" }, caps, model_info)
      assert.is_true(result.enabled)
      assert.are.equal("max", result.level)
      assert.are.equal("max", result.mapped_effort)
    end)

    it("maps numeric input through budget_to_effort then effort map", function()
      local model_info = {
        thinking_effort_map = { minimal = "LOW", low = "LOW", medium = "MEDIUM", high = "HIGH", max = "HIGH" },
      }
      -- 5000 → budget_to_effort → "medium" → effort_map → "MEDIUM"
      local result = normalize.resolve_thinking({ thinking = 5000 }, caps, model_info)
      assert.is_true(result.enabled)
      assert.are.equal("MEDIUM", result.mapped_effort)
      assert.are.equal("medium", result.level)
    end)

    it("maps thinking_budget through effort map", function()
      local model_info = {
        thinking_effort_map = { minimal = "LOW", low = "LOW", medium = "MEDIUM", high = "HIGH", max = "HIGH" },
      }
      -- 16384 → budget_to_effort → "high" → effort_map → "HIGH"
      local result = normalize.resolve_thinking({ thinking_budget = 16384 }, caps, model_info)
      assert.is_true(result.enabled)
      assert.are.equal("HIGH", result.mapped_effort)
      assert.are.equal("high", result.level)
    end)

    it("is nil when effort map does not contain the level", function()
      local model_info = {
        thinking_effort_map = { low = "low", medium = "medium", high = "high" },
      }
      -- "minimal" not in map → mapped_effort is nil
      local result = normalize.resolve_thinking({ thinking = "minimal" }, caps, model_info)
      assert.is_true(result.enabled)
      assert.is_nil(result.mapped_effort)
      assert.are.equal("minimal", result.level)
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
      local result = normalize.resolve_thinking({ thinking = "high" }, caps)
      assert.is_false(result.enabled)
      assert.is_nil(result.level)
    end)

    it("returns disabled even with thinking_budget", function()
      local result = normalize.resolve_thinking({ thinking_budget = 4096 }, caps)
      assert.is_false(result.enabled)
      assert.is_nil(result.level)
    end)
  end)
end)
