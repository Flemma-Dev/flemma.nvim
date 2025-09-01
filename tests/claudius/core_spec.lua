describe(":ClaudiusSend command", function()
  local base_provider_module = require("claudius.provider.base")
  local original_send_request

  -- Variable to capture the request body from the mock
  local captured_request_body

  before_each(function()
    -- Reset captured data for each test
    captured_request_body = nil

    -- Store the original function
    original_send_request = base_provider_module.send_request

    -- Mock the send_request function to capture its arguments and prevent network calls
    base_provider_module.send_request = function(_, request_body, _)
      captured_request_body = request_body
      return 1 -- Return a dummy job_id to satisfy the caller
    end

    -- Invalidate the main claudius module cache to ensure a clean setup for each test
    package.loaded["claudius"] = nil
    local claudius = require("claudius")
    -- Setup with default configuration. Specific tests can override this.
    claudius.setup({})
  end)

  after_each(function()
    -- Restore the original send_request function
    base_provider_module.send_request = original_send_request
    original_send_request = nil

    -- Clean up any buffers created during the test
    vim.cmd("silent! %bdelete!")
  end)

  it("formats the request body correctly for the default Claude provider", function()
    -- Arrange: The default provider is Claude. We just need to set up the buffer.
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@System: Be brief.", "@You: Hello" })

    -- Act: Execute the ClaudiusSend command
    vim.cmd("ClaudiusSend")

    -- Assert: Check that the captured request body matches the expected format for Claude
    assert.is_not_nil(captured_request_body, "send_request was not called")

    local claudius = require("claudius")
    local config = claudius._get_config()
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
    claudius.switch("openai", "gpt-4o", {})

    -- Arrange: Create a new buffer, make it current, and set its content
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You: Hello" })

    -- Act: Execute the ClaudiusSend command
    vim.cmd("ClaudiusSend")

    -- Assert: Check that the captured request body matches the expected format for OpenAI
    assert.is_not_nil(captured_request_body, "send_request was not called")

    local claudius = require("claudius")
    local config = claudius._get_config()

    local expected_body = {
      model = "gpt-4o",
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
end)
