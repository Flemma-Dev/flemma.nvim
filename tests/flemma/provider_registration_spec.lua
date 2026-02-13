local registry = require("flemma.provider.registry")
local config_manager = require("flemma.core.config.manager")

describe("provider registration", function()
  -- Save original state and restore after each test
  local original_defaults, original_models

  before_each(function()
    -- Save state
    original_defaults = vim.deepcopy(registry.defaults)
    original_models = vim.deepcopy(registry.models)
  end)

  after_each(function()
    -- Restore built-in providers
    registry.clear()
    registry.setup()
    registry.defaults = original_defaults
    registry.models = original_models

    -- Clean up any custom provider models_data entries
    local models_data = require("flemma.models")
    models_data.providers["custom"] = nil
    models_data.providers["minimal"] = nil
  end)

  describe("register()", function()
    it("adds a provider recognized by has(), get(), supported_providers()", function()
      registry.register("custom", {
        module = "flemma.provider.providers.openai",
        capabilities = {
          supports_reasoning = false,
          supports_thinking_budget = false,
          outputs_thinking = false,
        },
        display_name = "Custom",
      })

      assert.is_true(registry.has("custom"))
      assert.are.equal("flemma.provider.providers.openai", registry.get("custom"))
      assert.are.equal("Custom", registry.get_display_name("custom"))

      local supported = registry.supported_providers()
      local found = false
      for _, name in ipairs(supported) do
        if name == "custom" then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)

    it("populates defaults and models when models are provided", function()
      registry.register("custom", {
        module = "flemma.provider.providers.openai",
        capabilities = {
          supports_reasoning = false,
          supports_thinking_budget = false,
          outputs_thinking = false,
        },
        display_name = "Custom",
        default_model = "my-model",
        models = {
          ["my-model"] = { pricing = { input = 1.0, output = 2.0 } },
          ["my-model-2"] = { pricing = { input = 0.5, output = 1.0 } },
        },
      })

      assert.are.equal("my-model", registry.defaults["custom"])
      assert.is_not_nil(registry.models["custom"])
      assert.is_true(registry.is_provider_model("my-model", "custom"))
      assert.is_true(registry.is_provider_model("my-model-2", "custom"))
      assert.is_false(registry.is_provider_model("unknown-model", "custom"))
    end)

    it("stores cache multipliers in models_data", function()
      registry.register("custom", {
        module = "flemma.provider.providers.openai",
        capabilities = {
          supports_reasoning = false,
          supports_thinking_budget = false,
          outputs_thinking = false,
        },
        display_name = "Custom",
        default_model = "my-model",
        models = { ["my-model"] = { pricing = { input = 0, output = 0 } } },
        cache_read_multiplier = 0.25,
        cache_write_multipliers = { short = 1.5 },
      })

      local models_data = require("flemma.models")
      assert.are.equal(0.25, models_data.providers["custom"].cache_read_multiplier)
      assert.are.same({ short = 1.5 }, models_data.providers["custom"].cache_write_multipliers)
    end)
  end)

  describe("is_provider_model() without models", function()
    it("accepts any model string for a registered provider with no model list", function()
      registry.register("minimal", {
        module = "flemma.provider.providers.openai",
        capabilities = {
          supports_reasoning = false,
          supports_thinking_budget = false,
          outputs_thinking = false,
        },
        display_name = "Minimal",
      })

      assert.is_true(registry.is_provider_model("anything-goes", "minimal"))
      assert.is_true(registry.is_provider_model("any-model-name", "minimal"))
    end)

    it("returns false for nil model_name even with no model list", function()
      registry.register("minimal", {
        module = "flemma.provider.providers.openai",
        capabilities = {
          supports_reasoning = false,
          supports_thinking_budget = false,
          outputs_thinking = false,
        },
        display_name = "Minimal",
      })

      assert.is_false(registry.is_provider_model(nil, "minimal"))
    end)
  end)

  describe("get_model()", function()
    it("returns nil for unregistered providers instead of anthropic fallback", function()
      assert.is_nil(registry.get_model("nonexistent"))
    end)

    it("returns the default for a registered built-in provider", function()
      assert.are.equal("claude-sonnet-4-5", registry.get_model("anthropic"))
    end)
  end)

  describe("get_default_parameters()", function()
    it("returns registered default parameters", function()
      local defaults = registry.get_default_parameters("anthropic")
      assert.is_not_nil(defaults)
      assert.are.equal("short", defaults.cache_retention)
    end)

    it("returns registered default parameters for openai", function()
      local defaults = registry.get_default_parameters("openai")
      assert.is_not_nil(defaults)
      assert.are.equal("short", defaults.cache_retention)
    end)

    it("returns custom provider defaults", function()
      registry.register("custom", {
        module = "flemma.provider.providers.openai",
        capabilities = {
          supports_reasoning = false,
          supports_thinking_budget = false,
          outputs_thinking = false,
        },
        display_name = "Custom",
        default_parameters = { api_base = "http://localhost:11434" },
      })

      local defaults = registry.get_default_parameters("custom")
      assert.is_not_nil(defaults)
      assert.are.equal("http://localhost:11434", defaults.api_base)
    end)
  end)

  describe("get_capabilities()", function()
    it("returns min_thinking_budget for anthropic", function()
      local caps = registry.get_capabilities("anthropic")
      assert.is_not_nil(caps)
      assert.are.equal(1024, caps.min_thinking_budget)
    end)

    it("returns min_thinking_budget for vertex", function()
      local caps = registry.get_capabilities("vertex")
      assert.is_not_nil(caps)
      assert.are.equal(1, caps.min_thinking_budget)
    end)

    it("returns nil min_thinking_budget for openai", function()
      local caps = registry.get_capabilities("openai")
      assert.is_not_nil(caps)
      assert.is_nil(caps.min_thinking_budget)
    end)
  end)

  describe("setup()", function()
    it("does not overwrite providers registered before it", function()
      registry.clear()

      -- Register custom provider before setup
      registry.register("anthropic", {
        module = "my.custom.anthropic",
        capabilities = {
          supports_reasoning = false,
          supports_thinking_budget = false,
          outputs_thinking = false,
        },
        display_name = "My Anthropic",
      })

      -- setup() should skip anthropic since it's already registered
      registry.setup()

      assert.are.equal("my.custom.anthropic", registry.get("anthropic"))
      assert.are.equal("My Anthropic", registry.get_display_name("anthropic"))
    end)
  end)

  describe("clear()", function()
    it("resets all providers", function()
      registry.clear()

      assert.is_false(registry.has("anthropic"))
      assert.is_false(registry.has("openai"))
      assert.is_false(registry.has("vertex"))
      assert.are.same({}, registry.supported_providers())
      assert.are.same({}, registry.defaults)
      assert.are.same({}, registry.models)
    end)
  end)
end)

describe("merge_parameters with registered defaults", function()
  it("uses registered defaults as fallback", function()
    local merged = config_manager.merge_parameters({}, "anthropic")
    assert.are.equal("short", merged.cache_retention)
  end)

  it("general base params override registered defaults", function()
    local merged = config_manager.merge_parameters({ max_tokens = 8000 }, "anthropic")
    assert.are.equal(8000, merged.max_tokens)
    assert.are.equal("short", merged.cache_retention)
  end)

  it("provider-specific overrides take highest priority", function()
    local merged =
      config_manager.merge_parameters({ anthropic = { cache_retention = "long", thinking_budget = 4096 } }, "anthropic")
    assert.are.equal("long", merged.cache_retention)
    assert.are.equal(4096, merged.thinking_budget)
  end)

  it("explicit provider_overrides argument takes highest priority", function()
    local merged = config_manager.merge_parameters(
      { anthropic = { cache_retention = "none" } },
      "anthropic",
      { cache_retention = "long" }
    )
    assert.are.equal("long", merged.cache_retention)
  end)

  it("includes openai registered defaults when no user params given", function()
    local merged = config_manager.merge_parameters({}, "openai")
    -- OpenAI now has cache_retention = "short" as a registered default
    assert.are.equal("short", merged.cache_retention)
  end)
end)
