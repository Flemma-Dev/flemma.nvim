--- End-to-end integration test for binary tool results.
---
--- Verifies the full pipeline from a buffer containing a tool_use + tool_result
--- with a file reference (e.g. "@./tests/fixtures/sample.png;type=image/png"),
--- through the preprocessor, parser, and processor, producing a tool_result
--- part whose .parts list includes a file part with the image data.

describe("binary tool result end-to-end", function()
  local parser_mod
  local preprocessor_mod
  local processor_mod
  local state_mod
  local registry
  local tools_mod
  local ctx_mod

  before_each(function()
    -- Clear all relevant caches for full isolation
    package.loaded["flemma.parser"] = nil
    package.loaded["flemma.processor"] = nil
    package.loaded["flemma.preprocessor"] = nil
    package.loaded["flemma.preprocessor.registry"] = nil
    package.loaded["flemma.preprocessor.runner"] = nil
    package.loaded["flemma.preprocessor.context"] = nil
    package.loaded["flemma.preprocessor.rewriters.file_references"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.context"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.tools.registry"] = nil
    package.loaded["flemma.ast"] = nil
    package.loaded["flemma.ast.nodes"] = nil
    package.loaded["flemma.ast.query"] = nil

    parser_mod = require("flemma.parser")
    preprocessor_mod = require("flemma.preprocessor")
    processor_mod = require("flemma.processor")
    state_mod = require("flemma.state")
    ctx_mod = require("flemma.context")
    registry = require("flemma.tools.registry")
    tools_mod = require("flemma.tools")

    -- Set up the preprocessor hook (file_references rewriter + others)
    preprocessor_mod.setup()

    -- Set up built-in tools (registers the real read tool with template_tool_result capability)
    registry.clear()
    tools_mod.setup()
  end)

  after_each(function()
    parser_mod.set_post_parse_hook(nil)
    registry.clear()
  end)

  it("produces a file part in evaluated tool_result for an image file reference", function()
    -- Fixture: the sample.png created in Task 10 (binary PNG).
    -- The file reference in the buffer must use the @./ prefix so the
    -- file_references preprocessor rewriter (pattern @(%.%.?%/...)) picks it up.
    -- We use a path relative to the project root (cwd), which is where the buffer
    -- is anchored — get_parsed_document resolves __dirname from the buffer name.
    local cwd = vim.fn.getcwd()
    local png_fixture = cwd .. "/tests/fixtures/sample.png"
    assert.equals(1, vim.fn.filereadable(png_fixture), "sample.png fixture must exist")

    -- Build the buffer content. The tool_result fence contains a @./ file reference
    -- that the preprocessor will convert to an include() expression, which the
    -- processor will evaluate into a file part via the capture mechanism.
    local lines = {
      "@Assistant:",
      "",
      "**Tool Use:** `read` (`call_img_001`)",
      "```json",
      '{"label": "reading image", "path": "./tests/fixtures/sample.png"}',
      "```",
      "",
      "@You:",
      "",
      "**Tool Result:** `call_img_001`",
      "```",
      "@./tests/fixtures/sample.png;type=image/png",
      "```",
    }

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.getcwd() .. "/test_binary_integration.chat")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    -- get_parsed_document runs through the post-parse hook (file_references rewriter)
    local doc = parser_mod.get_parsed_document(bufnr)

    -- Verify the parser + preprocessor produced segments inside the tool_result
    assert.equals(2, #doc.messages, "expected @Assistant + @You messages")
    local you_msg = doc.messages[2]
    assert.equals("You", you_msg.role)
    assert.equals(1, #you_msg.segments, "expected exactly one tool_result segment in @You")
    local tr_seg = you_msg.segments[1]
    assert.equals("tool_result", tr_seg.kind)
    assert.equals("call_img_001", tr_seg.tool_use_id)

    -- The preprocessor should have converted @./path;type=image/png → expression segment
    local has_expression = false
    for _, child in ipairs(tr_seg.segments or {}) do
      if child.kind == "expression" then
        has_expression = true
        break
      end
    end
    assert.is_true(has_expression, "preprocessor should have converted file reference to expression in tool_result")

    -- Evaluate through the processor (which uses the capability-gated capture mechanism)
    local base = ctx_mod.from_buffer(bufnr)
    local result = processor_mod.evaluate(doc, base, { bufnr = bufnr })

    -- Find the tool_result part in the evaluated @You message
    assert.equals(2, #result.messages, "expected two evaluated messages")
    local eval_you = result.messages[2]
    assert.equals("You", eval_you.role)

    local tr_part = nil
    for _, part in ipairs(eval_you.parts) do
      if part.kind == "tool_result" then
        tr_part = part
        break
      end
    end
    assert.is_not_nil(tr_part, "tool_result part should be present in evaluated @You message")
    assert.equals("call_img_001", tr_part.tool_use_id)

    -- The read tool has template_tool_result capability → .parts should be populated
    assert.is_table(tr_part.parts, "tool_result should have .parts from capture mechanism")
    assert.is_true(#tr_part.parts > 0, "tool_result .parts should be non-empty")

    -- At least one part should be a file part with image/png mime type
    local file_part = nil
    for _, p in ipairs(tr_part.parts) do
      if p.kind == "file" and p.mime_type and p.mime_type:match("image/") then
        file_part = p
        break
      end
    end
    assert.is_not_nil(file_part, "expected a file part with image/ mime type in tool_result .parts")
    assert.equals("image/png", file_part.mime_type)
    assert.is_string(file_part.data, "file part should carry raw binary data")
    assert.is_true(#file_part.data > 0, "file part data should be non-empty")

    state_mod.cleanup_buffer_state(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("collapses tool_result to content string for tools without the capability", function()
    -- Register a plain tool without template_tool_result capability
    registry.register("plain_fetch", {
      name = "plain_fetch",
      description = "A tool without binary capability",
      input_schema = { type = "object", properties = {} },
      -- No capabilities field
    })

    local lines = {
      "@Assistant:",
      "",
      "**Tool Use:** `plain_fetch` (`call_plain_001`)",
      "```json",
      '{"label": "test"}',
      "```",
      "",
      "@You:",
      "",
      "**Tool Result:** `call_plain_001`",
      "```",
      "@./tests/fixtures/sample.png;type=image/png",
      "```",
    }

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.getcwd() .. "/test_binary_plain_fallback.chat")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    local doc = parser_mod.get_parsed_document(bufnr)

    local base = ctx_mod.from_buffer(bufnr)
    local result = processor_mod.evaluate(doc, base, { bufnr = bufnr })

    assert.equals(2, #result.messages)
    local eval_you = result.messages[2]

    local tr_part = nil
    for _, part in ipairs(eval_you.parts) do
      if part.kind == "tool_result" then
        tr_part = part
        break
      end
    end
    assert.is_not_nil(tr_part, "tool_result part should be present")
    assert.equals("call_plain_001", tr_part.tool_use_id)

    -- Without the capability, .parts should NOT be populated
    assert.is_nil(tr_part.parts, "plain tool should not have .parts — no capability")
    -- The content string should be present as fallback
    assert.is_string(tr_part.content, "plain tool result should have content string")

    state_mod.cleanup_buffer_state(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
