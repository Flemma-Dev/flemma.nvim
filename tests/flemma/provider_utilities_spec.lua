local registry = require("flemma.provider.registry")
local modeline = require("flemma.utilities.modeline")
local str = require("flemma.utilities.string")

describe("provider utility functions", function()
  describe("provider.registry.extract_switch_arguments", function()
    it("detects provider and model from positional tokens", function()
      local parsed = modeline.parse_args({ "openai", "gpt-4o" }, 1)
      local info = registry.extract_switch_arguments(parsed)

      assert.are.equal("openai", info.provider)
      assert.are.equal("gpt-4o", info.model)
      assert.are.same({ "openai", "gpt-4o" }, info.positionals)
      assert.are.same({}, info.extra_positionals)
    end)

    it("prefers explicit provider/model assignments", function()
      local parsed = {
        provider = "vertex",
        model = "gemini-2.5",
        [1] = "ignored-provider",
        [2] = "ignored-model",
        max_tokens = 8192,
      }
      local info = registry.extract_switch_arguments(parsed)

      assert.are.equal("vertex", info.provider)
      assert.are.equal("gemini-2.5", info.model)
      assert.is_true(info.has_explicit_provider)
      assert.is_true(info.has_explicit_model)
      assert.are.same({ "ignored-provider", "ignored-model" }, info.positionals)
      assert.are.same({
        max_tokens = 8192,
      }, info.parameters)
    end)

    it("collects extra positional arguments beyond provider/model", function()
      local parsed = modeline.parse_args({ "openai", "gpt-4o", "unexpected" }, 1)
      local info = registry.extract_switch_arguments(parsed)

      assert.are.same({ "unexpected" }, info.extra_positionals)
    end)

    it("handles empty input gracefully", function()
      local info = registry.extract_switch_arguments(nil)

      assert.is_nil(info.provider)
      assert.is_nil(info.model)
      assert.are.same({}, info.parameters)
      assert.are.same({}, info.positionals)
      assert.are.same({}, info.extra_positionals)
    end)
  end)

  describe("flemma.utilities.string split_provider_model()", function()
    it("returns model and nil for a plain model string", function()
      local model, provider = str.split_provider_model("gpt-5.5")
      assert.are.equal("gpt-5.5", model)
      assert.is_nil(provider)
    end)

    it("splits on forward slash", function()
      local model, provider = str.split_provider_model("codex/gpt-5.5")
      assert.are.equal("gpt-5.5", model)
      assert.are.equal("codex", provider)
    end)

    it("splits on space", function()
      local model, provider = str.split_provider_model("codex gpt-5.5")
      assert.are.equal("gpt-5.5", model)
      assert.are.equal("codex", provider)
    end)

    it("splits on the first delimiter when both are present", function()
      local model, provider = str.split_provider_model("codex/gpt-5.5 extra")
      assert.are.equal("gpt-5.5 extra", model)
      assert.are.equal("codex", provider)
    end)

    it("treats leading slash as plain (empty left half)", function()
      local model, provider = str.split_provider_model("/gpt-5.5")
      assert.are.equal("/gpt-5.5", model)
      assert.is_nil(provider)
    end)

    it("treats trailing slash as plain (empty right half)", function()
      local model, provider = str.split_provider_model("codex/")
      assert.are.equal("codex/", model)
      assert.is_nil(provider)
    end)

    it("treats leading space as plain (empty left half)", function()
      local model, provider = str.split_provider_model(" gpt-5.5")
      assert.are.equal(" gpt-5.5", model)
      assert.is_nil(provider)
    end)

    it("handles hyphenated model names", function()
      local model, provider = str.split_provider_model("openai/gpt-5.5-pro-2026-04-23")
      assert.are.equal("gpt-5.5-pro-2026-04-23", model)
      assert.are.equal("openai", provider)
    end)
  end)

  describe("flemma.provider.registry extract_switch_arguments() slash syntax", function()
    it("splits codex/gpt-5.5 into provider and model", function()
      local parsed = { [1] = "codex/gpt-5.5" }
      local info = registry.extract_switch_arguments(parsed)
      assert.are.equal("codex", info.provider)
      assert.are.equal("gpt-5.5", info.model)
    end)

    it("splits codex/gpt-5.5 with parameters", function()
      local parsed = { [1] = "codex/gpt-5.5", temperature = 0.3 }
      local info = registry.extract_switch_arguments(parsed)
      assert.are.equal("codex", info.provider)
      assert.are.equal("gpt-5.5", info.model)
      assert.are.equal(0.3, info.parameters.temperature)
    end)

    it("preserves existing space-separated behavior", function()
      local parsed = { [1] = "openai", [2] = "gpt-5.5" }
      local info = registry.extract_switch_arguments(parsed)
      assert.are.equal("openai", info.provider)
      assert.are.equal("gpt-5.5", info.model)
    end)

    it("does not split plain provider name", function()
      local parsed = { [1] = "openai" }
      local info = registry.extract_switch_arguments(parsed)
      assert.are.equal("openai", info.provider)
      assert.is_nil(info.model)
    end)

    it("moves positionals[2] to extra when slash sets model", function()
      local parsed = { [1] = "codex/gpt-5.5", [2] = "extra-arg" }
      local info = registry.extract_switch_arguments(parsed)
      assert.are.equal("codex", info.provider)
      assert.are.equal("gpt-5.5", info.model)
      assert.are.equal(1, #info.extra_positionals)
      assert.are.equal("extra-arg", info.extra_positionals[1])
    end)
  end)

  describe("provider.get_trailing_keys", function()
    local base

    before_each(function()
      package.loaded["flemma.provider.base"] = nil
      package.loaded["flemma.provider.adapters.anthropic"] = nil
      package.loaded["flemma.provider.adapters.openai"] = nil
      package.loaded["flemma.provider.adapters.vertex"] = nil
      base = require("flemma.provider.base")
    end)

    describe("base provider", function()
      it("has a get_trailing_keys method", function()
        assert.is_function(base.get_trailing_keys)
      end)

      it("returns an empty table by default", function()
        local provider = setmetatable({
          parameters = {},
          state = {},
        }, { __index = base })
        local keys = provider:get_trailing_keys()
        assert.are.same({}, keys)
      end)
    end)

    describe("Anthropic provider", function()
      it("returns system, tools, messages as trailing keys", function()
        local anthropic = require("flemma.provider.adapters.anthropic")
        local provider = anthropic.new({ model = "claude-sonnet-4-20250514" })
        local keys = provider:get_trailing_keys()
        assert.are.same({ "system", "tools", "messages" }, keys)
      end)
    end)

    describe("OpenAI provider", function()
      it("returns tools, input as trailing keys", function()
        local openai = require("flemma.provider.adapters.openai")
        local provider = openai.new({ model = "gpt-4o" })
        local keys = provider:get_trailing_keys()
        assert.are.same({ "tools", "input" }, keys)
      end)
    end)

    describe("Vertex provider", function()
      it("returns tools, contents as trailing keys", function()
        local vertex = require("flemma.provider.adapters.vertex")
        local provider = vertex.new({ model = "gemini-2.5-pro" })
        local keys = provider:get_trailing_keys()
        assert.are.same({ "tools", "contents" }, keys)
      end)
    end)
  end)
end)

describe("flemma.provider.registry decompose_model()", function()
  it("decomposes provider, model, and matrix parameters", function()
    local d = registry.decompose_model("vertex/gemini-3.1-pro-preview;project_id=stan;region=eu")
    assert.equals("vertex", d.provider)
    assert.equals("gemini-3.1-pro-preview", d.model)
    -- Individual lookups, not table equality: parameters is a plain table and
    -- key iteration order is irrelevant to this assertion.
    assert.equals("stan", d.parameters.project_id)
    assert.equals("eu", d.parameters.region)
  end)

  it("passes plain model names through", function()
    local d = registry.decompose_model("claude-haiku-4-5")
    assert.is_nil(d.provider)
    assert.equals("claude-haiku-4-5", d.model)
    assert.are.same({}, d.parameters)
  end)

  it("handles matrix parameters without a provider prefix", function()
    local d = registry.decompose_model("gemini-3.1-pro-preview;project_id=stan")
    assert.is_nil(d.provider)
    assert.equals("gemini-3.1-pro-preview", d.model)
    assert.are.same({ project_id = "stan" }, d.parameters)
  end)
end)

describe("flemma.provider.registry model_transform()", function()
  local function fake_ctx(reads)
    local ctx = { ops = {} }
    function ctx:get(path)
      return reads[path]
    end
    function ctx:set(path, value)
      table.insert(self.ops, { op = "$set", path = path, value = value })
    end
    return ctx
  end

  it("emits model, provider, and provider-scoped parameters", function()
    local ctx = fake_ctx({})
    registry.model_transform("vertex/gemini-3;project_id=stan", ctx)
    assert.are.same({
      { op = "$set", path = "model", value = "gemini-3" },
      { op = "$set", path = "provider", value = "vertex" },
      { op = "$set", path = "parameters.vertex.project_id", value = "stan" },
    }, ctx.ops)
  end)

  it("scopes prefixless parameters under the ambient provider", function()
    local ctx = fake_ctx({ provider = "anthropic" })
    registry.model_transform("claude-x;timeout=99", ctx)
    assert.are.same({
      { op = "$set", path = "model", value = "claude-x" },
      { op = "$set", path = "parameters.anthropic.timeout", value = 99 },
    }, ctx.ops)
  end)

  it("does not emit a provider write for prefixless models", function()
    local ctx = fake_ctx({ provider = "anthropic" })
    registry.model_transform("claude-x", ctx)
    assert.are.same({ { op = "$set", path = "model", value = "claude-x" } }, ctx.ops)
  end)

  it("drops parameters when no provider is resolvable", function()
    local ctx = fake_ctx({})
    registry.model_transform("claude-x;p=1", ctx)
    assert.are.same({ { op = "$set", path = "model", value = "claude-x" } }, ctx.ops)
  end)

  it("passes non-string values through as a plain model set", function()
    local ctx = fake_ctx({})
    registry.model_transform(true, ctx)
    assert.are.same({ { op = "$set", path = "model", value = true } }, ctx.ops)
  end)
end)
