local config_facade = require("flemma.config")
local notify = require("flemma.notify")

describe("flemma.setup with preset model", function()
  local captured = {}

  before_each(function()
    captured = {}
    notify._set_impl(function(notification)
      table.insert(captured, notification)
      return notification
    end)
  end)

  after_each(function()
    notify._reset_impl()
  end)

  it("resolves preset as default provider and model", function()
    local flemma = require("flemma")
    flemma.setup({
      model = "$test",
      presets = {
        ["$test"] = { provider = "openai", model = "gpt-4o" },
      },
    })

    local config = config_facade.materialize()
    assert.are.equal("openai", config.provider)
    assert.are.equal("gpt-4o", config.model)
  end)

  it("preset parameters merge with config parameters", function()
    local flemma = require("flemma")
    local normalize = require("flemma.provider.normalize")
    flemma.setup({
      model = "$test",
      parameters = {
        vertex = { project_id = "my-project" },
      },
      presets = {
        ["$test"] = { provider = "vertex", model = "gemini-2.5-pro", location = "europe-west1" },
      },
    })

    local config = config_facade.materialize()
    assert.are.equal("vertex", config.provider)
    -- Verify merged flat params (general + provider-specific)
    local flat = normalize.merge_parameters(config.provider, config)
    assert.are.equal("europe-west1", flat.location)
    assert.are.equal("my-project", flat.project_id)
  end)

  it("matching explicit provider with preset works", function()
    local flemma = require("flemma")
    flemma.setup({
      provider = "openai",
      model = "$test",
      presets = {
        ["$test"] = { provider = "openai", model = "gpt-4o" },
      },
    })

    local config = config_facade.materialize()
    assert.are.equal("openai", config.provider)
    assert.are.equal("gpt-4o", config.model)
  end)

  it("conflicting explicit provider emits error", function()
    local flemma = require("flemma")
    flemma.setup({
      provider = "anthropic",
      model = "$test",
      presets = {
        ["$test"] = { provider = "openai", model = "gpt-4o" },
      },
    })
    -- Flush vim.schedule callbacks from setup()
    vim.wait(10, function()
      return false
    end)

    -- Should have an error notification about the conflict
    local found_error = false
    for _, n in ipairs(captured) do
      if n.message and n.message:match("conflicts") then
        found_error = true
      end
    end
    assert.is_true(found_error, "Expected a conflict notification")
  end)

  it("unknown preset emits error", function()
    local flemma = require("flemma")
    flemma.setup({
      model = "$nonexistent",
    })
    -- Flush vim.schedule callbacks from setup()
    vim.wait(10, function()
      return false
    end)

    -- Should have an error notification
    local found_error = false
    for _, n in ipairs(captured) do
      if n.message and n.message:match("not found") then
        found_error = true
      end
    end
    assert.is_true(found_error, "Expected a not-found notification")
  end)
end)

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

    local config = config_facade.materialize()

    -- Check that user-provided values are set
    assert.are.equal("openai", config.provider)
    assert.are.equal("#ff0000", config.highlights.user)

    -- Check that default values are preserved
    assert.are.equal("Special", config.highlights.system)
    assert.are.equal(true, config.ui.pricing.enabled)
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

    local config = config_facade.materialize()

    -- Check that user-provided nested value is set
    assert.are.equal(true, config.editing.auto_write)

    -- Check that other nested defaults are preserved
    assert.are.equal(true, config.editing.disable_textwidth)
    assert.are.equal(true, config.editing.manage_updatetime)
  end)
end)
