describe("claudius.parse_buffer", function()
  it("parses a buffer with frontmatter and messages correctly", function()
    local spy = require("luassert.spy")
    spy.on(vim.api, "nvim_buf_get_lines")

    local lines = {
      "```lua",
      "foo = 'bar'",
      "```",
      "@System: Be helpful.",
      "",
      "@You: Hello",
    }

    vim.api.nvim_buf_get_lines:returns(lines)

    local claudius = require("claudius")
    local messages, frontmatter_code = claudius.parse_buffer(1)

    -- Assertions
    assert.are.equal(2, #messages, "Should parse 2 messages")

    assert.are.equal("System", messages[1].type)
    assert.are.equal("Be helpful.", messages[1].content)

    assert.are.equal("You", messages[2].type)
    assert.are.equal("Hello", messages[2].content)

    assert.are.equal("foo = 'bar'", frontmatter_code)

    spy.restore()
  end)
end)
