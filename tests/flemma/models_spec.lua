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
end)
