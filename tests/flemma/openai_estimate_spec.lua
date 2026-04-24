--- Tests for the OpenAI adapter's try_estimate_usage callback contract.

describe("openai.try_estimate_usage", function()
  local client = require("flemma.client")
  local notify = require("flemma.notify")
  local flemma, openai
  local notify_count

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.commands"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.provider.normalize"] = nil
    package.loaded["flemma.provider.registry"] = nil
    package.loaded["flemma.provider.adapters.openai"] = nil

    flemma = require("flemma")
    openai = require("flemma.provider.adapters.openai")

    flemma.setup({
      provider = "openai",
      model = "gpt-5",
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
  ---@return integer bufnr
  local function make_chat_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or { "@You:", "Hello" })
    return bufnr
  end

  ---@param captured table<string, flemma.usage.EstimateResult>
  ---@param predicate fun(result: flemma.usage.EstimateResult): boolean
  ---@return flemma.usage.EstimateResult|nil result
  local function wait_for_result(captured, predicate)
    vim.wait(2000, function()
      return captured.result and predicate(captured.result)
    end, 10, false)
    return captured.result
  end

  it("delivers tokens, cache_key, and model on success", function()
    client.register_fixture("responses/input_tokens", "tests/fixtures/openai/count_tokens_response.txt")
    local bufnr = make_chat_buffer()

    local captured = {}
    openai.try_estimate_usage(bufnr, function(result)
      captured.result = result
    end)

    local result = wait_for_result(captured, function(r)
      return r.response ~= nil
    end)

    assert.is_not_nil(result, "Expected callback to fire with a response")
    assert.is_nil(result.err)
    assert.is_not_nil(result.response)
    assert.equals(9, result.response.tokens)
    assert.equals("gpt-5", result.response.model)
    assert.equals("openai:gpt-5", result.response.cache_key)
    assert.equals(0, notify_count, "Adapter must not call notify directly")
  end)

  it("strips fields rejected by the input token endpoint but preserves input-affecting fields", function()
    flemma.setup({
      provider = "openai",
      model = "gpt-5",
      parameters = {
        thinking = "low",
        temperature = 0.2,
        cache_retention = "long",
      },
    })
    client.register_fixture("responses/input_tokens", "tests/fixtures/openai/count_tokens_response.txt")
    local bufnr = make_chat_buffer()
    vim.api.nvim_buf_set_name(bufnr, "/tmp/flemma-openai-estimate.chat")

    local captured_body
    local original_send = client.send_json_request
    client.send_json_request = function(opts, cb)
      captured_body = opts.request_body
      return original_send(opts, cb)
    end

    local captured = {}
    openai.try_estimate_usage(bufnr, function(result)
      captured.result = result
    end)
    wait_for_result(captured, function(r)
      return r.response ~= nil
    end)

    client.send_json_request = original_send

    assert.is_not_nil(captured_body)
    assert.is_nil(captured_body.stream)
    assert.is_nil(captured_body.store)
    assert.is_nil(captured_body.max_output_tokens)
    assert.is_nil(captured_body.temperature)
    assert.is_nil(captured_body.include)
    assert.is_nil(captured_body.prompt_cache_key)
    assert.is_nil(captured_body.prompt_cache_retention)
    assert.is_not_nil(captured_body.tools, "tool schemas affect input token count")
    assert.equals("auto", captured_body.tool_choice)
    assert.is_not_nil(captured_body.reasoning, "reasoning is accepted by the endpoint")
    assert.equals("low", captured_body.reasoning.effort)
  end)

  it("delivers err for auth error responses", function()
    client.register_fixture("responses/input_tokens", "tests/fixtures/openai/count_tokens_error.txt")
    local bufnr = make_chat_buffer()

    local captured = {}
    openai.try_estimate_usage(bufnr, function(result)
      captured.result = result
    end)

    local result = wait_for_result(captured, function(r)
      return r.err ~= nil
    end)

    assert.is_not_nil(result)
    assert.is_nil(result.response)
    assert.is_truthy(result.err:find("invalid_request_error", 1, true))
    assert.is_truthy(result.err:find("Incorrect API key", 1, true))
    assert.equals(0, notify_count, "Adapter must not call notify directly")
  end)

  it("delivers err for validation responses", function()
    client.register_fixture("responses/input_tokens", "tests/fixtures/openai/count_tokens_bad_request.txt")
    local bufnr = make_chat_buffer()

    local captured = {}
    openai.try_estimate_usage(bufnr, function(result)
      captured.result = result
    end)

    local result = wait_for_result(captured, function(r)
      return r.err ~= nil
    end)

    assert.is_not_nil(result)
    assert.is_nil(result.response)
    assert.is_truthy(result.err:find("invalid_request_error", 1, true))
    assert.is_truthy(result.err:find("Invalid type for 'input'", 1, true))
    assert.equals(0, notify_count, "Adapter must not call notify directly")
  end)

  it("delivers err for empty buffer (build failure)", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)

    local captured = {}
    openai.try_estimate_usage(bufnr, function(result)
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
    client.register_fixture("responses/input_tokens", "tests/fixtures/openai/count_tokens_unparseable.txt")
    local bufnr = make_chat_buffer()

    local captured = {}
    openai.try_estimate_usage(bufnr, function(result)
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
