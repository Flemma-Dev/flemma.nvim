local registry = require("flemma.provider.registry")
local modeline = require("flemma.modeline")

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
