local registry = require("flemma.provider.registry")

describe("flemma.provider.registry split_provider_model()", function()
  it("returns model and nil for a plain model string", function()
    local model, provider = registry.split_provider_model("gpt-5.5")
    assert.are.equal("gpt-5.5", model)
    assert.is_nil(provider)
  end)

  it("splits on forward slash", function()
    local model, provider = registry.split_provider_model("codex/gpt-5.5")
    assert.are.equal("gpt-5.5", model)
    assert.are.equal("codex", provider)
  end)

  it("splits on space", function()
    local model, provider = registry.split_provider_model("codex gpt-5.5")
    assert.are.equal("gpt-5.5", model)
    assert.are.equal("codex", provider)
  end)

  it("splits on the first delimiter when both are present", function()
    local model, provider = registry.split_provider_model("codex/gpt-5.5 extra")
    assert.are.equal("gpt-5.5 extra", model)
    assert.are.equal("codex", provider)
  end)

  it("treats leading slash as plain (empty left half)", function()
    local model, provider = registry.split_provider_model("/gpt-5.5")
    assert.are.equal("/gpt-5.5", model)
    assert.is_nil(provider)
  end)

  it("treats trailing slash as plain (empty right half)", function()
    local model, provider = registry.split_provider_model("codex/")
    assert.are.equal("codex/", model)
    assert.is_nil(provider)
  end)

  it("treats leading space as plain (empty left half)", function()
    local model, provider = registry.split_provider_model(" gpt-5.5")
    assert.are.equal(" gpt-5.5", model)
    assert.is_nil(provider)
  end)

  it("handles hyphenated model names", function()
    local model, provider = registry.split_provider_model("openai/gpt-5.5-pro-2026-04-23")
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
