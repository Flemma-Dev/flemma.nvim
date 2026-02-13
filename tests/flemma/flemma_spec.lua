local state = require("flemma.state")

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

    local config = state.get_config()

    -- Check that user-provided values are set
    assert.are.equal("openai", config.provider)
    assert.are.equal("#ff0000", config.highlights.user)

    -- Check that default values are preserved
    assert.are.equal("Special", config.highlights.system)
    assert.are.equal(true, config.pricing.enabled)
  end)

  it("preserves nested defaults when user provides partial nested config", function()
    local flemma = require("flemma")
    flemma.setup({
      provider = "openai",
      model = "gpt-5-mini",
      editing = {
        auto_write = true,
      },
    })

    local config = state.get_config()

    -- Check that user-provided nested value is set
    assert.are.equal(true, config.editing.auto_write)

    -- Check that other nested defaults are preserved
    assert.are.equal(true, config.editing.disable_textwidth)
    assert.are.equal(true, config.editing.manage_updatetime)
  end)
end)
