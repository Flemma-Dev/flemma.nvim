local stub = require("luassert.stub")

describe(":Flemma send command", function()
  local client = require("flemma.client")
  local flemma, state, core, registry

  before_each(function()
    -- Invalidate the main flemma module cache to ensure a clean setup for each test
    package.loaded["flemma"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.core.config.manager"] = nil
    package.loaded["flemma.provider.registry"] = nil
    package.loaded["flemma.models"] = nil

    flemma = require("flemma")
    state = require("flemma.state")
    core = require("flemma.core")
    registry = require("flemma.provider.registry")

    -- Setup with default configuration. Disable thinking so request-format tests
    -- get predictable temperature values. Specific tests can override this.
    flemma.setup({ parameters = { thinking = false } })
  end)

  after_each(function()
    -- Clear any registered fixtures to ensure test isolation
    client.clear_fixtures()

    -- Clean up any buffers created during the test
    vim.cmd("silent! %bdelete!")
  end)

  it("formats the request body correctly for the default Anthropic provider", function()
    -- Arrange: The default provider is Anthropic. We just need to set up the buffer.
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@System: Be brief.", "@You: Hello" })

    -- Arrange: Register a dummy fixture to prevent actual network calls.
    -- The content of the fixture DOES matter, as it's processed by the provider.
    local config = state.get_config()
    local default_anthropic_model = registry.get_model("anthropic")
    client.register_fixture("api%.anthropic%.com", "tests/fixtures/anthropic_hello_success_stream.txt")

    -- Act: Execute the Flemma send command
    vim.cmd("Flemma send")

    -- Assert: Check that the captured request body matches the expected format for Anthropic
    local captured_request_body = core._get_last_request_body()
    assert.is_not_nil(captured_request_body, "request_body was not captured")

    assert.equals(default_anthropic_model, captured_request_body.model)
    -- With cache_retention="short" (default), system is an array with cache_control
    assert.equals(1, #captured_request_body.system)
    assert.equals("Be brief.", captured_request_body.system[1].text)
    assert.equals(config.parameters.max_tokens, captured_request_body.max_tokens)
    assert.equals(config.parameters.temperature, captured_request_body.temperature)
    assert.equals(true, captured_request_body.stream)
    assert.equals(1, #captured_request_body.messages)
    assert.equals("user", captured_request_body.messages[1].role)
    assert.equals("Hello", captured_request_body.messages[1].content[1].text)
    -- Tools are now included by default (MVP tool calling support)
    if captured_request_body.tools then
      assert.is_true(#captured_request_body.tools >= 0)
    end
  end)

  it("formats the request body correctly for the OpenAI provider", function()
    -- Arrange: Switch to the OpenAI provider for this test
    core.switch_provider("openai", "o3", {})

    -- Arrange: Register a dummy fixture to prevent actual network calls.
    client.register_fixture("api%.openai%.com", "tests/fixtures/openai_hello_success_stream.txt")

    -- Arrange: Create a new buffer, make it current, and set its content
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You: Hello" })

    -- Act: Execute the Flemma send command
    vim.cmd("Flemma send")

    -- Assert: Check that the captured request body matches the expected format for OpenAI
    local captured_request_body = core._get_last_request_body()
    assert.is_not_nil(captured_request_body, "request_body was not captured")

    local config = state.get_config()

    assert.equals("o3", captured_request_body.model)
    assert.is_not_nil(captured_request_body.input, "Should use input field (Responses API)")
    assert.is_nil(captured_request_body.messages, "Should NOT use messages field")
    -- Find the user message in the input array
    local user_items = vim.tbl_filter(function(item)
      return item.role == "user"
    end, captured_request_body.input)
    assert.equals(1, #user_items)
    assert.equals(true, captured_request_body.stream)
    assert.equals(false, captured_request_body.store)
    assert.is_nil(captured_request_body.stream_options, "Responses API does not use stream_options")
    assert.equals(config.parameters.max_tokens, captured_request_body.max_output_tokens)
    assert.equals(config.parameters.temperature, captured_request_body.temperature)

    -- Tools are now included by default (parallel tool use enabled)
    if captured_request_body.tools then
      assert.is_true(#captured_request_body.tools >= 0)
      assert.equals("auto", captured_request_body.tool_choice)
      -- Parallel tool use is enabled (no parallel_tool_calls: false flag)
      assert.is_nil(captured_request_body.parallel_tool_calls)
    end
  end)

  it("always stores bufnr in session requests", function()
    -- Arrange: Switch to OpenAI
    core.switch_provider("openai", "o3", {})
    client.register_fixture("api%.openai%.com", "tests/fixtures/openai_hello_success_stream.txt")

    -- Test 1: Named buffer → both filepath and bufnr should be set
    local named_bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(named_bufnr)
    vim.api.nvim_buf_set_name(named_bufnr, vim.fn.tempname() .. ".chat")
    vim.api.nvim_buf_set_lines(named_bufnr, 0, -1, false, { "@You: Hello" })

    vim.cmd("Flemma send")
    vim.wait(1000, function()
      local lines = vim.api.nvim_buf_get_lines(named_bufnr, 0, -1, false)
      return #lines >= 5 and lines[5] == "@You: "
    end)

    local session = state.get_session()
    local named_request = session:get_latest_request()
    assert.is_not_nil(named_request, "Session should have a request after named buffer send")
    assert.is_not_nil(named_request.filepath, "Named buffer should have a filepath")
    assert.equals(named_bufnr, named_request.bufnr, "Named buffer request should store bufnr")

    -- Test 2: Unnamed buffer → bufnr should be set, filepath should be nil
    client.register_fixture("api%.openai%.com", "tests/fixtures/openai_hello_success_stream.txt")
    local unnamed_bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(unnamed_bufnr)
    vim.api.nvim_buf_set_lines(unnamed_bufnr, 0, -1, false, { "@You: Hello" })

    vim.cmd("Flemma send")
    vim.wait(1000, function()
      local lines = vim.api.nvim_buf_get_lines(unnamed_bufnr, 0, -1, false)
      return #lines >= 5 and lines[5] == "@You: "
    end)

    local unnamed_request = session:get_latest_request()
    assert.is_not_nil(unnamed_request, "Session should have a request after unnamed buffer send")
    assert.is_nil(unnamed_request.filepath, "Unnamed buffer should NOT have a filepath")
    assert.equals(unnamed_bufnr, unnamed_request.bufnr, "Unnamed buffer request should store bufnr")
  end)

  it("handles a successful streaming response from a fixture", function()
    -- Arrange: Switch to the OpenAI provider and model that matches the fixture
    core.switch_provider("openai", "o3", {})

    -- Arrange: Register the fixture to be used by the provider
    client.register_fixture("api%.openai%.com", "tests/fixtures/openai_hello_success_stream.txt")

    -- Arrange: Set up the buffer with an initial prompt
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You: Hello" })

    -- Act: Execute the command
    vim.cmd("Flemma send")

    -- Wait for the response to be processed and the new prompt to be added
    vim.wait(1000, function()
      local final_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      return #final_lines == 5 and final_lines[5] == "@You: "
    end)

    -- Assert: Check the final buffer content
    local final_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local expected_lines = {
      "@You: Hello",
      "",
      "@Assistant: Hello! How can I help you today?",
      "",
      "@You: ",
    }
    assert.are.same(expected_lines, final_lines)
  end)

  it("handles an error response from a fixture", function()
    -- Arrange: Switch to the OpenAI provider
    core.switch_provider("openai", "o3", {})

    -- Arrange: Register the error fixture
    client.register_fixture("api%.openai%.com", "tests/fixtures/openai_invalid_key_error.txt")

    -- Arrange: Set up the buffer
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You: This will fail" })

    -- Arrange: Stub vim.notify to prevent UI and capture calls
    local notify_spy = stub(vim, "notify")

    -- Read expected error from fixture and execute the command
    local file = io.open("tests/fixtures/openai_invalid_key_error.txt", "r")
    assert.is_not_nil(file, "Fixture file could not be opened")
    local fixture_content = file:read("*a")
    file:close()
    local error_data = vim.json.decode(fixture_content)
    local expected_error_message = "Flemma: " .. error_data.error.message

    vim.cmd("Flemma send")

    -- Wait for the expected error notification instead of the first notify call
    vim.wait(2000, function()
      for _, call in ipairs(notify_spy.calls) do
        if call.refs[1] == expected_error_message then
          return true
        end
      end
      return false
    end, 10, false)

    local error_seen = false
    local error_level = nil

    for _, call in ipairs(notify_spy.calls) do
      if call.refs[1] == expected_error_message then
        error_seen = true
        error_level = call.refs[2]
      end
    end

    assert.is_true(error_seen, "Expected error notification was not emitted")
    assert.equals(vim.log.levels.ERROR, error_level)

    -- Assert: Check that the buffer is modifiable and clean
    assert.is_true(vim.bo[bufnr].modifiable, "Buffer should be modifiable after an error")
    assert.is_false(state.get_buffer_state(bufnr).locked, "Buffer state should not be locked after an error")
    local final_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({ "@You: This will fail", "" }, final_lines, "Buffer content should not have spinner artifacts")

    -- Cleanup
    notify_spy:revert()
  end)

  it("errors and does not switch when an unknown provider is requested", function()
    -- Arrange: Ensure we start from a valid, known provider (default is Anthropic)
    local original_provider = flemma.get_current_provider_name()
    assert.is_not_nil(original_provider, "Original provider should be set")

    -- Arrange: Stub notifications to capture the error
    local notify_spy = stub(vim, "notify")

    -- Act: Attempt to switch to an unsupported provider
    local result = core.switch_provider("huggingface", nil, {})

    -- Allow a brief moment for any notify to be recorded (synchronous in this case)
    vim.wait(50, function()
      return #notify_spy.calls > 0
    end, 10, false)

    -- Assert: switch should fail and return nil
    assert.is_nil(result, "switch should return nil for unknown provider")

    -- Assert: Provider should remain unchanged
    local current_provider = flemma.get_current_provider_name()
    assert.equals(original_provider, current_provider, "Provider should remain unchanged on invalid switch")

    -- Assert: An error notification was emitted
    local last_call = notify_spy.calls[#notify_spy.calls]
    assert.is_not_nil(last_call, "vim.notify should have been called")
    assert.equals(vim.log.levels.ERROR, last_call.refs[2], "Notification should be an error")
    assert.is_true(string.find(last_call.refs[1], "Unknown provider 'huggingface'") ~= nil)

    -- Cleanup
    notify_spy:revert()
  end)

  it("warns and falls back to the default model when an invalid model is requested", function()
    -- Arrange: Stub notifications
    local notify_spy = stub(vim, "notify")

    -- Act: Attempt to switch to an invalid model on a valid provider
    local result = core.switch_provider("openai", "gpt-6", {})

    -- Assert: switch returns a provider instance
    assert.is_not_nil(result, "switch should succeed when provider is valid, even if model is invalid")

    -- Wait for notify to capture calls
    vim.wait(50, function()
      return #notify_spy.calls > 0
    end, 10, false)

    -- Assert: A warn notification about model fallback was emitted
    local saw_warn = false
    for _, call in ipairs(notify_spy.calls) do
      local msg = call.refs[1]
      local level = call.refs[2]
      if
        level == vim.log.levels.WARN
        and msg
        and string.find(msg, "Model 'gpt%-6' is not valid for provider 'openai'")
      then
        saw_warn = true
        break
      end
    end
    assert.is_true(saw_warn, "Should warn about invalid model fallback")

    -- Assert: Model fell back to the provider default
    local default_openai_model = registry.get_model("openai")
    local cfg = state.get_config()
    assert.equals(default_openai_model, cfg.model, "Should fall back to provider default model")

    -- Cleanup
    notify_spy:revert()
  end)
end)
