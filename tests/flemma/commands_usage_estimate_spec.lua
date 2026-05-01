--- Tests for the :Flemma usage:estimate command dispatcher (format + notify).

describe(":Flemma usage:estimate dispatcher", function()
  local client = require("flemma.client")
  local notify = require("flemma.notify")
  local flemma
  local captured

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.commands"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.provider.normalize"] = nil
    package.loaded["flemma.provider.registry"] = nil

    flemma = require("flemma")
    flemma.setup({ parameters = { thinking = false } })

    captured = {}
    notify._set_impl(function(notification)
      table.insert(captured, notification)
      return notification
    end)
  end)

  after_each(function()
    notify._reset_impl()
    client.clear_fixtures()
    vim.cmd("silent! %bdelete!")
  end)

  local function make_chat_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or { "@You:", "Hello" })
    return bufnr
  end

  local function wait_for(predicate)
    vim.wait(2000, function()
      for _, n in ipairs(captured) do
        if predicate(n) then
          return true
        end
      end
      return false
    end, 10, false)
    for _, n in ipairs(captured) do
      if predicate(n) then
        return n
      end
    end
    return nil
  end

  local function run_estimate()
    vim.cmd("Flemma usage:estimate")
  end

  it("reports input tokens, cost, model, and per-MTok pricing on success", function()
    client.register_fixture("messages/count_tokens", "tests/fixtures/anthropic/count_tokens_response.txt")
    make_chat_buffer()

    run_estimate()

    local info = wait_for(function(n)
      return n.level == vim.log.levels.INFO
    end)
    assert.is_not_nil(info)
    local middot = "\xc2\xb7"
    local expected = "5,432 input tokens "
      .. middot
      .. " $0.016 "
      .. middot
      .. " claude-sonnet-4-6 ($3 input / $15 output per MTok)"
    assert.are.equal(expected, info.message)
  end)

  it("surfaces API errors via notify.error with 'Estimate failed:' prefix", function()
    client.register_fixture("messages/count_tokens", "tests/fixtures/anthropic/count_tokens_error.txt")
    make_chat_buffer()

    run_estimate()

    local err = wait_for(function(n)
      return n.level == vim.log.levels.ERROR
    end)
    assert.is_not_nil(err)
    assert.is_truthy(err.message:find("Estimate failed:", 1, true))
    assert.is_truthy(err.message:find("authentication_error", 1, true))
  end)

  it("reports OpenAI estimates through the same dispatcher path", function()
    flemma.setup({ provider = "openai", model = "gpt-5", parameters = { thinking = false } })
    client.register_fixture("responses/input_tokens", "tests/fixtures/openai/count_tokens_response.txt")
    make_chat_buffer()

    run_estimate()

    local info = wait_for(function(n)
      return n.level == vim.log.levels.INFO
    end)
    assert.is_not_nil(info)
    assert.is_truthy(info.message:find("9 input tokens", 1, true))
    assert.is_truthy(info.message:find("gpt-5", 1, true))
    assert.is_truthy(info.message:find("$1.25 input / $10 output per MTok", 1, true))
  end)

  it("notifies when the current provider does not implement try_estimate_usage", function()
    local module_path = "flemma.test.unsupported_estimate_provider"
    package.preload[module_path] = function()
      return {}
    end
    local provider_registry = require("flemma.provider.registry")
    provider_registry.register("unsupported-estimate", {
      module = module_path,
      capabilities = {
        supports_reasoning = false,
        supports_thinking_budget = false,
        outputs_thinking = false,
      },
      display_name = "Unsupported Estimate",
      default_model = "unsupported-model",
      models = {
        ["unsupported-model"] = {},
      },
    })
    local config = require("flemma.config")
    config.apply(config.LAYERS.RUNTIME, { provider = "unsupported-estimate", model = "unsupported-model" })
    make_chat_buffer()

    run_estimate()

    local err = wait_for(function(n)
      return n.level == vim.log.levels.ERROR
    end)
    assert.is_not_nil(err)
    assert.equals("Current provider does not support usage estimates.", err.message)
  end)

  it("notifies when no provider is configured", function()
    -- Wipe the provider via runtime apply to simulate the unconfigured state.
    local config = require("flemma.config")
    config.apply(config.LAYERS.RUNTIME, { provider = "" })
    make_chat_buffer()

    run_estimate()

    local err = wait_for(function(n)
      return n.level == vim.log.levels.ERROR
    end)
    assert.is_not_nil(err)
    assert.equals("No provider configured. Use :Flemma switch to select one.", err.message)
  end)
end)
