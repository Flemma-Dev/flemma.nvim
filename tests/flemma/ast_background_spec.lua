describe("background tool completed parsing", function()
  local parser

  before_each(function()
    package.loaded["flemma.parser"] = nil
    package.loaded["flemma.ast"] = nil
    parser = require("flemma.parser")
  end)

  it("parses a successful background completion block", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "**Background Tool Completed:** `bg_k7x2m`",
      "",
      "```",
      "tests/flemma/core_spec.lua: 47 passed, 0 failed",
      "```",
    })
    local doc = parser.get_parsed_document(bufnr)
    assert.equals(1, #doc.messages)
    assert.equals("You", doc.messages[1].role)
    local segment = doc.messages[1].segments[1]
    assert.equals("background_tool_completed", segment.kind)
    assert.equals("bg_k7x2m", segment.job_id)
    assert.is_nil(segment.status)
    assert.truthy(segment.content:match("47 passed"))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("parses an error background completion block", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "**Background Tool Completed:** `bg_9pfa3` (error)",
      "",
      "```",
      "Exit code 1: FAILED tests/flemma/agent_spec.lua",
      "```",
    })
    local doc = parser.get_parsed_document(bufnr)
    local segment = doc.messages[1].segments[1]
    assert.equals("background_tool_completed", segment.kind)
    assert.equals("bg_9pfa3", segment.job_id)
    assert.equals("error", segment.status)
    assert.truthy(segment.content:match("Exit code 1"))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("parses an orphan recovery block", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "**Background Tool Completed:** `bg_lost1` (error)",
      "",
      "```",
      "Background job lost: session ended before completion.",
      "```",
    })
    local doc = parser.get_parsed_document(bufnr)
    local segment = doc.messages[1].segments[1]
    assert.equals("background_tool_completed", segment.kind)
    assert.equals("bg_lost1", segment.job_id)
    assert.equals("error", segment.status)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  describe("to_generic_parts", function()
    it("converts background_tool_completed to text part with tag", function()
      local nodes = require("flemma.ast.nodes")
      local evaluated_parts = {
        nodes.background_tool_completed("bg_k7x2m", {
          content = "47 passed, 0 failed",
          start_line = 1,
          end_line = 5,
        }),
      }
      local generic_parts = nodes.to_generic_parts(evaluated_parts, "test.chat")
      assert.equals(1, #generic_parts)
      assert.equals("text", generic_parts[1].kind)
      assert.truthy(generic_parts[1].text:match("47 passed"))
      assert.equals("bg_k7x2m", generic_parts[1]._bg_job_id)
    end)
  end)
end)
