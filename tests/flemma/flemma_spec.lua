describe("flemma.setup", function()
  it("can be required without errors", function()
    local ok, flemma = pcall(require, "flemma")
    assert.is_true(ok, "failed to require flemma")
    assert.is_table(flemma, '"flemma" is not a table')
  end)

  it("merges user config with defaults", function()
    local flemma = require("flemma")
    flemma.setup({
      provider = "openai",
      highlights = {
        user = "#ff0000",
      },
    })

    local config = flemma._get_config()

    -- Check that user-provided values are set
    assert.are.equal("openai", config.provider)
    assert.are.equal("#ff0000", config.highlights.user)

    -- Check that default values are preserved
    assert.are.equal("Special", config.highlights.system)
    assert.are.equal(true, config.pricing.enabled)
  end)
end)
