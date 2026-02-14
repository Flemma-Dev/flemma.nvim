describe("base.resolve_thinking", function()
  local base

  before_each(function()
    package.loaded["flemma.provider.base"] = nil
    base = require("flemma.provider.base")
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
      local result = base.resolve_thinking({ thinking_budget = 4096 }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(4096, result.budget)
      assert.are.equal("medium", result.level)
    end)

    it("thinking_budget takes priority even when thinking is also set", function()
      local result = base.resolve_thinking({ thinking_budget = 4096, thinking = "high" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(4096, result.budget)
      assert.are.equal("medium", result.level)
    end)

    it("thinking_budget=0 disables", function()
      local result = base.resolve_thinking({ thinking_budget = 0 }, caps)
      assert.is_false(result.enabled)
      assert.is_nil(result.level)
    end)

    it("thinking='high' maps to 32768", function()
      local result = base.resolve_thinking({ thinking = "high" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(32768, result.budget)
      assert.are.equal("high", result.level)
    end)

    it("thinking='medium' maps to 8192", function()
      local result = base.resolve_thinking({ thinking = "medium" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(8192, result.budget)
      assert.are.equal("medium", result.level)
    end)

    it("thinking='low' maps to 1024", function()
      local result = base.resolve_thinking({ thinking = "low" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(1024, result.budget)
      assert.are.equal("low", result.level)
    end)

    it("thinking=500 clamps to min 1024", function()
      local result = base.resolve_thinking({ thinking = 500 }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(1024, result.budget)
      assert.are.equal("low", result.level)
    end)

    it("thinking=4096 (numeric) uses exact value", function()
      local result = base.resolve_thinking({ thinking = 4096 }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(4096, result.budget)
      assert.are.equal("medium", result.level)
    end)

    it("thinking=false disables", function()
      local result = base.resolve_thinking({ thinking = false }, caps)
      assert.is_false(result.enabled)
      assert.is_nil(result.level)
    end)

    it("thinking=0 disables", function()
      local result = base.resolve_thinking({ thinking = 0 }, caps)
      assert.is_false(result.enabled)
      assert.is_nil(result.level)
    end)

    it("nil thinking means disabled", function()
      local result = base.resolve_thinking({}, caps)
      assert.is_false(result.enabled)
      assert.is_nil(result.level)
    end)

    it("floors float budget to integer", function()
      local result = base.resolve_thinking({ thinking = 4096.7 }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(4096, result.budget)
      assert.are.equal("medium", result.level)
    end)

    it("high thinking_budget maps to high level", function()
      local result = base.resolve_thinking({ thinking_budget = 32768 }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(32768, result.budget)
      assert.are.equal("high", result.level)
    end)

    it("low thinking_budget maps to low level", function()
      local result = base.resolve_thinking({ thinking_budget = 1024 }, caps)
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

    it("thinking='low' maps to 1024 (no clamping needed)", function()
      local result = base.resolve_thinking({ thinking = "low" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(1024, result.budget)
      assert.are.equal("low", result.level)
    end)

    it("thinking=1 uses exact value (min is 1)", function()
      local result = base.resolve_thinking({ thinking = 1 }, caps)
      assert.is_true(result.enabled)
      assert.are.equal(1, result.budget)
      assert.are.equal("low", result.level)
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
      local result = base.resolve_thinking({ reasoning = "high" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal("high", result.effort)
      assert.are.equal("high", result.level)
    end)

    it("reasoning takes priority even when thinking is also set", function()
      local result = base.resolve_thinking({ reasoning = "high", thinking = "low" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal("high", result.effort)
      assert.are.equal("high", result.level)
    end)

    it("thinking='medium' falls through when no reasoning", function()
      local result = base.resolve_thinking({ thinking = "medium" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal("medium", result.effort)
      assert.are.equal("medium", result.level)
    end)

    it("thinking=4096 maps to medium effort", function()
      local result = base.resolve_thinking({ thinking = 4096 }, caps)
      assert.is_true(result.enabled)
      assert.are.equal("medium", result.effort)
      assert.are.equal("medium", result.level)
    end)

    it("thinking=1024 maps to low effort", function()
      local result = base.resolve_thinking({ thinking = 1024 }, caps)
      assert.is_true(result.enabled)
      assert.are.equal("low", result.effort)
      assert.are.equal("low", result.level)
    end)

    it("thinking=32768 maps to high effort", function()
      local result = base.resolve_thinking({ thinking = 32768 }, caps)
      assert.is_true(result.enabled)
      assert.are.equal("high", result.effort)
      assert.are.equal("high", result.level)
    end)

    it("thinking=false disables", function()
      local result = base.resolve_thinking({ thinking = false }, caps)
      assert.is_false(result.enabled)
      assert.is_nil(result.level)
    end)

    it("nil thinking means disabled", function()
      local result = base.resolve_thinking({}, caps)
      assert.is_false(result.enabled)
      assert.is_nil(result.level)
    end)

    it("empty reasoning string falls through to thinking", function()
      local result = base.resolve_thinking({ reasoning = "", thinking = "high" }, caps)
      assert.is_true(result.enabled)
      assert.are.equal("high", result.effort)
      assert.are.equal("high", result.level)
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
      local result = base.resolve_thinking({ thinking = "high" }, caps)
      assert.is_false(result.enabled)
      assert.is_nil(result.level)
    end)

    it("returns disabled even with thinking_budget", function()
      local result = base.resolve_thinking({ thinking_budget = 4096 }, caps)
      assert.is_false(result.enabled)
      assert.is_nil(result.level)
    end)
  end)
end)
