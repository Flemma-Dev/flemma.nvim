--- Tests for the Moonshot adapter's try_estimate_usage callback contract.

describe("moonshot.try_estimate_usage", function()
  local client = require("flemma.client")
  local notify = require("flemma.notify")
  local flemma, moonshot
  local notify_count

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.commands"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.provider.normalize"] = nil
    package.loaded["flemma.provider.registry"] = nil
    package.loaded["flemma.provider.adapters.moonshot"] = nil

    flemma = require("flemma")
    moonshot = require("flemma.provider.adapters.moonshot")

    flemma.setup({
      provider = "moonshot",
      model = "kimi-k2.5",
      parameters = { thinking = false },
    })

    notify_count = 0
    notify._set_impl(function(notification)
      notify_count = notify_count + 1
      return notification
    end)
  end)

  after_each(function()
    notify._reset_impl()
    client.clear_fixtures()
    vim.cmd("silent! %bdelete!")
  end)

  ---@param lines? string[]
  local function make_chat_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or { "@You:", "Hello" })
    return bufnr
  end

  ---@param predicate fun(result: flemma.usage.EstimateResult): boolean
  local function wait_for_result(captured, predicate)
    vim.wait(2000, function()
      return captured.result and predicate(captured.result)
    end, 10, false)
    return captured.result
  end

  it("delivers tokens, cache_key, and model on success", function()
    client.register_fixture("tokenizers/estimate", "tests/fixtures/moonshot/count_tokens_response.txt")
    local bufnr = make_chat_buffer()

    local captured = {}
    moonshot.try_estimate_usage(bufnr, function(result)
      captured.result = result
    end)

    local result = wait_for_result(captured, function(r)
      return r.response ~= nil
    end)

    assert.is_not_nil(result, "Expected callback to fire with a response")
    assert.is_nil(result.err)
    assert.is_not_nil(result.response)
    assert.equals(10, result.response.tokens)
    assert.equals("kimi-k2.5", result.response.model)
    assert.equals("moonshot:kimi-k2.5", result.response.cache_key)
    assert.equals(0, notify_count, "Adapter must not call notify directly")
  end)

  it("delivers err for auth error responses (object error shape)", function()
    client.register_fixture("tokenizers/estimate", "tests/fixtures/moonshot/count_tokens_error.txt")
    local bufnr = make_chat_buffer()

    local captured = {}
    moonshot.try_estimate_usage(bufnr, function(result)
      captured.result = result
    end)

    local result = wait_for_result(captured, function(r)
      return r.err ~= nil
    end)

    assert.is_not_nil(result)
    assert.is_nil(result.response)
    assert.is_truthy(result.err:find("invalid_authentication_error", 1, true))
    assert.is_truthy(result.err:find("Invalid Authentication", 1, true))
    assert.equals(0, notify_count, "Adapter must not call notify directly")
  end)

  it("delivers err for validation (bad request) responses (string error shape)", function()
    client.register_fixture("tokenizers/estimate", "tests/fixtures/moonshot/count_tokens_bad_request.txt")
    local bufnr = make_chat_buffer()

    local captured = {}
    moonshot.try_estimate_usage(bufnr, function(result)
      captured.result = result
    end)

    local result = wait_for_result(captured, function(r)
      return r.err ~= nil
    end)

    assert.is_not_nil(result)
    assert.is_nil(result.response)
    assert.is_truthy(result.err:find("messages", 1, true))
    assert.is_truthy(result.err:find("illegal", 1, true))
    assert.equals(0, notify_count, "Adapter must not call notify directly")
  end)

  it("delivers err for empty buffer (build failure)", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)

    local captured = {}
    moonshot.try_estimate_usage(bufnr, function(result)
      captured.result = result
    end)

    local result = wait_for_result(captured, function(r)
      return r.err ~= nil
    end)

    assert.is_not_nil(result)
    assert.is_truthy(result.err:find("Empty buffer", 1, true))
    assert.equals(0, notify_count, "Adapter must not call notify directly")
  end)

  it("delivers err for unparseable response", function()
    client.register_fixture("tokenizers/estimate", "tests/fixtures/moonshot/count_tokens_unparseable.txt")
    local bufnr = make_chat_buffer()

    local captured = {}
    moonshot.try_estimate_usage(bufnr, function(result)
      captured.result = result
    end)

    local result = wait_for_result(captured, function(r)
      return r.err ~= nil
    end)

    assert.is_not_nil(result)
    assert.is_truthy(result.err:find("could not parse response", 1, true))
    assert.equals(0, notify_count)
  end)
end)
