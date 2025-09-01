local stub = require("luassert.stub")

describe(":ClaudiusSend command", function()
  local base_provider_module = require("claudius.provider.base")

  before_each(function()
    -- Invalidate the main claudius module cache to ensure a clean setup for each test
    package.loaded["claudius"] = nil
    local claudius = require("claudius")
    -- Setup with default configuration. Specific tests can override this.
    claudius.setup({})
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
    local claudius = require("claudius")
    local config = claudius._get_config()
    local default_claude_model = require("claudius.provider.config").get_model("claude")
    base_provider_module.register_fixture(default_claude_model, "tests/fixtures/claude_hello_success_stream.txt")

    -- Act: Execute the ClaudiusSend command
    vim.cmd("ClaudiusSend")

    -- Assert: Check that the captured request body matches the expected format for Claude
    local captured_request_body = claudius._get_last_request_body()
    assert.is_not_nil(captured_request_body, "request_body was not captured")
    local default_claude_model = require("claudius.provider.config").get_model("claude")

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
    local claudius = require("claudius")
    claudius.switch("openai", "o3", {})

    -- Arrange: Register a dummy fixture to prevent actual network calls.
    base_provider_module.register_fixture("o3", "tests/fixtures/openai_hello_success_stream.txt")

    -- Arrange: Create a new buffer, make it current, and set its content
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You: Hello" })

    -- Act: Execute the ClaudiusSend command
    vim.cmd("ClaudiusSend")

    -- Assert: Check that the captured request body matches the expected format for OpenAI
    local captured_request_body = claudius._get_last_request_body()
    assert.is_not_nil(captured_request_body, "request_body was not captured")

    local config = claudius._get_config()

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
    local claudius = require("claudius")
    claudius.switch("openai", "o3", {})

    -- Arrange: Register the fixture to be used by the provider
    base_provider_module.register_fixture("o3", "tests/fixtures/openai_hello_success_stream.txt")

    -- Arrange: Set up the buffer with an initial prompt
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You: Hello" })

    -- Act: Execute the command
    vim.cmd("ClaudiusSend")

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
    local claudius = require("claudius")
    claudius.switch("openai", "o3", {})

    -- Arrange: Register the error fixture
    base_provider_module.register_fixture("o3", "tests/fixtures/openai_invalid_key_error.txt")

    -- Arrange: Set up the buffer
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You: This will fail" })

    -- Arrange: Stub vim.notify to prevent UI and capture calls
    local notify_spy = stub(vim, "notify")

    -- Act: Execute the command
    vim.cmd("ClaudiusSend")

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
    local expected_error_message = "Claudius: " .. error_data.error.message

    local last_call = notify_spy.calls[#notify_spy.calls]
    assert.equals(expected_error_message, last_call.refs[1]);
    assert.equals(vim.log.levels.ERROR, last_call.refs[2]);

    -- Assert: Check that the buffer is modifiable and clean
    assert.is_true(vim.bo[bufnr].modifiable, "Buffer should be modifiable after an error")
    local final_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({ "@You: This will fail", "" }, final_lines, "Buffer content should not have spinner artifacts")

    -- Cleanup
    notify_spy:revert()
  end)
end)
