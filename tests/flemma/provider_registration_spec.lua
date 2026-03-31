local registry = require("flemma.provider.registry")
local normalize = require("flemma.provider.normalize")

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
      assert.are.equal("claude-sonnet-4-6", registry.get_model("anthropic"))
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

  describe("unregister()", function()
    it("removes a provider and returns true", function()
      registry.register("custom", {
        module = "flemma.provider.providers.openai",
        capabilities = {
          supports_reasoning = false,
          supports_thinking_budget = false,
          outputs_thinking = false,
        },
        display_name = "Custom",
      })

      assert.is_true(registry.unregister("custom"))
      assert.is_false(registry.has("custom"))
      assert.is_nil(registry.get("custom"))
    end)

    it("returns false for unknown provider", function()
      assert.is_false(registry.unregister("nonexistent"))
    end)

    it("cleans up defaults and models", function()
      registry.register("custom", {
        module = "flemma.provider.providers.openai",
        capabilities = {
          supports_reasoning = false,
          supports_thinking_budget = false,
          outputs_thinking = false,
        },
        display_name = "Custom",
        default_model = "my-model",
        models = { ["my-model"] = { pricing = { input = 1.0, output = 2.0 } } },
      })

      assert.is_not_nil(registry.defaults["custom"])
      registry.unregister("custom")
      assert.is_nil(registry.defaults["custom"])
      assert.is_nil(registry.models["custom"])
    end)
  end)

  describe("get_all()", function()
    it("returns a copy of all provider entries", function()
      local all = registry.get_all()
      assert.is_not_nil(all["anthropic"])
      assert.is_not_nil(all["openai"])
      assert.is_not_nil(all["vertex"])
      assert.are.equal("flemma.provider.providers.anthropic", all["anthropic"].module)
    end)

    it("returns a deep copy (mutations do not affect registry)", function()
      local all = registry.get_all()
      all["anthropic"] = nil
      assert.is_true(registry.has("anthropic"))
    end)
  end)

  describe("count()", function()
    it("returns the number of registered providers", function()
      assert.are.equal(4, registry.count())
    end)

    it("returns 0 after clear", function()
      registry.clear()
      assert.are.equal(0, registry.count())
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

describe("flatten_parameters with facade", function()
  local config_facade = require("flemma.config")
  local schema_definition = require("flemma.config.schema")

  before_each(function()
    -- Reset facade and registries for clean state
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

  it("schema defaults provide base parameter values", function()
    local config = config_facade.materialize()
    local flat = normalize.flatten_parameters("anthropic", config)
    -- Schema defaults should be present
    assert.are.equal("50%", flat.max_tokens)
    assert.is_nil(flat.temperature)
    assert.are.equal(600, flat.timeout)
    assert.are.equal("short", flat.cache_retention)
  end)

  it("general setup params override defaults", function()
    config_facade.apply(config_facade.LAYERS.SETUP, {
      parameters = { max_tokens = 8000, cache_retention = "long" },
    })
    local config = config_facade.materialize()
    local flat = normalize.flatten_parameters("anthropic", config)
    assert.are.equal(8000, flat.max_tokens)
    assert.are.equal("long", flat.cache_retention)
  end)

  it("provider-specific setup params appear in flattened output", function()
    config_facade.apply(config_facade.LAYERS.SETUP, {
      parameters = { anthropic = { thinking_budget = 4096 } },
    })
    local config = config_facade.materialize()
    local flat = normalize.flatten_parameters("anthropic", config)
    assert.are.equal(4096, flat.thinking_budget)
  end)

  it("provider-specific values override general values with same key", function()
    -- The openai schema has reasoning_summary defaulting to "auto"
    local config = config_facade.materialize()
    local flat = normalize.flatten_parameters("openai", config)
    assert.are.equal("auto", flat.reasoning_summary)
  end)

  it("cache_retention flows as general parameter to any provider", function()
    config_facade.apply(config_facade.LAYERS.SETUP, {
      parameters = { cache_retention = "long" },
    })
    local config = config_facade.materialize()
    local flat = normalize.flatten_parameters("openai", config)
    assert.are.equal("long", flat.cache_retention)
  end)

  it("runtime layer overrides setup layer", function()
    config_facade.apply(config_facade.LAYERS.SETUP, {
      parameters = { cache_retention = "short" },
    })
    config_facade.apply(config_facade.LAYERS.RUNTIME, {
      parameters = { cache_retention = "long" },
    })
    local config = config_facade.materialize()
    local flat = normalize.flatten_parameters("anthropic", config)
    assert.are.equal("long", flat.cache_retention)
  end)

  it("vertex provider-specific params from setup survive runtime switch", function()
    -- Simulates: user config has vertex.project_id, then :Flemma switch vertex location=europe-west1
    config_facade.apply(config_facade.LAYERS.SETUP, {
      parameters = { vertex = { project_id = "my-project", location = "us-central1" } },
    })
    -- Runtime overrides just location
    config_facade.apply(config_facade.LAYERS.RUNTIME, {
      parameters = { vertex = { location = "europe-west1" } },
    })
    local config = config_facade.materialize()
    local flat = normalize.flatten_parameters("vertex", config)
    assert.are.equal("europe-west1", flat.location)
    assert.are.equal("my-project", flat.project_id)
  end)

  it("runtime provider-specific overrides win over setup on conflict", function()
    config_facade.apply(config_facade.LAYERS.SETUP, {
      parameters = { vertex = { project_id = "old-project", location = "us-central1" } },
    })
    config_facade.apply(config_facade.LAYERS.RUNTIME, {
      parameters = { vertex = { project_id = "new-project" } },
    })
    local config = config_facade.materialize()
    local flat = normalize.flatten_parameters("vertex", config)
    assert.are.equal("new-project", flat.project_id)
    assert.are.equal("us-central1", flat.location)
  end)

  it("model is included from top-level config", function()
    config_facade.apply(config_facade.LAYERS.SETUP, { model = "claude-sonnet-4-5" })
    local config = config_facade.materialize()
    local flat = normalize.flatten_parameters("anthropic", config)
    assert.are.equal("claude-sonnet-4-5", flat.model)
  end)
end)

describe("resolve_preset", function()
  local config_facade = require("flemma.config")
  local schema_definition = require("flemma.config.schema")

  before_each(function()
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.provider.registry"] = nil
    package.loaded["flemma.provider.normalize"] = nil
    package.loaded["flemma.presets"] = nil
    config_facade = require("flemma.config")
    registry = require("flemma.provider.registry")
    normalize = require("flemma.provider.normalize")

    config_facade.init(schema_definition)
    registry.setup()
  end)

  it("returns config unchanged when model is not a preset reference", function()
    config_facade.apply(config_facade.LAYERS.SETUP, { model = "claude-sonnet-4-5" })
    local config = config_facade.materialize()
    local resolved = normalize.resolve_preset(config)
    assert.equals("claude-sonnet-4-5", resolved.model)
    assert.equals("anthropic", resolved.provider)
  end)

  it("returns config unchanged when model is nil", function()
    local config = config_facade.materialize()
    local resolved = normalize.resolve_preset(config)
    assert.is_nil(resolved.model)
  end)

  it("resolves preset reference to concrete provider and model", function()
    local presets_mod = require("flemma.presets")
    presets_mod.setup({
      ["$haiku"] = { provider = "anthropic", model = "claude-haiku-4-5-20250514" },
    })
    config_facade.apply(config_facade.LAYERS.SETUP, { model = "$haiku" })
    local config = config_facade.materialize()
    local resolved = normalize.resolve_preset(config)
    assert.equals("anthropic", resolved.provider)
    assert.equals("claude-haiku-4-5-20250514", resolved.model)
  end)

  it("merges preset parameters into config", function()
    local presets_mod = require("flemma.presets")
    presets_mod.setup({
      ["$fast"] = { provider = "anthropic", model = "claude-haiku-4-5-20250514", thinking = "low" },
    })
    config_facade.apply(config_facade.LAYERS.SETUP, { model = "$fast" })
    local config = config_facade.materialize()
    local resolved = normalize.resolve_preset(config)
    assert.equals("claude-haiku-4-5-20250514", resolved.model)
    assert.equals("low", resolved.parameters.thinking)
  end)

  it("does not mutate the original config table", function()
    local presets_mod = require("flemma.presets")
    presets_mod.setup({
      ["$haiku"] = { provider = "anthropic", model = "claude-haiku-4-5-20250514" },
    })
    config_facade.apply(config_facade.LAYERS.SETUP, { model = "$haiku" })
    local config = config_facade.materialize()
    normalize.resolve_preset(config)
    assert.equals("$haiku", config.model)
  end)

  it("returns config unchanged when preset is not found", function()
    config_facade.apply(config_facade.LAYERS.SETUP, { model = "$nonexistent" })
    local config = config_facade.materialize()
    local resolved = normalize.resolve_preset(config)
    assert.equals("$nonexistent", resolved.model)
  end)
end)
