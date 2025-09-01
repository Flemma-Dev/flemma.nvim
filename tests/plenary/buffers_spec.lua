describe("claudius.parse_buffer", function()
  it("parses a buffer with frontmatter and messages correctly", function()
    -- Create a new scratch buffer
    local bufnr = vim.api.nvim_create_buf(false, true)

    local lines = {
      "```lua",
      "foo = 'bar'",
      "```",
      "@System: Be helpful.",
      "",
      "@You: Hello",
    }

    -- Set the lines in the buffer
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    local claudius = require("claudius")
    local messages, frontmatter_code = claudius.parse_buffer(bufnr)

    -- Assertions
    assert.are.equal(2, #messages, "Should parse 2 messages")

    assert.are.equal("System", messages[1].type)
    assert.are.equal("Be helpful.", messages[1].content)

    assert.are.equal("You", messages[2].type)
    assert.are.equal("Hello", messages[2].content)

    assert.are.equal("foo = 'bar'", frontmatter_code)
  end)
end)
