describe("flemma.parse_buffer", function()
  it("parses a buffer with frontmatter and messages correctly", function()
    local bufnr = vim.api.nvim_create_buf(false, false)

    local lines = {
      "```lua",
      "foo = 'bar'",
      "```",
      "@System: Be helpful.",
      "",
      "@You: Hello",
    }

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    local flemma = require("flemma")
    local context = require("flemma.context").from_file("test.chat")
    local messages, frontmatter_code, fm_context = require("flemma.buffers").parse_buffer(bufnr, context)

    assert.are.equal(2, #messages, "Should parse 2 messages")

    assert.are.equal("System", messages[1].type)
    assert.are.equal("Be helpful.", messages[1].content)

    assert.are.equal("You", messages[2].type)
    assert.are.equal("Hello", messages[2].content)

    assert.are.equal("foo = 'bar'", frontmatter_code)
    assert.are.equal("bar", fm_context.foo)
  end)

  it("does not execute frontmatter during UI update", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.bo[bufnr].filetype = "chat"

    local lines = {
      "```lua",
      "this is a syntax error!!!",
      "```",
      "@System: Be helpful.",
      "@You: Hello",
    }

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    local ui = require("flemma.ui")
    assert.has_no_errors(function()
      ui.update_ui(bufnr)
    end, "UI update should not execute frontmatter with syntax error")
  end)

  it("does execute frontmatter during parse_buffer and reports syntax errors", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.bo[bufnr].filetype = "chat"

    local lines = {
      "```lua",
      "this is a syntax error!!!",
      "```",
      "@System: Be helpful.",
      "@You: Hello",
    }

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    local context = require("flemma.context").from_file("test.chat")
    -- Should not error, but should return cloned context (with no user vars) and notify user
    local messages, fm_code, fm_context = require("flemma.buffers").parse_buffer(bufnr, context)
    assert.are.equal(2, #messages)
    assert.is_not_nil(fm_code)
    -- fm_context should still have __filename from cloned context
    assert.are.equal("test.chat", fm_context.__filename)
  end)
end)
