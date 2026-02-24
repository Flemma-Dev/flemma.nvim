describe("flemma.core.config.manager.resolve_max_tokens", function()
  local config_manager

  before_each(function()
    package.loaded["flemma.core.config.manager"] = nil
    package.loaded["flemma.provider.registry"] = nil
    package.loaded["flemma.models"] = nil

    -- Ensure registry is initialized with built-in providers
    local registry = require("flemma.provider.registry")
    registry.setup()

    config_manager = require("flemma.core.config.manager")
  end)

  it("resolves percentage with known model", function()
    -- claude-sonnet-4-6 has max_output_tokens = 64000
    local params = { max_tokens = "50%" }
    config_manager.resolve_max_tokens("anthropic", "claude-sonnet-4-6", params)
    assert.equals(32000, params.max_tokens)
  end)

  it("resolves percentage with unknown model to fallback", function()
    local params = { max_tokens = "50%" }
    config_manager.resolve_max_tokens("anthropic", "custom-model", params)
    assert.equals(4000, params.max_tokens)
  end)

  it("clamps small percentage to minimum", function()
    -- 1% of 64000 = 640, below MIN_MAX_TOKENS (1024)
    local params = { max_tokens = "1%" }
    config_manager.resolve_max_tokens("anthropic", "claude-haiku-4-5", params)
    assert.equals(1024, params.max_tokens)
  end)

  it("resolves 100% to full max", function()
    -- claude-sonnet-4-6 has max_output_tokens = 64000
    local params = { max_tokens = "100%" }
    config_manager.resolve_max_tokens("anthropic", "claude-sonnet-4-6", params)
    assert.equals(64000, params.max_tokens)
  end)

  it("passes through integer within limits", function()
    local params = { max_tokens = 8000 }
    config_manager.resolve_max_tokens("anthropic", "claude-sonnet-4-6", params)
    assert.equals(8000, params.max_tokens)
  end)

  it("clamps integer over limit", function()
    -- claude-sonnet-4-6 has max_output_tokens = 64000
    local params = { max_tokens = 100000 }
    config_manager.resolve_max_tokens("anthropic", "claude-sonnet-4-6", params)
    assert.equals(64000, params.max_tokens)
  end)

  it("passes through integer with unknown model (no data to clamp)", function()
    local params = { max_tokens = 999999 }
    config_manager.resolve_max_tokens("anthropic", "custom-model", params)
    assert.equals(999999, params.max_tokens)
  end)

  it("falls back when model info has no max_output_tokens", function()
    -- Register a custom provider with a model that has pricing but no max_output_tokens
    local registry = require("flemma.provider.registry")
    registry.register("partial", {
      module = "flemma.provider.providers.openai",
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
    config_manager.resolve_max_tokens("partial", "partial-model", params)
    assert.equals(4000, params.max_tokens)
  end)

  it("falls back for invalid string format", function()
    local params = { max_tokens = "abc" }
    config_manager.resolve_max_tokens("anthropic", "claude-sonnet-4-6", params)
    assert.equals(4000, params.max_tokens)
  end)

  it("is a no-op for nil max_tokens", function()
    local params = {}
    config_manager.resolve_max_tokens("anthropic", "claude-sonnet-4-6", params)
    assert.is_nil(params.max_tokens)
  end)
end)
