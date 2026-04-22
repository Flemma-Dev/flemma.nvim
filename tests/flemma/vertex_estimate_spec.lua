--- Tests for the Vertex AI adapter's try_estimate_usage callback contract.

describe("vertex.try_estimate_usage", function()
  local client = require("flemma.client")
  local notify = require("flemma.notify")
  local flemma, vertex
  local notify_count

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.commands"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.provider.normalize"] = nil
    package.loaded["flemma.provider.registry"] = nil
    package.loaded["flemma.provider.adapters.vertex"] = nil

    flemma = require("flemma")
    vertex = require("flemma.provider.adapters.vertex")

    flemma.setup({
      provider = "vertex",
      model = "gemini-2.5-flash",
      parameters = {
        thinking = false,
        vertex = { project_id = "test-project", location = "global" },
      },
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
    client.register_fixture(":countTokens", "tests/fixtures/vertex/count_tokens_response.txt")
    local bufnr = make_chat_buffer()

    local captured = {}
    vertex.try_estimate_usage(bufnr, function(result)
      captured.result = result
    end)

    local result = wait_for_result(captured, function(r)
      return r.response ~= nil
    end)

    assert.is_not_nil(result, "Expected callback to fire with a response")
    assert.is_nil(result.err)
    assert.is_not_nil(result.response)
    assert.equals(3, result.response.tokens)
    assert.equals("gemini-2.5-flash", result.response.model)
    assert.equals("vertex:gemini-2.5-flash", result.response.cache_key)
    assert.equals(0, notify_count, "Adapter must not call notify directly")
  end)

  -- Regression: countTokens rejects any top-level field outside the set
  -- { model, instances, contents, tools, systemInstruction, generationConfig }
  -- (per v1beta1 REST reference). Vertex's build_request emits `toolConfig`
  -- alongside `tools`, which would cause a 400 INVALID_ARGUMENT — strip it.
  it("strips toolConfig and generationConfig from the outgoing body", function()
    client.register_fixture(":countTokens", "tests/fixtures/vertex/count_tokens_response.txt")
    local bufnr = make_chat_buffer()

    local captured_body
    local original_send = client.send_json_request
    client.send_json_request = function(opts, cb)
      captured_body = opts.request_body
      return original_send(opts, cb)
    end

    local captured = {}
    vertex.try_estimate_usage(bufnr, function(result)
      captured.result = result
    end)
    wait_for_result(captured, function(r)
      return r.response ~= nil
    end)

    client.send_json_request = original_send

    assert.is_not_nil(captured_body)
    assert.is_nil(captured_body.toolConfig, "toolConfig must be stripped — countTokens rejects it")
    assert.is_nil(captured_body.generationConfig)
    -- Sanity: tools definitions must remain so the count reflects their size.
    assert.is_not_nil(captured_body.tools)
  end)

  it("delivers err for auth error responses", function()
    client.register_fixture(":countTokens", "tests/fixtures/vertex/count_tokens_error.txt")
    local bufnr = make_chat_buffer()

    local captured = {}
    vertex.try_estimate_usage(bufnr, function(result)
      captured.result = result
    end)

    local result = wait_for_result(captured, function(r)
      return r.err ~= nil
    end)

    assert.is_not_nil(result)
    assert.is_nil(result.response)
    assert.is_truthy(result.err:lower():find("invalid authentication credentials", 1, true))
    assert.is_truthy(result.err:find("UNAUTHENTICATED", 1, true))
    assert.equals(0, notify_count, "Adapter must not call notify directly")
  end)

  it("delivers err for validation (bad request) responses", function()
    client.register_fixture(":countTokens", "tests/fixtures/vertex/count_tokens_bad_request.txt")
    local bufnr = make_chat_buffer()

    local captured = {}
    vertex.try_estimate_usage(bufnr, function(result)
      captured.result = result
    end)

    local result = wait_for_result(captured, function(r)
      return r.err ~= nil
    end)

    assert.is_not_nil(result)
    assert.is_nil(result.response)
    assert.is_truthy(result.err:find("INVALID_ARGUMENT", 1, true))
    assert.is_truthy(result.err:find("contents", 1, true))
    assert.equals(0, notify_count, "Adapter must not call notify directly")
  end)

  it("delivers err for empty buffer (build failure)", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)

    local captured = {}
    vertex.try_estimate_usage(bufnr, function(result)
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
    client.register_fixture(":countTokens", "tests/fixtures/vertex/count_tokens_unparseable.txt")
    local bufnr = make_chat_buffer()

    local captured = {}
    vertex.try_estimate_usage(bufnr, function(result)
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
