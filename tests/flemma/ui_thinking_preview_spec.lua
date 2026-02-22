describe("thinking preview with leading whitespace content", function()
  local client = require("flemma.client")
  local flemma

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.core.config.manager"] = nil
    package.loaded["flemma.provider.registry"] = nil
    package.loaded["flemma.models"] = nil

    flemma = require("flemma")

    flemma.setup({ parameters = { thinking = false } })
  end)

  after_each(function()
    client.clear_fixtures()
    vim.cmd("silent! %bdelete!")
  end)

  it("discards whitespace-only content that arrives before thinking starts", function()
    -- Arrange: Register a fixture that simulates Opus 4.6 behavior:
    -- a whitespace-only text block ("\n\n"), then thinking, then actual text
    client.register_fixture("api%.anthropic%.com", "tests/fixtures/anthropic_whitespace_before_thinking_stream.txt")

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You: Hello" })

    -- Act
    vim.cmd("Flemma send")

    -- Wait for the full response to be processed
    vim.wait(2000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for _, line in ipairs(lines) do
        if line == "@You: " then
          return true
        end
      end
      return false
    end)

    -- Assert: The response should have the text on the @Assistant: line,
    -- NOT separated by blank lines from a whitespace-only text block
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Find the @Assistant line
    local assistant_line_idx = nil
    for i, line in ipairs(lines) do
      if line:match("^@Assistant:") then
        assistant_line_idx = i
        break
      end
    end

    assert.is_not_nil(assistant_line_idx, "Should have an @Assistant: line")
    assert.equals(
      "@Assistant: Here is the answer.",
      lines[assistant_line_idx],
      "Response text should be on the @Assistant: line, not separated by whitespace-only content"
    )
  end)
end)
