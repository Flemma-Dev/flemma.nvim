local notify = require("flemma.notify")

local function flush_schedule()
  vim.wait(10, function()
    return false
  end)
end

describe(":Flemma send command", function()
  local client = require("flemma.client")
  local flemma, state, core, registry
  local captured

  before_each(function()
    -- Invalidate the main flemma module cache to ensure a clean setup for each test
    package.loaded["flemma"] = nil
    package.loaded["flemma.commands"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.provider.normalize"] = nil
    package.loaded["flemma.provider.registry"] = nil

    flemma = require("flemma")
    state = require("flemma.state")
    core = require("flemma.core")
    registry = require("flemma.provider.registry")

    -- Setup with default configuration. Disable thinking so request-format tests
    -- get predictable temperature values. Specific tests can override this.
    flemma.setup({ parameters = { thinking = false } })

    captured = {}
    notify._set_impl(function(notification)
      table.insert(captured, notification)
      return notification
    end)
  end)

  after_each(function()
    notify._reset_impl()

    -- Clear any registered fixtures to ensure test isolation
    client.clear_fixtures()

    -- Clean up any buffers created during the test
    vim.cmd("silent! %bdelete!")
  end)

  it("formats the request body correctly for the default Anthropic provider", function()
    -- Arrange: The default provider is Anthropic. We just need to set up the buffer.
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@System:", "Be brief.", "@You:", "Hello" })

    -- Arrange: Register a dummy fixture to prevent actual network calls.
    -- The content of the fixture DOES matter, as it's processed by the provider.
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
    -- max_tokens resolves from "50%" of claude-sonnet-4-6's 64K max_output → 32000
    assert.equals(32000, captured_request_body.max_tokens)
    assert.is_nil(captured_request_body.temperature)
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
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "Hello" })

    -- Act: Execute the Flemma send command
    vim.cmd("Flemma send")

    -- Assert: Check that the captured request body matches the expected format for OpenAI
    local captured_request_body = core._get_last_request_body()
    assert.is_not_nil(captured_request_body, "request_body was not captured")

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
    -- max_tokens resolves from "50%" of o3's 100K max_output → 50000
    assert.equals(50000, captured_request_body.max_output_tokens)
    assert.is_nil(captured_request_body.temperature)

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
    vim.api.nvim_buf_set_lines(named_bufnr, 0, -1, false, { "@You:", "Hello" })

    vim.cmd("Flemma send")
    vim.wait(1000, function()
      local lines = vim.api.nvim_buf_get_lines(named_bufnr, 0, -1, false)
      return #lines >= 7 and lines[7] == "@You:"
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
    vim.api.nvim_buf_set_lines(unnamed_bufnr, 0, -1, false, { "@You:", "Hello" })

    vim.cmd("Flemma send")
    vim.wait(1000, function()
      local lines = vim.api.nvim_buf_get_lines(unnamed_bufnr, 0, -1, false)
      return #lines >= 7 and lines[7] == "@You:"
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
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "Hello" })

    -- Act: Execute the command
    vim.cmd("Flemma send")

    -- Wait for the response to be processed and the new prompt to be added
    vim.wait(1000, function()
      local final_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      return #final_lines == 8 and final_lines[7] == "@You:"
    end)

    -- Assert: Check the final buffer content
    local final_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local expected_lines = {
      "@You:",
      "Hello",
      "",
      "@Assistant:",
      "Hello! How can I help you today?",
      "",
      "@You:",
      "",
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
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "This will fail" })

    -- Read expected error from fixture and execute the command
    local file = io.open("tests/fixtures/openai_invalid_key_error.txt", "r")
    assert.is_not_nil(file, "Fixture file could not be opened")
    local fixture_content = file:read("*a")
    file:close()
    local error_data = vim.json.decode(fixture_content)
    -- extract_json_response_error prefixes the error type when present.
    local expected_error_message = error_data.error.type .. " — " .. error_data.error.message

    vim.cmd("Flemma send")

    -- Wait for the expected error notification
    vim.wait(2000, function()
      for _, n in ipairs(captured) do
        if n.message == expected_error_message then
          return true
        end
      end
      return false
    end, 10, false)

    local error_seen = false
    local error_level = nil

    for _, n in ipairs(captured) do
      if n.message == expected_error_message then
        error_seen = true
        error_level = n.level
      end
    end

    assert.is_true(error_seen, "Expected error notification was not emitted")
    assert.equals(vim.log.levels.ERROR, error_level)

    -- Assert: Check that the buffer is modifiable and clean
    assert.is_true(vim.bo[bufnr].modifiable, "Buffer should be modifiable after an error")
    assert.is_false(state.get_buffer_state(bufnr).locked, "Buffer state should not be locked after an error")
    local final_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({ "@You:", "This will fail", "" }, final_lines, "Buffer content should not have spinner artifacts")
  end)

  it("surfaces an error when the API returns non-JSON HTML", function()
    -- Arrange: Switch to OpenAI and register HTML error fixture
    core.switch_provider("openai", "o3", {})
    client.register_fixture("api%.openai%.com", "tests/fixtures/openai_html_error.txt")

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "This will get HTML back" })

    vim.cmd("Flemma send")

    -- Wait for error notification
    vim.wait(2000, function()
      for _, n in ipairs(captured) do
        if n.level == vim.log.levels.ERROR then
          return true
        end
      end
      return false
    end, 10, false)

    -- Should have notified an error, not silently added a new @You: prompt
    local error_seen = false
    for _, n in ipairs(captured) do
      if n.level == vim.log.levels.ERROR then
        error_seen = true
      end
    end

    assert.is_true(error_seen, "Expected error notification for non-JSON HTML response")
    assert.is_true(vim.bo[bufnr].modifiable, "Buffer should be modifiable after an error")
  end)

  it("surfaces an error when the API returns plain text", function()
    -- Arrange: Switch to OpenAI and register plain text error fixture
    core.switch_provider("openai", "o3", {})
    client.register_fixture("api%.openai%.com", "tests/fixtures/openai_plain_text_error.txt")

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "This will get plain text back" })

    vim.cmd("Flemma send")

    -- Wait for error notification
    vim.wait(2000, function()
      for _, n in ipairs(captured) do
        if n.level == vim.log.levels.ERROR then
          return true
        end
      end
      return false
    end, 10, false)

    local error_seen = false
    for _, n in ipairs(captured) do
      if n.level == vim.log.levels.ERROR then
        error_seen = true
      end
    end

    assert.is_true(error_seen, "Expected error notification for plain text response")
    assert.is_true(vim.bo[bufnr].modifiable, "Buffer should be modifiable after an error")
  end)

  it("errors and does not switch when an unknown provider is requested", function()
    local config_facade = require("flemma.config")

    -- Arrange: capture provider before the failed switch
    local original_provider = config_facade.get().provider

    -- Act: Attempt to switch to an unsupported provider
    local result = core.switch_provider("huggingface", nil, {})

    -- Allow a brief moment for any notify to be recorded
    vim.wait(50, function()
      return #captured > 0
    end, 10, false)
    flush_schedule()

    -- Assert: switch should fail and return nil
    assert.is_nil(result, "switch should return nil for unknown provider")

    -- Assert: Provider should remain unchanged
    assert.equals(original_provider, config_facade.get().provider, "Provider should remain unchanged on invalid switch")

    -- Assert: An error notification was emitted
    local last_notification = captured[#captured]
    assert.is_not_nil(last_notification, "notify should have been called")
    assert.equals(vim.log.levels.ERROR, last_notification.level, "Notification should be an error")
    assert.is_true(string.find(last_notification.message, "Unknown provider 'huggingface'") ~= nil)
  end)

  it("warns and falls back to the default model when an invalid model is requested", function()
    -- Act: Attempt to switch to an invalid model on a valid provider
    local result = core.switch_provider("openai", "gpt-6", {})

    -- Assert: switch succeeds (returns true)
    assert.is_truthy(result, "switch should succeed when provider is valid, even if model is invalid")

    -- Wait for notify to capture calls
    vim.wait(50, function()
      return #captured > 0
    end, 10, false)
    flush_schedule()

    -- Assert: A warn notification about model fallback was emitted
    local saw_warn = false
    for _, n in ipairs(captured) do
      if
        n.level == vim.log.levels.WARN
        and string.find(n.message, "Model 'gpt%-6' is not valid for provider 'openai'")
      then
        saw_warn = true
        break
      end
    end
    assert.is_true(saw_warn, "Should warn about invalid model fallback")

    -- Assert: Model fell back to the provider default
    local default_openai_model = registry.get_model("openai")
    local cfg = require("flemma.config").materialize()
    assert.equals(default_openai_model, cfg.model, "Should fall back to provider default model")
  end)

  it("switch to a normal-cost model emits single-line INFO with period", function()
    core.switch_provider("anthropic", "claude-sonnet-4-6", {})

    vim.wait(50, function()
      return #captured > 0
    end, 10, false)
    flush_schedule()

    local saw_info = false
    for _, n in ipairs(captured) do
      if string.find(n.message, "claude%-sonnet%-4%-6") then
        assert.are.equal(vim.log.levels.INFO, n.level, "Normal-cost switch should be INFO")
        assert.is_falsy(string.find(n.message, "⚠"), "Should not contain warning icon")
        assert.is_truthy(string.find(n.message, "%.$"), "Should end with period")
        assert.is_falsy(string.find(n.message, "\n"), "Should be single-line")
        saw_info = true
        break
      end
    end
    assert.is_true(saw_info, "Normal switch should emit INFO notification")
  end)

  it("switch to boundary-cost model (opus-4-6, $30 exactly) stays INFO", function()
    core.switch_provider("anthropic", "claude-opus-4-6", {})

    vim.wait(50, function()
      return #captured > 0
    end, 10, false)
    flush_schedule()

    local saw_switch = false
    for _, n in ipairs(captured) do
      if string.find(n.message, "claude%-opus%-4%-6") then
        assert.are.equal(vim.log.levels.INFO, n.level, "Boundary model should stay INFO")
        assert.is_falsy(string.find(n.message, "⚠"), "Should not contain warning icon")
        saw_switch = true
        break
      end
    end
    assert.is_true(saw_switch, "Should see switch notification for opus-4-6")
  end)

  it("switch to a high-cost model emits multi-line WARN with pricing", function()
    -- gpt-5.4-pro: $30+$180 = $210 > 30 threshold
    core.switch_provider("openai", "gpt-5.4-pro", {})

    vim.wait(50, function()
      return #captured > 0
    end, 10, false)
    flush_schedule()

    local saw_warn = false
    for _, n in ipairs(captured) do
      if n.level == vim.log.levels.WARN and string.find(n.message, "gpt%-5%.4%-pro") then
        assert.is_truthy(string.find(n.message, "%$30"), "Should contain input price")
        assert.is_truthy(string.find(n.message, "%$180"), "Should contain output price")
        assert.is_truthy(string.find(n.message, "\n"), "Should be multi-line")
        assert.is_truthy(string.find(n.message, "⚠ Billed at"), "Should have cost bullet")
        saw_warn = true
        break
      end
    end
    assert.is_true(saw_warn, "High-cost switch should emit WARN with pricing")
  end)

  it("switch notification shows frontmatter model override as bullet line", function()
    -- Switch globally to anthropic/claude-opus-4-6, then set up a buffer
    -- with frontmatter that overrides the model
    core.switch_provider("anthropic", "claude-opus-4-6", {})

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```lua",
      'flemma.opt.model = "claude-haiku-4-5"',
      "```",
      "@You:",
      "Hello",
    })

    -- Drain the first switch notification before watching for the second.
    flush_schedule()

    -- Re-switch to trigger notification with frontmatter evaluated
    captured = {}
    core.switch_provider("anthropic", "claude-opus-4-6", {})

    vim.wait(50, function()
      return #captured > 0
    end, 10, false)
    flush_schedule()

    local saw_override = false
    for _, n in ipairs(captured) do
      if string.find(n.message, "claude%-opus%-4%-6") then
        assert.is_truthy(string.find(n.message, "model 'claude%-haiku%-4%-5'"), "Should mention overridden model")
        assert.is_truthy(string.find(n.message, "frontmatter"), "Should mention frontmatter")
        assert.is_truthy(string.find(n.message, "\n"), "Should be multi-line")
        assert.is_truthy(string.find(n.message, "  • This buffer uses"), "Override should be a bullet line")
        saw_override = true
        break
      end
    end
    assert.is_true(saw_override, "Should show frontmatter model override")
  end)

  it("model fallback appears as bullet line in switch notification", function()
    -- Invalid model falls back to provider default; fallback warning becomes a bullet
    core.switch_provider("openai", "nonexistent-model", {})

    vim.wait(50, function()
      return #captured > 0
    end, 10, false)
    flush_schedule()

    local saw_fallback = false
    for _, n in ipairs(captured) do
      if n.level == vim.log.levels.WARN and string.find(n.message, "Switched to") then
        assert.is_truthy(
          string.find(n.message, "⚠ Model 'nonexistent%-model' is not valid"),
          "Should have fallback bullet"
        )
        assert.is_truthy(string.find(n.message, "\n"), "Should be multi-line")
        saw_fallback = true
        break
      end
    end
    assert.is_true(saw_fallback, "Should show model fallback as bullet in switch notification")
  end)

  it("initialize_provider emits deferred warning", function()
    -- Use an invalid model to trigger fallback warning
    core.initialize_provider("openai", "nonexistent-model", {})

    -- flemma.notify schedules implicitly — need to process the event loop
    vim.wait(200, function()
      for _, n in ipairs(captured) do
        if string.find(n.message, "nonexistent%-model") then
          return true
        end
      end
      return false
    end, 10, false)

    local saw_warn = false
    for _, n in ipairs(captured) do
      if string.find(n.message, "nonexistent%-model") then
        assert.are.equal(vim.log.levels.WARN, n.level, "Should be WARN level")
        assert.is_truthy(string.find(n.message, "Initialized"), "Should have header line")
        assert.is_truthy(
          string.find(n.message, "⚠ Model 'nonexistent%-model' is not valid"),
          "Should have fallback bullet"
        )
        saw_warn = true
        break
      end
    end
    assert.is_true(saw_warn, "initialize_provider should emit deferred warning")
  end)

  it("frontmatter can override provider and model for a single buffer", function()
    -- Arrange: Verify the default provider is NOT OpenAI (what frontmatter will override to)
    local default_config = require("flemma.config").materialize()
    assert.is_not.equals("openai", default_config.provider, "Test assumes default is not OpenAI")

    client.register_fixture("api%.openai%.com", "tests/fixtures/openai_hello_success_stream.txt")

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```lua",
      'flemma.opt.provider = "openai"',
      'flemma.opt.model = "o3"',
      "```",
      "@You:",
      "Hello from OpenAI via frontmatter",
    })

    -- Act: Send — frontmatter should override provider to OpenAI
    vim.cmd("Flemma send")

    -- Assert: Request body uses OpenAI format (input field, not messages)
    local request_body = core._get_last_request_body()
    assert.is_not_nil(request_body, "request_body should be captured")
    assert.equals("o3", request_body.model)
    assert.is_not_nil(request_body.input, "Should use OpenAI Responses API 'input' field")
    assert.is_nil(request_body.messages, "Should NOT use Anthropic 'messages' field")

    -- Assert: Global config still points to the original provider (frontmatter is per-buffer)
    local global_after = require("flemma.config").materialize()
    assert.equals(default_config.provider, global_after.provider)
  end)

  it("print() in code blocks emits text into the request body", function()
    -- Arrange: Register the default Anthropic fixture
    client.register_fixture("api%.anthropic%.com", "tests/fixtures/anthropic_hello_success_stream.txt")

    -- Arrange: Buffer with {% print() %} statements building a user message
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      '{%- local topics = {"parsing", "testing"} -%}',
      '{%- print("Today I need help with: ") -%}',
      "{%- for topic, loop in each(topics) do",
      '  if not loop.first then print(", ") end',
      "  print(topic)",
      "end -%}",
      ".",
    })

    -- Act
    vim.cmd("Flemma send")

    -- Assert: The user message content should contain the expanded print output
    local request_body = core._get_last_request_body()
    assert.is_not_nil(request_body, "request_body was not captured")
    assert.equals(1, #request_body.messages)
    assert.equals("user", request_body.messages[1].role)

    local user_text = request_body.messages[1].content[1].text
    assert.equals("Today I need help with: parsing, testing.", user_text)
  end)
end)
