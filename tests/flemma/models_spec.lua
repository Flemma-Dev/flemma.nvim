describe("flemma.models", function()
  local models_data

  before_each(function()
    package.loaded["flemma.models"] = nil
    models_data = require("flemma.models")
  end)

  describe("ModelInfo schema", function()
    it("anthropic models have per-model cache pricing", function()
      local info = models_data.providers.anthropic.models["claude-sonnet-4-6"]
      assert.is_not_nil(info)
      assert.is_not_nil(info.pricing.cache_read)
      assert.is_not_nil(info.pricing.cache_write)
      assert.is_number(info.pricing.cache_read)
      assert.is_number(info.pricing.cache_write)
    end)

    it("openai models have per-model cache_read pricing", function()
      local info = models_data.providers.openai.models["gpt-5"]
      assert.is_not_nil(info)
      assert.is_not_nil(info.pricing.cache_read)
      assert.is_number(info.pricing.cache_read)
    end)

    it("anthropic thinking models have thinking_budgets", function()
      local info = models_data.providers.anthropic.models["claude-sonnet-4-5"]
      assert.is_not_nil(info)
      assert.is_not_nil(info.thinking_budgets)
      assert.is_number(info.thinking_budgets.minimal)
      assert.is_number(info.thinking_budgets.low)
      assert.is_number(info.thinking_budgets.medium)
      assert.is_number(info.thinking_budgets.high)
    end)

    it("vertex thinking models have thinking_budgets", function()
      local info = models_data.providers.vertex.models["gemini-2.5-flash"]
      assert.is_not_nil(info)
      assert.is_not_nil(info.thinking_budgets)
      assert.is_number(info.thinking_budgets.minimal)
    end)

    it("vertex flash-lite has correct thinking budget range", function()
      local info = models_data.providers.vertex.models["gemini-2.5-flash-lite"]
      assert.is_not_nil(info)
      assert.is_not_nil(info.thinking_budgets)
      -- From the Vertex API error: supported values are 512 to 24576
      assert.are.equal(512, info.min_thinking_budget)
      assert.are.equal(24576, info.max_thinking_budget)
    end)

    it("anthropic models have min_cache_tokens", function()
      local info = models_data.providers.anthropic.models["claude-haiku-4-5"]
      assert.is_not_nil(info)
      assert.is_not_nil(info.min_cache_tokens)
      assert.are.equal(4096, info.min_cache_tokens)
    end)
  end)

  describe("thinking_effort_map", function()
    it("openai gpt-5.2 maps minimal to low", function()
      local info = models_data.providers.openai.models["gpt-5.2"]
      assert.is_not_nil(info.thinking_effort_map)
      assert.are.equal("low", info.thinking_effort_map.minimal)
    end)

    it("openai gpt-5.2 maps max to xhigh", function()
      local info = models_data.providers.openai.models["gpt-5.2"]
      assert.are.equal("xhigh", info.thinking_effort_map.max)
    end)

    it("openai gpt-5 maps minimal to minimal (native support)", function()
      local info = models_data.providers.openai.models["gpt-5"]
      assert.are.equal("minimal", info.thinking_effort_map.minimal)
    end)

    it("openai gpt-5 maps max to high (no xhigh support)", function()
      local info = models_data.providers.openai.models["gpt-5"]
      assert.are.equal("high", info.thinking_effort_map.max)
    end)

    it("anthropic opus-4-6 maps max to max", function()
      local info = models_data.providers.anthropic.models["claude-opus-4-6"]
      assert.is_not_nil(info.thinking_effort_map)
      assert.are.equal("max", info.thinking_effort_map.max)
    end)

    it("anthropic sonnet-4-6 maps max to high (max is Opus-only)", function()
      local info = models_data.providers.anthropic.models["claude-sonnet-4-6"]
      assert.are.equal("high", info.thinking_effort_map.max)
    end)

    it("anthropic sonnet-4-6 maps minimal to low", function()
      local info = models_data.providers.anthropic.models["claude-sonnet-4-6"]
      assert.are.equal("low", info.thinking_effort_map.minimal)
    end)

    it("vertex gemini-3-flash-preview maps minimal to MINIMAL", function()
      local info = models_data.providers.vertex.models["gemini-3-flash-preview"]
      assert.are.equal("MINIMAL", info.thinking_effort_map.minimal)
    end)

    it("vertex gemini-3.1-pro-preview maps minimal to LOW", function()
      local info = models_data.providers.vertex.models["gemini-3.1-pro-preview"]
      assert.is_not_nil(info.thinking_effort_map)
      assert.are.equal("LOW", info.thinking_effort_map.minimal)
    end)

    it("vertex gemini-3.1-pro-preview maps medium to MEDIUM (3.1 Pro added MEDIUM)", function()
      local info = models_data.providers.vertex.models["gemini-3.1-pro-preview"]
      assert.is_not_nil(info.thinking_effort_map)
      assert.are.equal("MEDIUM", info.thinking_effort_map.medium)
    end)

    it("non-thinking models have no effort map", function()
      local info = models_data.providers.openai.models["gpt-4o"]
      assert.is_nil(info.thinking_effort_map)
    end)

    it("anthropic opus-4-5 maps max to high (no max support)", function()
      local info = models_data.providers.anthropic.models["claude-opus-4-5"]
      assert.is_not_nil(info.thinking_effort_map)
      assert.are.equal("high", info.thinking_effort_map.max)
      assert.are.equal("low", info.thinking_effort_map.minimal)
    end)

    it("budget-only anthropic models (sonnet-4-5, haiku-4-5) have no effort map", function()
      local info = models_data.providers.anthropic.models["claude-sonnet-4-5"]
      assert.is_nil(info.thinking_effort_map)
    end)

    it("budget-only vertex models (gemini-2.5) have no effort map", function()
      local info = models_data.providers.vertex.models["gemini-2.5-pro"]
      assert.is_nil(info.thinking_effort_map)
    end)
  end)

  describe("HIGH_COST_THRESHOLD", function()
    it("is exported as a number", function()
      assert.is_number(models_data.HIGH_COST_THRESHOLD)
    end)

    it("claude-opus-4-6 sits exactly at the boundary and does not exceed it", function()
      local pricing = models_data.providers.anthropic.models["claude-opus-4-6"].pricing
      local combined = pricing.input + pricing.output
      assert.are.equal(30, combined)
      assert.is_false(combined > models_data.HIGH_COST_THRESHOLD)
    end)

    it("expensive models exceed the threshold", function()
      local pricing = models_data.providers.openai.models["gpt-5.4-pro"].pricing
      local combined = pricing.input + pricing.output
      assert.is_true(combined > models_data.HIGH_COST_THRESHOLD)
    end)

  end)
end)
