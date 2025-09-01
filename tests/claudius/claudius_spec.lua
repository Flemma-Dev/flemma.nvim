describe("claudius.setup", function()
  it("can be required without errors", function()
    local ok, claudius = pcall(require, "claudius")
    assert.is_true(ok, "failed to require claudius")
    assert.is_table(claudius, '"claudius" is not a table')
  end)

  it("merges user config with defaults", function()
    local claudius = require("claudius")
    claudius.setup({
      provider = "openai",
      highlights = {
        user = "#ff0000",
      },
    })

    local config = claudius._get_config()

    -- Check that user-provided values are set
    assert.are.equal("openai", config.provider)
    assert.are.equal("#ff0000", config.highlights.user)

    -- Check that default values are preserved
    assert.are.equal("Special", config.highlights.system)
    assert.are.equal(true, config.pricing.enabled)
  end)
end)
