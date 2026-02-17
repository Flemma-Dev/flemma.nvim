local state = require("flemma.state")

describe("flemma.setup with preset model", function()
  local notifications = {}
  local original_notify

  before_each(function()
    notifications = {}
    original_notify = vim.notify
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.notify = original_notify
    state.set_provider(nil)
  end)

  it("resolves preset as default provider and model", function()
    local flemma = require("flemma")
    flemma.setup({
      model = "$test",
      presets = {
        ["$test"] = { provider = "openai", model = "gpt-4o" },
      },
    })

    local config = state.get_config()
    assert.are.equal("openai", config.provider)
    assert.are.equal("gpt-4o", config.model)
  end)

  it("preset parameters merge with config parameters", function()
    local flemma = require("flemma")
    flemma.setup({
      model = "$test",
      parameters = {
        vertex = { project_id = "my-project" },
      },
      presets = {
        ["$test"] = { provider = "vertex", model = "gemini-2.5-pro", location = "europe-west1" },
      },
    })

    local provider = state.get_provider()
    assert.is_not_nil(provider)
    assert.are.equal("europe-west1", provider.parameters.location)
    assert.are.equal("my-project", provider.parameters.project_id)
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

    local config = state.get_config()
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

    -- Provider should NOT have been initialized
    assert.is_nil(state.get_provider())
    -- Should have an error notification
    local found_error = false
    for _, n in ipairs(notifications) do
      if n.msg and n.msg:match("conflicts") then
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

    -- Provider should NOT have been initialized
    assert.is_nil(state.get_provider())
    -- Should have an error notification
    local found_error = false
    for _, n in ipairs(notifications) do
      if n.msg and n.msg:match("not found") then
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
