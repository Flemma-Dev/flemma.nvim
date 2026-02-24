local ast = require("flemma.ast")
local ctx = require("flemma.context")
local parser = require("flemma.parser")
local pipeline = require("flemma.pipeline")

local ABORT_COMMENT = "<!-- flemma:aborted: Response interrupted by the user. -->"
local ABORT_MESSAGE = "Response interrupted by the user."
local ABORT_LLM_TEXT = "<!-- " .. ABORT_MESSAGE .. " -->"

describe("Aborted response handling", function()
  describe("parser", function()
    it("recognizes flemma:aborted comment as AbortedSegment with message", function()
      local lines = {
        "@Assistant: Hello",
        ABORT_COMMENT,
      }
      local doc = parser.parse_lines(lines)
      assert.equals(1, #doc.messages)
      local msg = doc.messages[1]
      assert.equals("Assistant", msg.role)

      local found = false
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "aborted" then
          found = true
          assert.equals(ABORT_MESSAGE, seg.message)
          assert.equals(2, seg.position.start_line)
          break
        end
      end
      assert.is_true(found, "Expected an AbortedSegment in the parsed message")
    end)

    it("captures custom abort message", function()
      local lines = {
        "@Assistant: Hello",
        "<!-- flemma:aborted: Custom abort reason here. -->",
      }
      local doc = parser.parse_lines(lines)
      local msg = doc.messages[1]
      local found = false
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "aborted" then
          found = true
          assert.equals("Custom abort reason here.", seg.message)
          break
        end
      end
      assert.is_true(found, "Expected AbortedSegment with custom message")
    end)

    it("trims whitespace around the message", function()
      local lines = {
        "@Assistant: Hello",
        "<!--  flemma:aborted:   Some message   -->",
      }
      local doc = parser.parse_lines(lines)
      local msg = doc.messages[1]
      local found = false
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "aborted" then
          found = true
          assert.equals("Some message", seg.message)
          break
        end
      end
      assert.is_true(found, "Expected AbortedSegment with trimmed message")
    end)

    it("does not recognize abort comment in @You: messages", function()
      local lines = {
        "@You: " .. ABORT_COMMENT,
      }
      local doc = parser.parse_lines(lines)
      local msg = doc.messages[1]
      for _, seg in ipairs(msg.segments) do
        assert.is_not.equals("aborted", seg.kind)
      end
    end)

    it("parses flemma:tool status=aborted fence correctly", function()
      local lines = {
        "@Assistant: Hello",
        "**Tool Use:** `bash` (`tool_123`)",
        "",
        "```json",
        '{"command": "ls"}',
        "```",
        "@You: **Tool Result:** `tool_123`",
        "",
        "```flemma:tool status=aborted",
        "```",
      }
      local doc = parser.parse_lines(lines)
      local you_msg = doc.messages[2]
      assert.equals("You", you_msg.role)
      local tool_result = nil
      for _, seg in ipairs(you_msg.segments) do
        if seg.kind == "tool_result" then
          tool_result = seg
          break
        end
      end
      assert.is_not_nil(tool_result)
      assert.equals("aborted", tool_result.status)
    end)
  end)

  describe("tool context", function()
    before_each(function()
      package.loaded["flemma.tools.context"] = nil
      package.loaded["flemma.parser"] = nil
    end)

    it("resolve_all_pending returns aborted=true with message for aborted messages", function()
      local tool_context = require("flemma.tools.context")
      local test_parser = require("flemma.parser")

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant: Let me help",
        "**Tool Use:** `bash` (`tool_abc`)",
        "",
        "```json",
        '{"command": "ls"}',
        "```",
        ABORT_COMMENT,
      })

      test_parser.get_parsed_document(bufnr)

      local pending = tool_context.resolve_all_pending(bufnr)
      assert.equals(1, #pending)
      assert.equals("tool_abc", pending[1].tool_id)
      assert.is_true(pending[1].aborted)
      assert.equals(ABORT_MESSAGE, pending[1].aborted_message)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("resolve_all_pending returns aborted=nil for tool_use in normal messages", function()
      local tool_context = require("flemma.tools.context")
      local test_parser = require("flemma.parser")

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant: Let me help",
        "**Tool Use:** `bash` (`tool_def`)",
        "",
        "```json",
        '{"command": "ls"}',
        "```",
      })

      test_parser.get_parsed_document(bufnr)

      local pending = tool_context.resolve_all_pending(bufnr)
      assert.equals(1, #pending)
      assert.equals("tool_def", pending[1].tool_id)
      assert.is_nil(pending[1].aborted)
      assert.is_nil(pending[1].aborted_message)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("marks all tool_use blocks as aborted when message has multiple tool calls", function()
      local tool_context = require("flemma.tools.context")
      local test_parser = require("flemma.parser")

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant: Let me do two things",
        "**Tool Use:** `bash` (`tool_1`)",
        "",
        "```json",
        '{"command": "ls"}',
        "```",
        "**Tool Use:** `bash` (`tool_2`)",
        "",
        "```json",
        '{"command": "pwd"}',
        "```",
        ABORT_COMMENT,
      })

      test_parser.get_parsed_document(bufnr)

      local pending = tool_context.resolve_all_pending(bufnr)
      assert.equals(2, #pending)
      for _, p in ipairs(pending) do
        assert.is_true(p.aborted, "Expected tool " .. p.tool_id .. " to be aborted")
        assert.equals(ABORT_MESSAGE, p.aborted_message)
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("does not mark tools as aborted when abort marker is not trailing", function()
      local tool_context = require("flemma.tools.context")
      local test_parser = require("flemma.parser")

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant: Let me help",
        "**Tool Use:** `bash` (`tool_mid`)",
        "",
        "```json",
        '{"command": "ls"}',
        "```",
        ABORT_COMMENT,
        "Some text after the abort marker",
      })

      test_parser.get_parsed_document(bufnr)

      local pending = tool_context.resolve_all_pending(bufnr)
      assert.equals(1, #pending)
      assert.is_nil(pending[1].aborted)
      assert.is_nil(pending[1].aborted_message)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("handles trailing blank lines after abort marker", function()
      local tool_context = require("flemma.tools.context")
      local test_parser = require("flemma.parser")

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant: Let me help",
        "**Tool Use:** `bash` (`tool_trail`)",
        "",
        "```json",
        '{"command": "ls"}',
        "```",
        ABORT_COMMENT,
        "",
      })

      test_parser.get_parsed_document(bufnr)

      local pending = tool_context.resolve_all_pending(bufnr)
      assert.equals(1, #pending)
      assert.is_true(pending[1].aborted)
      assert.equals(ABORT_MESSAGE, pending[1].aborted_message)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("processor", function()
    it("emits aborted segment as aborted part with message", function()
      local processor = require("flemma.processor")
      local doc = parser.parse_lines({
        "@Assistant: Hello",
        ABORT_COMMENT,
      })

      local result = processor.evaluate(doc, nil)
      local assistant_parts = result.messages[1].parts

      local found = false
      for _, part in ipairs(assistant_parts) do
        if part.kind == "aborted" then
          found = true
          assert.equals(ABORT_MESSAGE, part.message)
          break
        end
      end
      assert.is_true(found, "Expected aborted part in processor output")
    end)

    it("preserves custom message through processor", function()
      local processor = require("flemma.processor")
      local doc = parser.parse_lines({
        "@Assistant: Hello",
        "<!-- flemma:aborted: My custom abort reason. -->",
      })

      local result = processor.evaluate(doc, nil)
      local assistant_parts = result.messages[1].parts

      local found = false
      for _, part in ipairs(assistant_parts) do
        if part.kind == "aborted" then
          found = true
          assert.equals("My custom abort reason.", part.message)
          break
        end
      end
      assert.is_true(found, "Expected aborted part with custom message in processor output")
    end)
  end)

  describe("pipeline", function()
    it("strips abort marker from historical assistant messages", function()
      local doc = parser.parse_lines({
        "@Assistant: First response",
        ABORT_COMMENT,
        "@You: Thanks",
        "@Assistant: Second response",
        ABORT_COMMENT,
      })
      local base_context = ctx.from_file("/tmp/test.chat")
      local prompt = pipeline.run(doc, base_context)

      -- First assistant message (historical) should NOT have abort marker
      local first_assistant = prompt.history[1]
      assert.equals("assistant", first_assistant.role)
      for _, part in ipairs(first_assistant.parts) do
        if part.kind == "text" then
          assert.is_not.equals(ABORT_LLM_TEXT, part.text, "Historical message should have abort marker stripped")
        end
      end

      -- Last assistant message (text-only) should retain abort marker as text
      local last_assistant = prompt.history[3]
      assert.equals("assistant", last_assistant.role)
      local found = false
      for _, part in ipairs(last_assistant.parts) do
        if part.kind == "text" and part.text == ABORT_LLM_TEXT then
          found = true
          break
        end
      end
      assert.is_true(found, "Expected abort marker preserved on last assistant message")
    end)

    it("preserves abort marker when only one assistant message", function()
      local doc = parser.parse_lines({
        "@Assistant: Only response",
        ABORT_COMMENT,
      })
      local base_context = ctx.from_file("/tmp/test.chat")
      local prompt = pipeline.run(doc, base_context)

      local assistant = prompt.history[1]
      assert.equals("assistant", assistant.role)
      local found = false
      for _, part in ipairs(assistant.parts) do
        if part.kind == "text" and part.text == ABORT_LLM_TEXT then
          found = true
          break
        end
      end
      assert.is_true(found, "Expected abort marker preserved on single assistant message")
    end)

    it("strips abort marker when followed by user and another assistant", function()
      local doc = parser.parse_lines({
        "@Assistant: First",
        ABORT_COMMENT,
        "@You: Continue",
        "@Assistant: Second",
        ABORT_COMMENT,
      })
      local base_context = ctx.from_file("/tmp/test.chat")
      local prompt = pipeline.run(doc, base_context)

      -- First assistant (index 1): should be stripped
      local first = prompt.history[1]
      for _, part in ipairs(first.parts) do
        if part.kind == "text" then
          assert.is_not.equals(ABORT_LLM_TEXT, part.text, "Historical message should have abort marker stripped")
        end
      end

      -- Last assistant (index 3): text-only, should be preserved
      local last = prompt.history[3]
      local found = false
      for _, part in ipairs(last.parts) do
        if part.kind == "text" and part.text == ABORT_LLM_TEXT then
          found = true
          break
        end
      end
      assert.is_true(found, "Expected abort marker on last text-only assistant")
    end)

    it("strips abort marker from last assistant when it contains tool_use", function()
      local doc = parser.parse_lines({
        "@Assistant: Let me help",
        "**Tool Use:** `bash` (`tool_abc`)",
        "",
        "```json",
        '{"command": "ls"}',
        "```",
        ABORT_COMMENT,
        "@You: **Tool Result:** `tool_abc`",
        "",
        "```",
        ABORT_MESSAGE,
        "```",
      })
      local base_context = ctx.from_file("/tmp/test.chat")
      local prompt = pipeline.run(doc, base_context)

      -- Assistant message has tool_use → abort marker must be stripped
      local assistant = prompt.history[1]
      assert.equals("assistant", assistant.role)
      for _, part in ipairs(assistant.parts) do
        if part.kind == "text" then
          assert.is_not.equals(
            ABORT_LLM_TEXT,
            part.text,
            "Abort marker should be stripped from assistant with tool_use"
          )
        end
      end
    end)
  end)

  describe("AST", function()
    it("creates aborted segment with message and position", function()
      local seg = ast.aborted("Test message", { start_line = 5, end_line = 5 })
      assert.equals("aborted", seg.kind)
      assert.equals("Test message", seg.message)
      assert.equals(5, seg.position.start_line)
      assert.equals(5, seg.position.end_line)
    end)
  end)

  describe("regression", function()
    it("non-aborted tool_use flows through normal approval path", function()
      local tool_context = require("flemma.tools.context")

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant: Let me help",
        "**Tool Use:** `bash` (`tool_normal`)",
        "",
        "```json",
        '{"command": "echo hello"}',
        "```",
        "Some trailing text",
      })

      require("flemma.parser").get_parsed_document(bufnr)

      local pending = tool_context.resolve_all_pending(bufnr)
      assert.equals(1, #pending)
      assert.is_nil(pending[1].aborted)
      assert.is_nil(pending[1].aborted_message)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
