local stub = require("luassert.stub")

describe(":FlemmaSend command", function()
  local base_provider_module = require("flemma.provider.base")
  local state = require("flemma.state")

  before_each(function()
    -- Invalidate the main flemma module cache to ensure a clean setup for each test
    package.loaded["flemma"] = nil
    local flemma = require("flemma")
    -- Setup with default configuration. Specific tests can override this.
    flemma.setup({})
  end)

  after_each(function()
    -- Clear any registered fixtures to ensure test isolation
    base_provider_module.clear_fixtures()

    -- Clean up any buffers created during the test
    vim.cmd("silent! %bdelete!")
  end)

  it("formats the request body correctly for the default Claude provider", function()
    -- Arrange: The default provider is Claude. We just need to set up the buffer.
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@System: Be brief.", "@You: Hello" })

    -- Arrange: Register a dummy fixture to prevent actual network calls.
    -- The content of the fixture DOES matter, as it's processed by the provider.
    local flemma = require("flemma")
    local state = require("flemma.state")
    local config = state.get_config()
    local default_claude_model = require("flemma.provider.config").get_model("claude")
    base_provider_module.register_fixture(default_claude_model, "tests/fixtures/claude_hello_success_stream.txt")

    -- Act: Execute the FlemmaSend command
    vim.cmd("FlemmaSend")

    -- Assert: Check that the captured request body matches the expected format for Claude
    local captured_request_body = flemma._get_last_request_body()
    assert.is_not_nil(captured_request_body, "request_body was not captured")
    local default_claude_model = require("flemma.provider.config").get_model("claude")

    local expected_body = {
      model = default_claude_model,
      messages = {
        { role = "user", content = { { type = "text", text = "Hello" } } },
      },
      system = "Be brief.",
      max_tokens = config.parameters.max_tokens,
      temperature = config.parameters.temperature,
      stream = true,
    }

    assert.are.same(expected_body, captured_request_body)
  end)

  it("formats the request body correctly for the OpenAI provider", function()
    -- Arrange: Switch to the OpenAI provider for this test
    local flemma = require("flemma")
    flemma.switch("openai", "o3", {})

    -- Arrange: Register a dummy fixture to prevent actual network calls.
    base_provider_module.register_fixture("o3", "tests/fixtures/openai_hello_success_stream.txt")

    -- Arrange: Create a new buffer, make it current, and set its content
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You: Hello" })

    -- Act: Execute the FlemmaSend command
    vim.cmd("FlemmaSend")

    -- Assert: Check that the captured request body matches the expected format for OpenAI
    local captured_request_body = flemma._get_last_request_body()
    assert.is_not_nil(captured_request_body, "request_body was not captured")

    local config = state.get_config()

    local expected_body = {
      model = "o3",
      messages = {
        { role = "user", content = "Hello" },
      },
      stream = true,
      stream_options = { include_usage = true },
      max_tokens = config.parameters.max_tokens,
      temperature = config.parameters.temperature,
    }

    assert.are.same(expected_body, captured_request_body)
  end)

  it("handles a successful streaming response from a fixture", function()
    -- Arrange: Switch to the OpenAI provider and model that matches the fixture
    local flemma = require("flemma")
    flemma.switch("openai", "o3", {})

    -- Arrange: Register the fixture to be used by the provider
    base_provider_module.register_fixture("o3", "tests/fixtures/openai_hello_success_stream.txt")

    -- Arrange: Set up the buffer with an initial prompt
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You: Hello" })

    -- Act: Execute the command
    vim.cmd("FlemmaSend")

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
    local flemma = require("flemma")
    flemma.switch("openai", "o3", {})

    -- Arrange: Register the error fixture
    base_provider_module.register_fixture("o3", "tests/fixtures/openai_invalid_key_error.txt")

    -- Arrange: Set up the buffer
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You: This will fail" })

    -- Arrange: Stub vim.notify to prevent UI and capture calls
    local notify_spy = stub(vim, "notify")

    -- Act: Execute the command
    vim.cmd("FlemmaSend")

    -- Wait for the notification to be called
    vim.wait(500, function()
      return #notify_spy.calls > 0
    end, 10, false)

    -- Assert: Check that vim.notify was called with the correct error message
    -- Read expected error from fixture
    local file = io.open("tests/fixtures/openai_invalid_key_error.txt", "r")
    assert.is_not_nil(file, "Fixture file could not be opened")
    local fixture_content = file:read("*a")
    file:close()
    local error_data = vim.fn.json_decode(fixture_content)
    local expected_error_message = "Flemma: " .. error_data.error.message

    local last_call = notify_spy.calls[#notify_spy.calls]
    assert.equals(expected_error_message, last_call.refs[1])
    assert.equals(vim.log.levels.ERROR, last_call.refs[2])

    -- Assert: Check that the buffer is modifiable and clean
    assert.is_true(vim.bo[bufnr].modifiable, "Buffer should be modifiable after an error")
    local final_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({ "@You: This will fail", "" }, final_lines, "Buffer content should not have spinner artifacts")

    -- Cleanup
    notify_spy:revert()
  end)

  it("errors and does not switch when an unknown provider is requested", function()
    -- Arrange: Ensure we start from a valid, known provider (default is Claude)
    local flemma = require("flemma")
    local original_provider = flemma.get_current_provider_name()
    assert.is_not_nil(original_provider, "Original provider should be set")

    -- Arrange: Stub notifications to capture the error
    local notify_spy = stub(vim, "notify")

    -- Act: Attempt to switch to an unsupported provider
    local result = flemma.switch("huggingface", nil, {})

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
    -- Arrange
    local flemma = require("flemma")

    -- Stub notifications
    local notify_spy = stub(vim, "notify")

    -- Act: Attempt to switch to an invalid model on a valid provider
    local result = flemma.switch("openai", "gpt-6", {})

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
    local default_openai_model = require("flemma.provider.config").get_model("openai")
    local cfg = state.get_config()
    assert.equals(default_openai_model, cfg.model, "Should fall back to provider default model")

    -- Cleanup
    notify_spy:revert()
  end)
end)
