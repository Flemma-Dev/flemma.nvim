local registry = require("flemma.provider.registry")

describe("flemma.models", function()
  describe("ModelInfo schema", function()
    it("anthropic models have per-model cache pricing", function()
      local info = registry.get_model_info("anthropic", "claude-sonnet-4-6")
      assert.is_not_nil(info)
      assert.is_not_nil(info.pricing.cache_read)
      assert.is_not_nil(info.pricing.cache_write)
      assert.is_number(info.pricing.cache_read)
      assert.is_number(info.pricing.cache_write)
    end)

    it("openai models have per-model cache_read pricing", function()
      local info = registry.get_model_info("openai", "gpt-5")
      assert.is_not_nil(info)
      assert.is_not_nil(info.pricing.cache_read)
      assert.is_number(info.pricing.cache_read)
    end)

    it("anthropic thinking models have thinking_budgets", function()
      local info = registry.get_model_info("anthropic", "claude-sonnet-4-5")
      assert.is_not_nil(info)
      assert.is_not_nil(info.thinking_budgets)
      assert.is_number(info.thinking_budgets.minimal)
      assert.is_number(info.thinking_budgets.low)
      assert.is_number(info.thinking_budgets.medium)
      assert.is_number(info.thinking_budgets.high)
    end)

    it("vertex thinking models have thinking_budgets", function()
      local info = registry.get_model_info("vertex", "gemini-2.5-flash")
      assert.is_not_nil(info)
      assert.is_not_nil(info.thinking_budgets)
      assert.is_number(info.thinking_budgets.minimal)
    end)

    it("vertex flash-lite has correct thinking budget range", function()
      local info = registry.get_model_info("vertex", "gemini-2.5-flash-lite")
      assert.is_not_nil(info)
      assert.is_not_nil(info.thinking_budgets)
      -- From the Vertex API error: supported values are 512 to 24576
      assert.are.equal(512, info.min_thinking_budget)
      assert.are.equal(24576, info.max_thinking_budget)
    end)

    it("vertex 2.5 pro has a thinking budget floor of 128, not 1", function()
      -- Google's thinking_budget table gives 2.5 Pro a minimum of 128 where 2.5
      -- Flash allows 1 — thinking cannot be turned off on Pro at all.
      local pro = registry.get_model_info("vertex", "gemini-2.5-pro")
      assert.are.equal(128, pro.min_thinking_budget)
      assert.are.equal(32768, pro.max_thinking_budget)
      assert.are.equal(1, registry.get_model_info("vertex", "gemini-2.5-flash").min_thinking_budget)
    end)

    it("vertex gemini 3 models carry no thinking budgets", function()
      -- Gemini 3 is thinkingLevel-only; Google publishes a thinkingBudget range for
      -- 2.5 alone, and a Gemini 3 request carrying both parameters returns an error.
      for _, model in ipairs({ "gemini-3.1-pro-preview", "gemini-3-pro-preview", "gemini-3-flash-preview" }) do
        local info = registry.get_model_info("vertex", model)
        assert.is_not_nil(info.thinking_effort_map, model .. " should map effort levels")
        assert.is_nil(info.thinking_budgets, model .. " should not declare thinking_budgets")
        assert.is_nil(info.min_thinking_budget, model .. " should not declare a budget floor")
        assert.is_nil(info.max_thinking_budget, model .. " should not declare a budget ceiling")
      end
    end)

    it("gpt-5.6 models carry the family's cache-write price", function()
      -- GPT-5.6 is the first OpenAI family to bill cache writes; earlier families
      -- show "-" on the pricing page and correctly omit the field.
      assert.are.equal(6.25, registry.get_model_info("openai", "gpt-5.6-sol").pricing.cache_write)
      assert.are.equal(6.25, registry.get_model_info("openai", "gpt-5.6").pricing.cache_write)
      assert.are.equal(3.125, registry.get_model_info("openai", "gpt-5.6-terra").pricing.cache_write)
      assert.are.equal(1.25, registry.get_model_info("openai", "gpt-5.6-luna").pricing.cache_write)
      assert.is_nil(registry.get_model_info("openai", "gpt-5.5").pricing.cache_write)
    end)

    it("gpt-5-pro reserves its 400K context for output, not input", function()
      -- 272K of gpt-5-pro's 400K window is max output, leaving 128K for input —
      -- the inverse of every other GPT-5 model, which reserves 128K for output.
      local pro = registry.get_model_info("openai", "gpt-5-pro")
      assert.are.equal(128000, pro.max_input_tokens)
      assert.are.equal(272000, pro.max_output_tokens)
      assert.are.equal(272000, registry.get_model_info("openai", "gpt-5").max_input_tokens)
      assert.are.equal(128000, registry.get_model_info("openai", "gpt-5").max_output_tokens)
    end)

    it("moonshot k2.7-code forces thinking rather than toggling it", function()
      -- Thinking cannot be disabled on the k2.7-code family: `{"type":"disabled"}`
      -- returns an error, unlike k2.6/k2.5 where it is a supported value.
      for _, model in ipairs({ "kimi-k2.7-code", "kimi-k2.7-code-highspeed" }) do
        assert.are.equal("forced", registry.get_model_info("moonshot", model).meta.thinking_mode)
      end
      assert.are.equal("optional", registry.get_model_info("moonshot", "kimi-k2.6").meta.thinking_mode)
    end)

    it("anthropic models have min_cache_tokens", function()
      local info = registry.get_model_info("anthropic", "claude-haiku-4-5")
      assert.is_not_nil(info)
      assert.is_not_nil(info.min_cache_tokens)
      assert.are.equal(4096, info.min_cache_tokens)
    end)
  end)

  describe("thinking_effort_map", function()
    it("openai gpt-5.2 maps minimal to low", function()
      local info = registry.get_model_info("openai", "gpt-5.2")
      assert.is_not_nil(info.thinking_effort_map)
      assert.are.equal("low", info.thinking_effort_map.minimal)
    end)

    it("openai gpt-5.2 maps max to xhigh", function()
      local info = registry.get_model_info("openai", "gpt-5.2")
      assert.are.equal("xhigh", info.thinking_effort_map.max)
    end)

    it("openai gpt-5.2-pro maps unsupported low efforts to medium", function()
      local info = registry.get_model_info("openai", "gpt-5.2-pro")
      assert.is_not_nil(info.meta)
      assert.is_true(info.meta.reasoning_effort)
      assert.is_not_nil(info.thinking_effort_map)
      assert.are.equal("medium", info.thinking_effort_map.minimal)
      assert.are.equal("medium", info.thinking_effort_map.low)
      assert.are.equal("xhigh", info.thinking_effort_map.max)
    end)

    it("openai gpt-5.4-pro maps unsupported low efforts to medium", function()
      local info = registry.get_model_info("openai", "gpt-5.4-pro")
      assert.is_not_nil(info.meta)
      assert.is_true(info.meta.reasoning_effort)
      assert.is_not_nil(info.thinking_effort_map)
      assert.are.equal("medium", info.thinking_effort_map.minimal)
      assert.are.equal("medium", info.thinking_effort_map.low)
      assert.are.equal("xhigh", info.thinking_effort_map.max)
    end)

    it("openai gpt-5-pro maps every effort to high", function()
      local info = registry.get_model_info("openai", "gpt-5-pro")
      assert.is_not_nil(info.meta)
      assert.is_true(info.meta.reasoning_effort)
      assert.is_not_nil(info.thinking_effort_map)
      assert.are.equal("high", info.thinking_effort_map.minimal)
      assert.are.equal("high", info.thinking_effort_map.low)
      assert.are.equal("high", info.thinking_effort_map.medium)
      assert.are.equal("high", info.thinking_effort_map.high)
      assert.are.equal("high", info.thinking_effort_map.max)
    end)

    it("openai gpt-5 maps minimal to minimal (native support)", function()
      local info = registry.get_model_info("openai", "gpt-5")
      assert.are.equal("minimal", info.thinking_effort_map.minimal)
    end)

    it("openai gpt-5 maps max to high (no xhigh support)", function()
      local info = registry.get_model_info("openai", "gpt-5")
      assert.are.equal("high", info.thinking_effort_map.max)
    end)

    it("anthropic opus-4-6 maps max to max", function()
      local info = registry.get_model_info("anthropic", "claude-opus-4-6")
      assert.is_not_nil(info.thinking_effort_map)
      assert.are.equal("max", info.thinking_effort_map.max)
    end)

    it("anthropic sonnet-4-6 maps max to max", function()
      -- `max` effort is available on every adaptive-thinking Claude model, Sonnet included;
      -- only `xhigh` is restricted to Opus 4.7+ / Sonnet 5 / Fable 5.
      local info = registry.get_model_info("anthropic", "claude-sonnet-4-6")
      assert.are.equal("max", info.thinking_effort_map.max)
    end)

    it("anthropic opus-5 maps max to max", function()
      local info = registry.get_model_info("anthropic", "claude-opus-5")
      assert.is_not_nil(info.thinking_effort_map)
      assert.are.equal("max", info.thinking_effort_map.max)
    end)

    it("openai gpt-5.6 maps max to max (native support)", function()
      local info = registry.get_model_info("openai", "gpt-5.6-sol")
      assert.are.equal("max", info.thinking_effort_map.max)
    end)

    it("anthropic sonnet-4-6 maps minimal to low", function()
      local info = registry.get_model_info("anthropic", "claude-sonnet-4-6")
      assert.are.equal("low", info.thinking_effort_map.minimal)
    end)

    it("vertex gemini-3-flash-preview maps minimal to MINIMAL", function()
      local info = registry.get_model_info("vertex", "gemini-3-flash-preview")
      assert.are.equal("MINIMAL", info.thinking_effort_map.minimal)
    end)

    it("vertex gemini-3.1-pro-preview maps minimal to LOW", function()
      local info = registry.get_model_info("vertex", "gemini-3.1-pro-preview")
      assert.is_not_nil(info.thinking_effort_map)
      assert.are.equal("LOW", info.thinking_effort_map.minimal)
    end)

    it("vertex gemini-3.1-pro-preview maps medium to MEDIUM (3.1 Pro added MEDIUM)", function()
      local info = registry.get_model_info("vertex", "gemini-3.1-pro-preview")
      assert.is_not_nil(info.thinking_effort_map)
      assert.are.equal("MEDIUM", info.thinking_effort_map.medium)
    end)

    it("moonshot kimi-k3 clamps the canonical levels onto low/high/max", function()
      local info = registry.get_model_info("moonshot", "kimi-k3")
      assert.is_not_nil(info.meta)
      assert.are.equal("effort", info.meta.thinking_mode)
      assert.is_not_nil(info.thinking_effort_map)
      assert.are.equal("low", info.thinking_effort_map.minimal)
      assert.are.equal("low", info.thinking_effort_map.low)
      assert.are.equal("high", info.thinking_effort_map.medium)
      assert.are.equal("high", info.thinking_effort_map.high)
      assert.are.equal("max", info.thinking_effort_map.max)
    end)

    it("moonshot thinking-toggle models have no effort map", function()
      -- K2 toggles thinking on and off with no depth control; a map would be inert.
      local info = registry.get_model_info("moonshot", "kimi-k2.6")
      assert.are.equal("optional", info.meta.thinking_mode)
      assert.is_nil(info.thinking_effort_map)
    end)

    it("non-thinking models have no effort map", function()
      local info = registry.get_model_info("openai", "gpt-4o")
      assert.is_nil(info.thinking_effort_map)
    end)

    it("anthropic opus-4-5 maps max to high (no max support)", function()
      local info = registry.get_model_info("anthropic", "claude-opus-4-5")
      assert.is_not_nil(info.thinking_effort_map)
      assert.are.equal("high", info.thinking_effort_map.max)
      assert.are.equal("low", info.thinking_effort_map.minimal)
    end)

    it("budget-only anthropic models (sonnet-4-5, haiku-4-5) have no effort map", function()
      local info = registry.get_model_info("anthropic", "claude-sonnet-4-5")
      assert.is_nil(info.thinking_effort_map)
    end)

    it("budget-only vertex models (gemini-2.5) have no effort map", function()
      local info = registry.get_model_info("vertex", "gemini-2.5-pro")
      assert.is_nil(info.thinking_effort_map)
    end)
  end)

  describe("high_cost_threshold", function()
    it("is available via config", function()
      local config = require("flemma.config")
      local threshold = config.materialize().ui.pricing.high_cost_threshold
      assert.is_number(threshold)
    end)

    it("claude-opus-4-6 sits exactly at the boundary and does not exceed it", function()
      local config = require("flemma.config")
      local threshold = config.materialize().ui.pricing.high_cost_threshold
      local pricing = registry.get_model_info("anthropic", "claude-opus-4-6").pricing
      local combined = pricing.input + pricing.output
      assert.are.equal(30, combined)
      assert.is_false(combined > threshold)
    end)

    it("expensive models exceed the threshold", function()
      local config = require("flemma.config")
      local threshold = config.materialize().ui.pricing.high_cost_threshold
      local pricing = registry.get_model_info("openai", "gpt-5.4-pro").pricing
      local combined = pricing.input + pricing.output
      assert.is_true(combined > threshold)
    end)
  end)
end)
