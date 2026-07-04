--- Merged AST/parser specs.
--- Each former spec file is nested under a labeled describe() block so its
--- file-local requires and helpers keep an isolated scope while the suite
--- runs in a single Neovim instance.

describe("ast.dump", function()
  describe("flemma.ast.dump", function()
    local dump
    local nodes
    local display

    before_each(function()
      package.loaded["flemma.ast.dump"] = nil
      package.loaded["flemma.ast.nodes"] = nil
      package.loaded["flemma.utilities.display"] = nil
      dump = require("flemma.ast.dump")
      nodes = require("flemma.ast.nodes")
      display = require("flemma.utilities.display")
    end)

    describe("position formatting", function()
      it("formats lines-only position", function()
        local seg = nodes.aborted("cancelled", { start_line = 5, end_line = 20 })
        local lines = dump.tree(seg)
        assert.is_truthy(lines[1]:find("%[5 %- 20%]"))
      end)

      it("formats position with columns", function()
        local seg = nodes.expression("x", { start_line = 7, end_line = 7, start_col = 12, end_col = 28 })
        local lines = dump.tree(seg)
        assert.is_truthy(lines[1]:find("%[7:12 %- 7:28%]"))
      end)

      it("omits position bracket when position is nil", function()
        local seg = nodes.text("hello")
        local lines = dump.tree(seg)
        assert.equals("text", lines[1])
      end)

      it("formats single-line position without columns", function()
        local seg = nodes.aborted("err", { start_line = 3 })
        local lines = dump.tree(seg)
        assert.is_truthy(lines[1]:find("%[3%]"))
      end)
    end)

    describe("segment rendering", function()
      it("renders text segment with multiline value", function()
        local seg = nodes.text("Hello\nWorld!", { start_line = 5, end_line = 6 })
        local lines = dump.tree(seg)
        assert.equals("text [5 - 6]", lines[1])
        assert.equals("  value:", lines[2])
        assert.equals("    Hello↵", lines[3])
        assert.equals("    World!", lines[4])
      end)

      it("renders expression segment with multiline code", function()
        local seg = nodes.expression("os.date()", { start_line = 7, end_line = 7, start_col = 12, end_col = 28 })
        local lines = dump.tree(seg)
        assert.equals("expression [7:12 - 7:28]", lines[1])
        assert.equals("  code:", lines[2])
        assert.equals("    os.date()", lines[3])
        assert.equals(3, #lines)
      end)

      it("renders thinking segment with redacted and signature", function()
        local seg = nodes.thinking("Let me think...", { start_line = 10, end_line = 15 }, {
          redacted = false,
          signature = { value = "base64data", provider = "anthropic" },
        })
        local lines = dump.tree(seg)
        assert.is_truthy(lines[1]:find("redacted=false"))
        assert.is_truthy(lines[1]:find('signature.provider="anthropic"'))
        assert.is_falsy(lines[1]:find("base64data"))
        assert.equals("  content:", lines[2])
        assert.equals("    Let me think...", lines[3])
      end)

      it("renders tool_use segment with JSON input", function()
        local seg = nodes.tool_use("call_123", "bash", { command = "ls" }, { start_line = 20, end_line = 25 })
        local lines = dump.tree(seg)
        assert.is_truthy(lines[1]:find('name="bash"'))
        assert.is_truthy(lines[1]:find('id="call_123"'))
        assert.equals("  input:", lines[2])
        local json_block = table.concat(lines, "\n", 3)
        assert.is_truthy(json_block:find('"command"'))
        assert.is_truthy(json_block:find('"ls"'))
      end)

      it("renders tool_result segment with status", function()
        local seg = nodes.tool_result("call_123", {
          content = "file contents here",
          status = "approved",
          start_line = 9,
          end_line = 20,
        })
        local lines = dump.tree(seg)
        assert.is_truthy(lines[1]:find('tool_use_id="call_123"'))
        assert.is_truthy(lines[1]:find('status="approved"'))
        assert.equals("  content:", lines[2])
        assert.equals("    file contents here", lines[3])
      end)

      it("renders aborted segment with inline message", function()
        local seg = nodes.aborted("User cancelled", { start_line = 46, end_line = 47 })
        local lines = dump.tree(seg)
        assert.equals('aborted [46 - 47] message="User cancelled"', lines[1])
        assert.equals(1, #lines)
      end)

      it("renders frontmatter with multiline code", function()
        local fm = nodes.frontmatter("lua", "vim.g.x = true\nvim.g.y = false", { start_line = 1, end_line = 3 })
        local lines = dump.tree(fm)
        assert.equals('frontmatter [1 - 3] language="lua"', lines[1])
        assert.equals("  code:", lines[2])
        assert.equals("    vim.g.x = true↵", lines[3])
        assert.equals("    vim.g.y = false", lines[4])
      end)

      it("visualizes leading and trailing whitespace", function()
        local lead = display.get_lead_char()
        local trail = display.get_trail_char()
        local seg = nodes.expression(" include('foo') ", { start_line = 5, end_line = 5, start_col = 1, end_col = 17 })
        local lines = dump.tree(seg)
        assert.equals("expression [5:1 - 5:17]", lines[1])
        assert.equals("  code:", lines[2])
        assert.equals("    " .. lead .. "include('foo')" .. trail, lines[3])
      end)

      it("visualizes whitespace-only content", function()
        local trail = display.get_trail_char()
        local seg = nodes.text("  ", { start_line = 5, end_line = 5 })
        local lines = dump.tree(seg)
        assert.equals("  value:", lines[2])
        assert.equals("    " .. trail .. trail, lines[3])
      end)
    end)

    describe("depth limiting", function()
      it("summarizes children at depth=1 for message", function()
        local msg = nodes.message("You", {
          nodes.text("hello", { start_line = 2, end_line = 2 }),
          nodes.expression("x", { start_line = 2, end_line = 2, start_col = 8, end_col = 14 }),
          nodes.text("world", { start_line = 3, end_line = 3 }),
        }, { start_line = 1, end_line = 3 })
        local lines = dump.tree(msg, { depth = 1 })
        assert.equals('message [1 - 3] role="You"', lines[1])
        assert.equals("  segments: 3 children (text, expression, text)", lines[2])
        assert.equals(2, #lines)
      end)

      it("summarizes children at depth=1 for document", function()
        local doc = nodes.document(nodes.frontmatter("yaml", "model: claude", { start_line = 1, end_line = 3 }), {
          nodes.message("You", {}, { start_line = 4, end_line = 5 }),
          nodes.message("Assistant", {}, { start_line = 6, end_line = 10 }),
        }, {}, { start_line = 1, end_line = 10 })
        local lines = dump.tree(doc, { depth = 1 })
        assert.equals("document [1 - 10]", lines[1])
        assert.equals("  frontmatter: 1 child", lines[2])
        assert.equals("  messages: 2 children (You, Assistant)", lines[3])
        assert.equals(3, #lines)
      end)
    end)

    describe("full document dump", function()
      it("renders nested document with all levels", function()
        local doc = nodes.document(nodes.frontmatter("lua", "x = 1", { start_line = 1, end_line = 3 }), {
          nodes.message("You", {
            nodes.text("Hello", { start_line = 5, end_line = 5 }),
          }, { start_line = 4, end_line = 5 }),
          nodes.message("Assistant", {
            nodes.text("Hi there", { start_line = 7, end_line = 7 }),
          }, { start_line = 6, end_line = 7 }),
        }, {}, { start_line = 1, end_line = 7 })
        local lines = dump.tree(doc)
        assert.equals("document [1 - 7]", lines[1])
        assert.equals('  frontmatter [1 - 3] language="lua"', lines[2])
        assert.equals("    code:", lines[3])
        assert.equals("      x = 1", lines[4])
        assert.equals('  message [4 - 5] role="You"', lines[5])
        assert.equals("    text [5]", lines[6])
        assert.equals("      value:", lines[7])
        assert.equals("        Hello", lines[8])
        assert.equals('  message [6 - 7] role="Assistant"', lines[9])
        assert.equals("    text [7]", lines[10])
        assert.equals("      value:", lines[11])
        assert.equals("        Hi there", lines[12])
      end)
    end)

    describe("diff scenario", function()
      it("shows structural differences between raw and rewritten ASTs", function()
        local raw = nodes.document(nil, {
          nodes.message("You", {
            nodes.text("See @./file.txt for details", { start_line = 2, end_line = 2 }),
          }, { start_line = 1, end_line = 2 }),
        }, {}, { start_line = 1, end_line = 2 })

        local rewritten = nodes.document(nil, {
          nodes.message("You", {
            nodes.text("See ", { start_line = 2, end_line = 2 }),
            nodes.expression("include('./file.txt')", { start_line = 2, end_line = 2, start_col = 5, end_col = 19 }),
            nodes.text(" for details", { start_line = 2, end_line = 2 }),
          }, { start_line = 1, end_line = 2 }),
        }, {}, { start_line = 1, end_line = 2 })

        local raw_lines = dump.tree(raw)
        local rewritten_lines = dump.tree(rewritten)

        local raw_text = table.concat(raw_lines, "\n")
        local rewritten_text = table.concat(rewritten_lines, "\n")

        assert.are_not.equal(raw_text, rewritten_text)
        assert.is_truthy(raw_text:find("See @./file.txt for details"))
        assert.is_truthy(rewritten_text:find("expression"))
        assert.is_truthy(rewritten_text:find("include"))
        assert.is_falsy(rewritten_text:find("See @./file.txt for details"))
      end)
    end)
  end)
end)

describe("ast.query", function()
  local ast = require("flemma.ast")
  local parser = require("flemma.parser")

  describe("ast.query", function()
    before_each(function()
      package.loaded["flemma.ast"] = nil
      package.loaded["flemma.ast.query"] = nil
      package.loaded["flemma.ast.nodes"] = nil
      package.loaded["flemma.parser"] = nil
      package.loaded["flemma.state"] = nil
      package.loaded["flemma.preprocessor"] = nil
      package.loaded["flemma.preprocessor.registry"] = nil
      package.loaded["flemma.preprocessor.runner"] = nil
      package.loaded["flemma.preprocessor.context"] = nil
      package.loaded["flemma.utilities.encoding"] = nil
      package.loaded["flemma.preprocessor.rewriters.file_references"] = nil
      ast = require("flemma.ast")
      parser = require("flemma.parser")
    end)

    describe("find_tool_sibling", function()
      it("returns tool_result for a tool_use segment", function()
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `bash` (`call_001`)",
          "```json",
          '{"command": "ls"}',
          "```",
          "@You:",
          "**Tool Result:** `call_001`",
          "",
          "```",
          "file1.txt",
          "```",
        })

        -- Find the tool_use segment
        local tool_use = nil
        for _, msg in ipairs(doc.messages) do
          for _, seg in ipairs(msg.segments) do
            if seg.kind == "tool_use" then
              tool_use = seg
            end
          end
        end
        assert.is_not_nil(tool_use)

        local counterpart, counterpart_msg = ast.find_tool_sibling(doc, tool_use)
        assert.is_not_nil(counterpart)
        assert.equals("tool_result", counterpart.kind)
        assert.equals("call_001", counterpart.tool_use_id)
        assert.is_not_nil(counterpart_msg)
        assert.equals("You", counterpart_msg.role)
      end)

      it("returns tool_use for a tool_result segment", function()
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `read` (`call_002`)",
          "```json",
          '{"path": "/tmp/a.txt"}',
          "```",
          "@You:",
          "**Tool Result:** `call_002`",
          "",
          "```",
          "contents",
          "```",
        })

        local tool_result = nil
        for _, msg in ipairs(doc.messages) do
          for _, seg in ipairs(msg.segments) do
            if seg.kind == "tool_result" then
              tool_result = seg
            end
          end
        end
        assert.is_not_nil(tool_result)

        local counterpart, counterpart_msg = ast.find_tool_sibling(doc, tool_result)
        assert.is_not_nil(counterpart)
        assert.equals("tool_use", counterpart.kind)
        assert.equals("call_002", counterpart.id)
        assert.is_not_nil(counterpart_msg)
        assert.equals("Assistant", counterpart_msg.role)
      end)

      it("returns nil for tool_use without result", function()
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `bash` (`call_003`)",
          "```json",
          '{"command": "pwd"}',
          "```",
        })

        local tool_use = nil
        for _, msg in ipairs(doc.messages) do
          for _, seg in ipairs(msg.segments) do
            if seg.kind == "tool_use" then
              tool_use = seg
            end
          end
        end
        assert.is_not_nil(tool_use)

        local counterpart, counterpart_msg = ast.find_tool_sibling(doc, tool_use)
        assert.is_nil(counterpart)
        assert.is_nil(counterpart_msg)
      end)

      it("returns nil for orphan tool_result", function()
        local doc = parser.parse_lines({
          "@You:",
          "**Tool Result:** `call_orphan`",
          "",
          "```",
          "data",
          "```",
        })

        local tool_result = nil
        for _, msg in ipairs(doc.messages) do
          for _, seg in ipairs(msg.segments) do
            if seg.kind == "tool_result" then
              tool_result = seg
            end
          end
        end
        assert.is_not_nil(tool_result)

        local counterpart, counterpart_msg = ast.find_tool_sibling(doc, tool_result)
        assert.is_nil(counterpart)
        assert.is_nil(counterpart_msg)
      end)

      it("handles multiple tool pairs", function()
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `bash` (`call_a`)",
          "```json",
          '{"command": "ls"}',
          "```",
          "**Tool Use:** `read` (`call_b`)",
          "```json",
          '{"path": "/tmp"}',
          "```",
          "@You:",
          "**Tool Result:** `call_a`",
          "",
          "```",
          "result_a",
          "```",
          "**Tool Result:** `call_b`",
          "",
          "```",
          "result_b",
          "```",
        })

        -- Find call_b tool_use
        local tool_use_b = nil
        for _, msg in ipairs(doc.messages) do
          for _, seg in ipairs(msg.segments) do
            if seg.kind == "tool_use" and seg.id == "call_b" then
              tool_use_b = seg
            end
          end
        end
        assert.is_not_nil(tool_use_b)

        local counterpart = ast.find_tool_sibling(doc, tool_use_b)
        assert.is_not_nil(counterpart)
        assert.equals("tool_result", counterpart.kind)
        assert.equals("call_b", counterpart.tool_use_id)
      end)

      it("returns first match for duplicate tool_result", function()
        -- Simulate re-execution: two tool_results for same tool_use_id
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `bash` (`call_dup`)",
          "```json",
          '{"command": "echo hi"}',
          "```",
          "@You:",
          "**Tool Result:** `call_dup`",
          "",
          "```",
          "first_result",
          "```",
          "**Tool Result:** `call_dup`",
          "",
          "```",
          "second_result",
          "```",
        })

        local tool_use = nil
        for _, msg in ipairs(doc.messages) do
          for _, seg in ipairs(msg.segments) do
            if seg.kind == "tool_use" then
              tool_use = seg
            end
          end
        end
        assert.is_not_nil(tool_use)

        local counterpart = ast.find_tool_sibling(doc, tool_use)
        assert.is_not_nil(counterpart)
        assert.equals("first_result", counterpart.content)
      end)

      it("works with intermediate status tool_result", function()
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `bash` (`call_pending`)",
          "```json",
          '{"command": "rm -rf /"}',
          "```",
          "@You:",
          "**Tool Result:** `call_pending` (pending)",
          "",
          "```",
          "```",
        })

        local tool_use = nil
        for _, msg in ipairs(doc.messages) do
          for _, seg in ipairs(msg.segments) do
            if seg.kind == "tool_use" then
              tool_use = seg
            end
          end
        end
        assert.is_not_nil(tool_use)

        local counterpart = ast.find_tool_sibling(doc, tool_use)
        assert.is_not_nil(counterpart)
        assert.equals("tool_result", counterpart.kind)
        assert.equals("pending", counterpart.status)
      end)
    end)

    describe("find_message_at_line", function()
      it("returns message when lnum matches start_line (fast path)", function()
        local query = require("flemma.ast.query")
        local doc = parser.parse_lines({
          "@You:",
          "hello",
          "@Assistant:",
          "world",
        })
        local msg = query.find_message_at_line(doc, 1)
        assert.is_not_nil(msg)
        assert.equals("You", msg.role)
      end)

      it("returns message when lnum is inside the message (containment fallback)", function()
        local query = require("flemma.ast.query")
        local doc = parser.parse_lines({
          "@You:",
          "hello",
          "@Assistant:",
          "line one",
          "line two",
          "line three",
        })
        local msg = query.find_message_at_line(doc, 5)
        assert.is_not_nil(msg)
        assert.equals("Assistant", msg.role)
      end)

      it("returns nil when lnum is outside all messages", function()
        local query = require("flemma.ast.query")
        local doc = parser.parse_lines({})
        local msg = query.find_message_at_line(doc, 1)
        assert.is_nil(msg)
      end)

      it("finds the correct message among multiple", function()
        local query = require("flemma.ast.query")
        local doc = parser.parse_lines({
          "@System:",
          "system prompt",
          "@You:",
          "question",
          "@Assistant:",
          "answer",
        })
        -- Line 4 is inside @You: message
        local msg = query.find_message_at_line(doc, 4)
        assert.is_not_nil(msg)
        assert.equals("You", msg.role)
      end)
    end)

    describe("build_tool_use_index", function()
      it("returns name and label for tool_use with input.label", function()
        local query = require("flemma.ast.query")
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `bash` (`call_001`)",
          "```json",
          '{"command": "ls", "label": "List files", "timeout": 30}',
          "```",
        })
        local index = query.build_tool_use_index(doc)
        assert.are.equal("bash", index["call_001"].name)
        assert.are.equal("List files", index["call_001"].label)
      end)

      it("returns name with nil label when input has no label", function()
        local query = require("flemma.ast.query")
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `bash` (`call_002`)",
          "```json",
          '{"command": "ls", "timeout": 30}',
          "```",
        })
        local index = query.build_tool_use_index(doc)
        assert.are.equal("bash", index["call_002"].name)
        assert.is_nil(index["call_002"].label)
      end)

      it("handles multiple tools across messages", function()
        local query = require("flemma.ast.query")
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `read` (`call_003`)",
          "```json",
          '{"path": "foo.lua", "label": "Reading foo", "offset": null, "limit": null}',
          "```",
          "**Tool Use:** `bash` (`call_004`)",
          "```json",
          '{"command": "ls", "label": "List files", "timeout": 30}',
          "```",
        })
        local index = query.build_tool_use_index(doc)
        assert.are.equal("read", index["call_003"].name)
        assert.are.equal("Reading foo", index["call_003"].label)
        assert.are.equal("bash", index["call_004"].name)
        assert.are.equal("List files", index["call_004"].label)
      end)

      it("ignores tool_result segments", function()
        local query = require("flemma.ast.query")
        local doc = parser.parse_lines({
          "@You:",
          "**Tool Result:** `call_005`",
          "",
          "```",
          "output",
          "```",
        })
        local index = query.build_tool_use_index(doc)
        assert.is_nil(index["call_005"])
      end)
    end)

    describe("build_tool_sibling_table", function()
      it("returns empty table for empty document", function()
        local doc = parser.parse_lines({})
        local table_ = ast.build_tool_sibling_table(doc)
        assert.same({}, table_)
      end)

      it("indexes paired tool use and result", function()
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `bash` (`call_x`)",
          "```json",
          '{"command": "ls"}',
          "```",
          "@You:",
          "**Tool Result:** `call_x`",
          "",
          "```",
          "output",
          "```",
        })

        local siblings = ast.build_tool_sibling_table(doc)
        assert.is_not_nil(siblings["call_x"])
        assert.is_not_nil(siblings["call_x"].use)
        assert.equals("bash", siblings["call_x"].use.name)
        assert.is_not_nil(siblings["call_x"].use_message)
        assert.equals("Assistant", siblings["call_x"].use_message.role)
        assert.is_not_nil(siblings["call_x"].result)
        assert.equals("call_x", siblings["call_x"].result.tool_use_id)
        assert.is_not_nil(siblings["call_x"].result_message)
        assert.equals("You", siblings["call_x"].result_message.role)
      end)

      it("handles orphan tool_use (no result)", function()
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `bash` (`call_orphan_use`)",
          "```json",
          '{"command": "pwd"}',
          "```",
        })

        local siblings = ast.build_tool_sibling_table(doc)
        assert.is_not_nil(siblings["call_orphan_use"])
        assert.is_not_nil(siblings["call_orphan_use"].use)
        assert.is_nil(siblings["call_orphan_use"].result)
      end)

      it("last tool_result wins for duplicate tool_use_id", function()
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `bash` (`call_dup2`)",
          "```json",
          '{"command": "echo"}',
          "```",
          "@You:",
          "**Tool Result:** `call_dup2`",
          "",
          "```",
          "first",
          "```",
          "**Tool Result:** `call_dup2`",
          "",
          "```",
          "second",
          "```",
        })

        local siblings = ast.build_tool_sibling_table(doc)
        assert.is_not_nil(siblings["call_dup2"])
        assert.equals("second", siblings["call_dup2"].result.content)
      end)

      it("preserves status on tool_result entries", function()
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `bash` (`call_status`)",
          "```json",
          '{"command": "rm /"}',
          "```",
          "@You:",
          "**Tool Result:** `call_status` (pending)",
          "",
          "```",
          "```",
        })

        local siblings = ast.build_tool_sibling_table(doc)
        assert.is_not_nil(siblings["call_status"])
        assert.is_not_nil(siblings["call_status"].result)
        assert.equals("pending", siblings["call_status"].result.status)
      end)

      it("indexes multiple pairs correctly", function()
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `bash` (`id_1`)",
          "```json",
          '{"command": "a"}',
          "```",
          "**Tool Use:** `read` (`id_2`)",
          "```json",
          '{"path": "b"}',
          "```",
          "@You:",
          "**Tool Result:** `id_1`",
          "",
          "```",
          "res_a",
          "```",
          "**Tool Result:** `id_2`",
          "",
          "```",
          "res_b",
          "```",
        })

        local siblings = ast.build_tool_sibling_table(doc)
        assert.is_not_nil(siblings["id_1"])
        assert.is_not_nil(siblings["id_2"])
        assert.equals("bash", siblings["id_1"].use.name)
        assert.equals("read", siblings["id_2"].use.name)
        assert.equals("res_a", siblings["id_1"].result.content)
        assert.equals("res_b", siblings["id_2"].result.content)
      end)
    end)

    describe("find_tool_segment_at_line", function()
      it("returns job_result segment", function()
        local doc = parser.parse_lines({
          "@You:",
          "**Job Result:** `job_abc12345`",
          "",
          "```",
          "test output",
          "```",
        })

        local seg, kind = ast.find_tool_segment_at_line(doc, 2)
        assert.is_not_nil(seg)
        assert.equals("job_result", kind)
        assert.equals("job_abc12345", seg.job_id)
      end)
    end)

    describe("find_job_result", function()
      it("finds a job_result by job_id", function()
        local doc = parser.parse_lines({
          "@You:",
          "**Job Result:** `job_find1`",
          "",
          "```",
          "result data",
          "```",
        })

        local seg, msg = ast.find_job_result(doc, "job_find1")
        assert.is_not_nil(seg)
        assert.equals("job_result", seg.kind)
        assert.equals("job_find1", seg.job_id)
        assert.is_not_nil(msg)
        assert.equals("You", msg.role)
      end)

      it("returns nil for non-existent job_id", function()
        local doc = parser.parse_lines({
          "@You:",
          "**Job Result:** `job_exists`",
          "",
          "```",
          "data",
          "```",
        })

        local seg = ast.find_job_result(doc, "job_nope")
        assert.is_nil(seg)
      end)
    end)

    describe("find_tool_result_for_job", function()
      it("finds a tool_result with matching job= meta", function()
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `bash` (`call_bg1`)",
          "```json",
          '{"command": "ls"}',
          "```",
          "@You:",
          "**Tool Result:** `call_bg1` (job=job_match1)",
          "",
          "```",
          "Running as a background job.",
          "```",
        })

        local seg, msg = ast.find_tool_result_for_job(doc, "job_match1")
        assert.is_not_nil(seg)
        assert.equals("tool_result", seg.kind)
        assert.equals("call_bg1", seg.tool_use_id)
        assert.is_not_nil(msg)
      end)

      it("returns nil when no tool_result references the job", function()
        local doc = parser.parse_lines({
          "@You:",
          "**Tool Result:** `call_plain`",
          "",
          "```",
          "output",
          "```",
        })

        local seg = ast.find_tool_result_for_job(doc, "job_orphan")
        assert.is_nil(seg)
      end)
    end)

    describe("effective_tool_result_status", function()
      it("returns the tool_result's own status when set", function()
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `bash` (`call_es1`)",
          "```json",
          '{"command": "ls"}',
          "```",
          "@You:",
          "**Tool Result:** `call_es1` (error)",
          "",
          "```",
          "permission denied",
          "```",
        })

        local seg = nil
        for _, msg in ipairs(doc.messages) do
          for _, s in ipairs(msg.segments) do
            if s.kind == "tool_result" then
              seg = s
            end
          end
        end
        assert.is_not_nil(seg)
        assert.equals("error", ast.effective_tool_result_status(seg, doc))
      end)

      it("returns nil for a successful tool_result without job", function()
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `bash` (`call_es2`)",
          "```json",
          '{"command": "ls"}',
          "```",
          "@You:",
          "**Tool Result:** `call_es2`",
          "",
          "```",
          "file1.txt",
          "```",
        })

        local seg = nil
        for _, msg in ipairs(doc.messages) do
          for _, s in ipairs(msg.segments) do
            if s.kind == "tool_result" then
              seg = s
            end
          end
        end
        assert.is_not_nil(seg)
        assert.is_nil(ast.effective_tool_result_status(seg, doc))
      end)

      it("inherits error from a failed job_result", function()
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `bash` (`call_es3`)",
          "```json",
          '{"command": "sleep 999"}',
          "```",
          "@You:",
          "**Tool Result:** `call_es3` (job=job_fail1)",
          "",
          "```",
          "Running as a background job.",
          "```",
          "",
          "@You:",
          "**Job Result:** `job_fail1` (error)",
          "",
          "```",
          "Exit code 1",
          "```",
        })

        local seg = nil
        for _, msg in ipairs(doc.messages) do
          for _, s in ipairs(msg.segments) do
            if s.kind == "tool_result" then
              seg = s
            end
          end
        end
        assert.is_not_nil(seg)
        assert.equals("error", ast.effective_tool_result_status(seg, doc))
      end)

      it("returns nil for a successful job_result", function()
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `bash` (`call_es4`)",
          "```json",
          '{"command": "ls"}',
          "```",
          "@You:",
          "**Tool Result:** `call_es4` (job=job_ok1)",
          "",
          "```",
          "Running as a background job.",
          "```",
          "",
          "@You:",
          "**Job Result:** `job_ok1`",
          "",
          "```",
          "file1.txt",
          "```",
        })

        local seg = nil
        for _, msg in ipairs(doc.messages) do
          for _, s in ipairs(msg.segments) do
            if s.kind == "tool_result" then
              seg = s
            end
          end
        end
        assert.is_not_nil(seg)
        assert.is_nil(ast.effective_tool_result_status(seg, doc))
      end)

      it("returns nil when job has not been delivered yet", function()
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `bash` (`call_es5`)",
          "```json",
          '{"command": "sleep 999"}',
          "```",
          "@You:",
          "**Tool Result:** `call_es5` (job=job_pending1)",
          "",
          "```",
          "Running as a background job.",
          "```",
        })

        local seg = nil
        for _, msg in ipairs(doc.messages) do
          for _, s in ipairs(msg.segments) do
            if s.kind == "tool_result" then
              seg = s
            end
          end
        end
        assert.is_not_nil(seg)
        assert.is_nil(ast.effective_tool_result_status(seg, doc))
      end)

      it("prefers tool_result's own status over job status", function()
        local doc = parser.parse_lines({
          "@Assistant:",
          "**Tool Use:** `bash` (`call_es6`)",
          "```json",
          '{"command": "ls"}',
          "```",
          "@You:",
          "**Tool Result:** `call_es6` (error job=job_override1)",
          "",
          "```",
          "Running as a background job.",
          "```",
          "",
          "@You:",
          "**Job Result:** `job_override1`",
          "",
          "```",
          "success",
          "```",
        })

        local seg = nil
        for _, msg in ipairs(doc.messages) do
          for _, s in ipairs(msg.segments) do
            if s.kind == "tool_result" then
              seg = s
            end
          end
        end
        assert.is_not_nil(seg)
        assert.equals("error", ast.effective_tool_result_status(seg, doc))
      end)
    end)
  end)
end)

describe("ast and context", function()
  local ast = require("flemma.ast")
  local ctx = require("flemma.context")
  local templating = require("flemma.templating")
  local parser = require("flemma.parser")
  local processor = require("flemma.processor")
  local pipeline = require("flemma.pipeline")
  local runner = require("flemma.preprocessor.runner")
  local file_refs = require("flemma.preprocessor.rewriters.file_references")

  describe("AST and Context", function()
    it("creates AST nodes with proper structure", function()
      local d = ast.document(nil, {}, {}, { start_line = 1, end_line = 1 })
      assert.equals("document", d.kind)
      assert.equals(1, d.position.start_line)

      local m = ast.message("You", { ast.text("hi") }, { start_line = 2, end_line = 3 })
      assert.equals("You", m.role)
      assert.equals("text", m.segments[1].kind)
    end)

    it("extends context with variables", function()
      local base = ctx.from_file("/tmp/flemma.chat")
      local ext = ctx.extend(base, { x = 1 })
      assert.equals(base:get_filename(), ext:get_filename())
      local vars = ext:get_variables()
      assert.equals(1, vars.x)
    end)

    it("provides __dirname from filename", function()
      local base = ctx.from_file("/tmp/flemma.chat")
      assert.equals("/tmp", base:get_dirname())
    end)

    it("returns nil dirname when no filename", function()
      local empty = ctx.clone(nil)
      assert.is_nil(empty:get_dirname())
    end)

    it("clone preserves filename", function()
      local base = ctx.from_file("/tmp/flemma.chat")
      local cloned = ctx.clone(base)
      assert.equals("/tmp/flemma.chat", cloned:get_filename())
      assert.equals("/tmp", cloned:get_dirname())
    end)

    it("extend preserves filename", function()
      local base = ctx.from_file("/tmp/flemma.chat")
      local ext = ctx.extend(base, { y = 2 })
      assert.equals("/tmp/flemma.chat", ext:get_filename())
      assert.equals("/tmp", ext:get_dirname())
    end)

    it("creates eval environment from context", function()
      local base = ctx.from_file("/tmp/flemma.chat")
      local ext = ctx.extend(base, { foo = "bar" })
      local env = templating.from_context(ext)
      assert.equals("/tmp/flemma.chat", env.__filename)
      assert.equals("/tmp", env.__dirname)
      assert.equals("bar", env.foo)
    end)

    it("sets __dirname to nil when context has no filename", function()
      local empty = ctx.clone(nil)
      local env = templating.from_context(empty)
      assert.is_nil(env.__filename)
      assert.is_nil(env.__dirname)
    end)
  end)

  describe("Parser", function()
    it("parses empty document", function()
      local doc = parser.parse_lines({})
      assert.equals("document", doc.kind)
      assert.is_nil(doc.frontmatter)
      assert.equals(0, #doc.messages)
    end)

    it("parses frontmatter only", function()
      local lines = {
        "```lua",
        "x = 1",
        "```",
      }
      local doc = parser.parse_lines(lines)
      assert.is_not_nil(doc.frontmatter)
      assert.equals("lua", doc.frontmatter.language)
      assert.equals(0, #doc.messages)
    end)

    it("parses messages and segments", function()
      local lines = {
        "@You:",
        "Hello {{1+1}} world @./a.txt.",
        "@Assistant:",
        "Ok",
      }
      local doc = parser.parse_lines(lines)
      local m1 = doc.messages[1]
      assert.equals("You", m1.role)
      local kinds = {}
      for _, s in ipairs(m1.segments) do
        kinds[#kinds + 1] = s.kind
      end
      -- Parser no longer converts @./file to expression; only {{ }} are expressions
      -- Expected: text("Hello "), expression(1+1), text(" world @./a.txt.")
      assert.equals("text", kinds[1])
      assert.equals("expression", kinds[2])
      assert.equals("text", kinds[3])
    end)

    it("parses MIME override and URL-encoded filenames as raw text (handled by preprocessor)", function()
      local lines = {
        "@You:",
        "See @./my%20file.bin;type=image/png!",
      }
      local doc = parser.parse_lines(lines)
      -- Parser no longer converts @./file to expression; it stays as text
      -- The preprocessor file-references rewriter handles the conversion
      local segs = doc.messages[1].segments
      assert.equals(1, #segs)
      assert.equals("text", segs[1].kind)
      assert.equals("See @./my%20file.bin;type=image/png!", segs[1].value)
    end)

    it("does not treat role markers inside fenced code blocks as message boundaries", function()
      local lines = {
        "@You:",
        "Here is how you use Flemma:",
        "",
        "```",
        "@You:",
        "Hello!",
        "```",
      }
      local doc = parser.parse_lines(lines)
      assert.equals(1, #doc.messages, "Should parse as a single message, not split on @You: inside fence")
      assert.equals("You", doc.messages[1].role)
    end)

    it("handles nested fences with role markers inside inner fence", function()
      local lines = {
        "@You:",
        "Outer content",
        "",
        "````",
        "```",
        "@Assistant:",
        "```",
        "````",
      }
      local doc = parser.parse_lines(lines)
      assert.equals(1, #doc.messages, "Should parse as single message; inner ``` does not close ````")
      assert.equals("You", doc.messages[1].role)
    end)

    it("does not treat inline fenced code as a fence opener", function()
      -- Per CommonMark: backtick fence info string cannot contain backtick characters.
      -- Lines where backticks open and close on the same line are not valid fences.
      local cases = {
        "```How are you?```",
        "```markdown Hello!```",
        "```    ...giving up```",
        "```Hello `World?",
      }
      for _, inline_code in ipairs(cases) do
        local lines = {
          "@Assistant:",
          "Hi!",
          inline_code,
          "",
          "@You:",
          "Goodbye!",
        }
        local doc = parser.parse_lines(lines)
        assert.equals(2, #doc.messages, "Line '" .. inline_code .. "' should not be treated as a fence opener")
        assert.equals("Assistant", doc.messages[1].role)
        assert.equals("You", doc.messages[2].role)
      end
    end)

    it("resumes normal parsing after a fenced code block closes", function()
      local lines = {
        "@You:",
        "Before fence",
        "```",
        "@Assistant:",
        "```",
        "@Assistant:",
        "After fence",
      }
      local doc = parser.parse_lines(lines)
      assert.equals(2, #doc.messages, "Should find two messages: fence-protected @Assistant: and real @Assistant:")
      assert.equals("You", doc.messages[1].role)
      assert.equals("Assistant", doc.messages[2].role)
    end)

    it("parses thinking tags in Assistant messages", function()
      local lines = {
        "@Assistant:",
        "I think",
        "<thinking>",
        "this is my internal thought",
        "</thinking>",
        "that the answer is 42.",
      }
      local doc = parser.parse_lines(lines)
      local msg = doc.messages[1]
      assert.equals("Assistant", msg.role)

      -- Check segments include thinking node
      local has_thinking = false
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "thinking" then
          has_thinking = true
          assert.equals("this is my internal thought", seg.content)
        end
      end
      assert.is_true(has_thinking, "Should have parsed thinking node")
    end)

    it("parses redacted thinking tags in Assistant messages", function()
      local lines = {
        "@Assistant:",
        "Here is my response.",
        "",
        "<thinking redacted>",
        "encrypted-data-abc123",
        "</thinking>",
      }
      local doc = parser.parse_lines(lines)
      local msg = doc.messages[1]
      assert.equals("Assistant", msg.role)

      local thinking_seg = nil
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "thinking" and seg.redacted then
          thinking_seg = seg
          break
        end
      end

      assert.is_not_nil(thinking_seg, "Should have parsed redacted thinking node")
      assert.equals("encrypted-data-abc123", thinking_seg.content)
      assert.is_true(thinking_seg.redacted)
      assert.is_nil(thinking_seg.signature, "Redacted thinking should not have signature")
    end)

    it("parses thinking tags with line positions when on separate lines", function()
      local lines = {
        "@Assistant:",
        "Here is my response",
        "<thinking>",
        "internal thought process",
        "more thinking",
        "</thinking>",
        "The answer is 42.",
      }
      local doc = parser.parse_lines(lines)
      local msg = doc.messages[1]
      assert.equals("Assistant", msg.role)

      -- Find thinking segment
      local thinking_seg = nil
      for _, seg in ipairs(msg.segments) do
        if seg.kind == "thinking" then
          thinking_seg = seg
          break
        end
      end

      assert.is_not_nil(thinking_seg, "Should have thinking segment")
      assert.equals("internal thought process\nmore thinking", thinking_seg.content)
      assert.is_not_nil(thinking_seg.position, "Thinking segment should have position")
      assert.equals(3, thinking_seg.position.start_line, "Thinking should start at line 3")
      assert.equals(6, thinking_seg.position.end_line, "Thinking should end at line 6")
    end)
  end)

  describe("Expression segment positions", function()
    it("sets end_col on {{ }} expressions", function()
      local doc = parser.parse_lines({
        "@You:",
        "Hello {{ name }} world",
      })
      local segs = doc.messages[1].segments
      -- Find the expression segment
      local expr_seg
      for _, seg in ipairs(segs) do
        if seg.kind == "expression" then
          expr_seg = seg
          break
        end
      end
      assert.is_not_nil(expr_seg)
      assert.is_not_nil(expr_seg.position.start_col)
      assert.is_not_nil(expr_seg.position.end_col)
      assert.is_true(expr_seg.position.end_col > expr_seg.position.start_col)
    end)

    it("treats @./ file references as plain text (handled by preprocessor)", function()
      local doc = parser.parse_lines({
        "@You:",
        "See @./readme.md for details",
      })
      local segs = doc.messages[1].segments
      -- Parser no longer converts @./file to expression segments
      assert.equals(1, #segs)
      assert.equals("text", segs[1].kind)
      assert.equals("See @./readme.md for details", segs[1].value)
    end)
  end)

  describe("find_segment_at_position", function()
    it("finds expression segment by line and column", function()
      local doc = parser.parse_lines({
        "@You:",
        "Hello {{ name }} world",
      })
      local seg, msg = ast.find_segment_at_position(doc, 2, 8)
      assert.is_not_nil(seg)
      assert.equals("expression", seg.kind)
      assert.equals("You", msg.role)
    end)

    it("returns text segment when not on expression", function()
      local doc = parser.parse_lines({
        "@You:",
        "Hello {{ name }} world",
      })
      local seg, msg = ast.find_segment_at_position(doc, 2, 1)
      assert.is_not_nil(seg)
      assert.equals("text", seg.kind)
      assert.equals("You", msg.role)
    end)

    it("returns nil for line outside any message", function()
      local doc = parser.parse_lines({
        "@You:",
        "Hello",
      })
      local seg, msg = ast.find_segment_at_position(doc, 99, 1)
      assert.is_nil(seg)
      assert.is_nil(msg)
    end)

    it("finds thinking segment by line", function()
      local doc = parser.parse_lines({
        "@Assistant:",
        "<thinking>",
        "I need to think about this",
        "</thinking>",
        "Here is my answer",
      })
      local seg, msg = ast.find_segment_at_position(doc, 3, 1)
      assert.is_not_nil(seg)
      assert.equals("thinking", seg.kind)
      assert.equals("Assistant", msg.role)
    end)

    it("finds tool_use segment by line", function()
      local doc = parser.parse_lines({
        "@Assistant:",
        "**Tool Use:** `bash` (`call_123`)",
        "```json",
        '{"command": "ls"}',
        "```",
      })
      local seg, msg = ast.find_segment_at_position(doc, 2, 1)
      assert.is_not_nil(seg)
      assert.equals("tool_use", seg.kind)
      assert.equals("Assistant", msg.role)
    end)

    it("returns message without segment on role marker line", function()
      local doc = parser.parse_lines({
        "@You:",
        "Hello world",
      })
      local seg, msg = ast.find_segment_at_position(doc, 1, 1)
      assert.is_nil(seg)
      assert.is_not_nil(msg)
      assert.equals("You", msg.role)
    end)

    it("distinguishes adjacent expressions on same line", function()
      local doc = parser.parse_lines({
        "@You:",
        "{{ a }} and {{ b }}",
      })
      -- First expression
      local seg1 = ast.find_segment_at_position(doc, 2, 1)
      assert.is_not_nil(seg1)
      assert.equals("expression", seg1.kind)
      assert.equals(" a ", seg1.code)

      -- Second expression
      local seg2 = ast.find_segment_at_position(doc, 2, 14)
      assert.is_not_nil(seg2)
      assert.equals("expression", seg2.kind)
      assert.equals(" b ", seg2.code)
    end)
  end)

  --- Run the file-references preprocessor rewriter on a parsed document.
  --- Converts @./file text into include() expression segments.
  ---@param doc flemma.ast.DocumentNode
  ---@return flemma.ast.DocumentNode
  local function run_file_refs_rewriter(doc)
    return runner.run_pipeline(doc, 0, {
      interactive = false,
      rewriters = { file_refs.rewriter },
    })
  end

  describe("Processor", function()
    local function setup_fixtures()
      os.execute("mkdir -p tests/fixtures")
      local f = io.open("tests/fixtures/a.txt", "w")
      f:write("hello A")
      f:close()
      f = io.open("tests/fixtures/doc.chat", "w")
      f:write("")
      f:close()
      f = io.open("tests/fixtures/loop1.txt", "w")
      f:write("{{ include('loop2.txt') }}")
      f:close()
      f = io.open("tests/fixtures/loop2.txt", "w")
      f:write("{{ include('loop1.txt') }}")
      f:close()
    end

    before_each(function()
      setup_fixtures()
    end)

    it("evaluates expressions and resolves file refs", function()
      local base = ctx.from_file("tests/fixtures/doc.chat")
      local lines = {
        "@You:",
        "File1: {{ 'hello' }} and File2: @./a.txt.",
      }
      local doc = parser.parse_lines(lines)
      -- Run file-references rewriter to convert @./file -> include() expressions
      doc = run_file_refs_rewriter(doc)
      local out = processor.evaluate(doc, base)
      assert.equals(1, #out.messages)
      local parts = out.messages[1].parts
      local kinds = {}
      for _, p in ipairs(parts) do
        kinds[#kinds + 1] = p.kind
      end
      -- The compiler merges adjacent text segments, so we get:
      -- text("File1: hello and File2: "), file(a.txt), text(".")
      assert.equals("text", kinds[1])
      assert.equals("file", kinds[2])
      local file_diags = vim.tbl_filter(function(d)
        return d.type == "file"
      end, out.diagnostics or {})
      assert.equals(0, #file_diags)
    end)

    it("handles URL-encoded filename and trailing punctuation", function()
      local base = ctx.from_file("tests/fixtures/doc.chat")
      local lines = {
        "@You:",
        "See @./my%20file.txt!",
      }
      local doc = parser.parse_lines(lines)
      -- Run file-references rewriter to convert @./file -> include() expressions
      doc = run_file_refs_rewriter(doc)
      local out = processor.evaluate(doc, base)
      local parts = out.messages[1].parts
      assert.equals("file", parts[2].kind)
      assert.equals("text", parts[3].kind)
      assert.equals("!", parts[3].text)
    end)

    it("handles MIME override", function()
      local f = io.open("tests/fixtures/sample.bin", "wb")
      f:write("BINARY")
      f:close()
      local base2 = ctx.from_file("tests/fixtures/sample.bin")
      local lines = {
        "@You:",
        "Img: @./sample.bin;type=image/png",
      }
      local doc = parser.parse_lines(lines)
      -- Run file-references rewriter to convert @./file -> include() expressions
      doc = run_file_refs_rewriter(doc)
      local out = processor.evaluate(doc, base2)
      local parts = out.messages[1].parts
      assert.equals("file", parts[2].kind)
      assert.equals("image/png", parts[2].mime_type)
    end)

    it("handles circular includes gracefully", function()
      local lines = {
        "@You:",
        "{{ include('tests/fixtures/loop1.txt') }}",
      }
      local b = ctx.from_file("tests/fixtures/loop1.txt")
      local doc = parser.parse_lines(lines)
      local ok = pcall(processor.evaluate, doc, b)
      assert.is_true(ok, "Processor should not crash; include() error handled in expression eval as text")
    end)

    it("treats @./ file references inside included content as plain text", function()
      local f = io.open("tests/fixtures/with_ref.txt", "w")
      f:write("Content: @./a.txt here")
      f:close()

      local lines = {
        "@You:",
        "{{ include('./with_ref.txt') }}",
      }
      local b = ctx.from_file("tests/fixtures/doc.chat")
      local doc = parser.parse_lines(lines)
      local out = processor.evaluate(doc, b)

      -- @./file inside included content is now plain text (preprocessor runs at document level only)
      local parts = out.messages[1].parts
      local has_text_content = false
      for _, p in ipairs(parts) do
        if p.kind == "text" and p.text:match("Content:") then
          has_text_content = true
        end
      end
      assert.is_true(has_text_content, "Should have text content from included file")
      -- The @./a.txt reference is now literal text, not a resolved file part
      local full_text = ""
      for _, p in ipairs(parts) do
        if p.kind == "text" then
          full_text = full_text .. p.text
        end
      end
      assert.is_true(full_text:match("@%./a%.txt") ~= nil, "@./a.txt should remain as literal text in included content")
    end)

    it("does not process expressions or file refs in @Assistant messages", function()
      local base = ctx.from_file("tests/fixtures/doc.chat")
      local lines = {
        "@Assistant:",
        "{{ 1 + 1 }} and @./a.txt should be literal",
      }
      local doc = parser.parse_lines(lines)
      local out = processor.evaluate(doc, base)
      local parts = out.messages[1].parts
      assert.equals(1, #parts)
      assert.equals("text", parts[1].kind)
      assert.is_true(parts[1].text:match("{{ 1 %+ 1 }}") ~= nil, "@Assistant should keep expressions literal")
      assert.is_true(parts[1].text:match("@%./a%.txt") ~= nil, "@Assistant should keep file refs literal")
    end)

    it("collects expression errors", function()
      local base = ctx.from_file("tests/fixtures/doc.chat")
      local lines = {
        "@You:",
        "{{ 1 / 'x' }}",
      }
      local doc = parser.parse_lines(lines)
      local out = processor.evaluate(doc, base)
      assert.is_true(#out.diagnostics > 0, "Should collect diagnostics")
      local expr_diags = vim.tbl_filter(function(d)
        return d.type == "expression"
      end, out.diagnostics)
      assert.is_true(#expr_diags > 0, "Should collect expression errors")
      assert.is_true(expr_diags[1].expression:match("1 / 'x'") ~= nil)
      assert.equals("warning", expr_diags[1].severity)
      -- Output should still contain the original expression
      local text = out.messages[1].parts[1].text
      assert.is_true(text:match("{{") ~= nil, "Failed expression should remain in output")
    end)

    it("evaluates {% code %} blocks in @System messages", function()
      local base = ctx.from_file("tests/fixtures/doc.chat")
      local lines = {
        "```lua",
        "mode = 'strict'",
        "```",
        "@System:",
        "{% if mode == 'strict' then %}",
        "Be precise and thorough.",
        "{% else %}",
        "Be friendly and concise.",
        "{% end %}",
      }
      local doc = parser.parse_lines(lines)
      local out = processor.evaluate(doc, base)
      assert.equals(1, #out.messages)
      local text = ""
      for _, p in ipairs(out.messages[1].parts) do
        if p.kind == "text" then
          text = text .. p.text
        end
      end
      assert.truthy(text:find("Be precise and thorough"))
      assert.is_nil(text:find("Be friendly and concise"))
    end)

    it("evaluates {% for %} loops in @You messages", function()
      local base = ctx.from_file("tests/fixtures/doc.chat")
      local lines = {
        "```lua",
        'items = {"alpha", "beta", "gamma"}',
        "```",
        "@You:",
        "Review these:",
        "{% for _, item in ipairs(items) do %}",
        "- {{ item }}",
        "{% end %}",
      }
      local doc = parser.parse_lines(lines)
      local out = processor.evaluate(doc, base)
      local text = ""
      for _, p in ipairs(out.messages[1].parts) do
        if p.kind == "text" then
          text = text .. p.text
        end
      end
      assert.truthy(text:find("alpha"))
      assert.truthy(text:find("beta"))
      assert.truthy(text:find("gamma"))
    end)

    it("{% code %} error produces template diagnostic", function()
      local base = ctx.from_file("tests/fixtures/doc.chat")
      local lines = {
        "@You:",
        "{% iff true then %}",
        "text",
        "{% end %}",
      }
      local doc = parser.parse_lines(lines)
      local out = processor.evaluate(doc, base)
      local template_diags = vim.tbl_filter(function(d)
        return d.type == "template"
      end, out.diagnostics or {})
      assert.is_true(#template_diags > 0, "Should have template diagnostic for syntax error")
    end)

    it("preserves thinking nodes in evaluation", function()
      local lines = {
        "@Assistant:",
        "I think",
        "<thinking>",
        "internal thought",
        "</thinking>",
        "the answer is 42.",
      }
      local doc = parser.parse_lines(lines)
      local out = processor.evaluate(doc, ctx.from_file("tests/fixtures/doc.chat"))

      -- Check that thinking nodes are preserved as parts
      local parts = out.messages[1].parts
      local has_thinking = false
      for _, p in ipairs(parts) do
        if p.kind == "thinking" then
          has_thinking = true
          assert.equals("internal thought", p.content)
        end
      end
      assert.is_true(has_thinking, "Thinking should be preserved as a part")

      -- Check text parts exist
      local text_parts = {}
      for _, p in ipairs(parts) do
        if p.kind == "text" then
          table.insert(text_parts, p.text)
        end
      end
      local result = table.concat(text_parts, "")
      assert.is_true(result:match("I think") ~= nil, "Should contain text before thinking")
      assert.is_true(result:match("the answer is 42") ~= nil, "Should contain text after thinking")
    end)
  end)

  describe("AST to Parts Mapper", function()
    it("maps parts to generic provider format", function()
      local parts = ast.to_generic_parts({
        { kind = "text", text = "hi" },
        { kind = "file", filename = "x.png", mime_type = "image/png", data = "abcd" },
        { kind = "file", filename = "x.pdf", mime_type = "application/pdf", data = "pdf" },
        { kind = "file", filename = "x.txt", mime_type = "text/plain", data = "hello" },
      })
      assert.equals("text", parts[1].kind)
      assert.equals("image", parts[2].kind)
      assert.equals("pdf", parts[3].kind)
      assert.equals("text_file", parts[4].kind)
      assert.equals("hello", parts[4].text)
    end)

    it("treats SVG as text despite image/* MIME prefix", function()
      local svg_content = '<svg xmlns="http://www.w3.org/2000/svg"><circle r="10"/></svg>'
      local parts = ast.to_generic_parts({
        { kind = "file", filename = "icon.svg", mime_type = "image/svg+xml", data = svg_content },
      })
      assert.equals(1, #parts)
      assert.equals("text_file", parts[1].kind)
      assert.equals("image/svg+xml", parts[1].mime_type)
      assert.equals(svg_content, parts[1].text)
    end)

    it("preserves redacted flag on thinking parts", function()
      local parts = ast.to_generic_parts({
        { kind = "thinking", content = "normal thought", signature = { value = "sig1", provider = "anthropic" } },
        { kind = "thinking", content = "encrypted-data", redacted = true },
      })
      assert.equals(2, #parts)
      assert.equals("thinking", parts[1].kind)
      assert.equals("sig1", parts[1].signature.value)
      assert.equals("anthropic", parts[1].signature.provider)
      assert.is_nil(parts[1].redacted)
      assert.equals("thinking", parts[2].kind)
      assert.is_true(parts[2].redacted)
      assert.equals("encrypted-data", parts[2].content)
    end)
  end)

  describe("AST Thinking Constructor", function()
    it("creates thinking node with redacted flag", function()
      local seg = ast.thinking("encrypted-data", { start_line = 5, end_line = 7 }, { redacted = true })
      assert.equals("thinking", seg.kind)
      assert.equals("encrypted-data", seg.content)
      assert.is_true(seg.redacted)
      assert.is_nil(seg.signature)
      assert.equals(5, seg.position.start_line)
      assert.equals(7, seg.position.end_line)
    end)

    it("creates normal thinking node without redacted flag", function()
      local seg = ast.thinking(
        "thought",
        { start_line = 1, end_line = 3 },
        { signature = { value = "sig-abc", provider = "anthropic" } }
      )
      assert.equals("thinking", seg.kind)
      assert.equals("thought", seg.content)
      assert.equals("sig-abc", seg.signature.value)
      assert.equals("anthropic", seg.signature.provider)
      assert.is_nil(seg.redacted)
    end)
  end)

  describe("Pipeline Integration", function()
    it("runs full pipeline with system message", function()
      local lines = {
        "@System:",
        "You are helpful.",
        "@You:",
        "Hello",
        "@Assistant:",
        "Hi there!",
      }
      local prompt = pipeline.run(parser.parse_lines(lines), ctx.from_file("tests/fixtures/doc.chat"), { bufnr = 0 })
      assert.equals("You are helpful.", prompt.system)
      assert.equals(2, #prompt.history)
    end)

    it("runs full pipeline with frontmatter, expressions, and files", function()
      local lines = {
        "```lua",
        "name = 'World'",
        "```",
        "@You:",
        "Hello {{ name }}! See @./tests/fixtures/a.txt",
        "@Assistant:",
        "Got it",
      }

      local doc = parser.parse_lines(lines)
      -- Run file-references rewriter to convert @./file -> include() expressions
      doc = run_file_refs_rewriter(doc)
      local prompt = pipeline.run(doc, ctx.from_file("tests/fixtures/doc.chat"), { bufnr = 0 })

      assert.is_nil(prompt.system)
      assert.equals(2, #prompt.history)

      -- Check that expression was evaluated
      local user_msg = prompt.history[1]
      assert.equals("user", user_msg.role)
      local has_world = false
      local all_text = {}
      for _, p in ipairs(user_msg.parts) do
        if p.kind == "text" or p.kind == "text_file" then
          table.insert(all_text, p.text or "")
          if (p.text or ""):match("World") then
            has_world = true
          end
        end
      end
      assert.is_true(has_world, "Expression should be evaluated to 'World'. Got: " .. table.concat(all_text, "|"))
    end)
  end)

  describe("Provider Integration", function()
    it("builds Anthropic request from pipeline output", function()
      local anthropic = require("flemma.provider.adapters.anthropic")
      local provider = anthropic.new({ model = "claude-3-haiku-20240307", max_tokens = 256, temperature = 0 })

      local lines = {
        "@System:",
        "You are helpful.",
        "@You:",
        "Hello",
        "@Assistant:",
        "Hi there!",
      }
      local prompt = pipeline.run(parser.parse_lines(lines), ctx.from_file("tests/fixtures/doc.chat"), { bufnr = 0 })
      local req = provider:build_request(prompt, {})
      assert.is_not_nil(req.model)
      assert.equals("table", type(req.messages))
      assert.equals(2, #req.messages)
    end)

    it("builds OpenAI request from pipeline output", function()
      local openai = require("flemma.provider.adapters.openai")
      local provider = openai.new({ model = "gpt-4o-mini", max_tokens = 100, temperature = 0 })

      local lines = {
        "```lua",
        "name = 'World'",
        "```",
        "@You:",
        "Hello {{ name }}! See @./tests/fixtures/a.txt",
        "@Assistant:",
        "Got it",
      }

      local context = ctx.from_file("tests/fixtures/doc.chat")
      local doc = parser.parse_lines(lines)
      -- Run file-references rewriter to convert @./file -> include() expressions
      doc = run_file_refs_rewriter(doc)
      local prompt = pipeline.run(doc, context, { bufnr = 0 })
      local req = provider:build_request(prompt, context)
      -- Responses API uses input[] instead of messages[]
      local user_items = vim.tbl_filter(function(item)
        return item.role == "user"
      end, req.input)
      assert.equals(1, #user_items)
      assert.equals("user", user_items[1].role)
    end)
  end)

  describe("Expression segment positions", function()
    it("sets end_col on {{ }} expressions", function()
      local doc = parser.parse_lines({
        "@You:",
        "Hello {{ name }} world",
      })
      local segs = doc.messages[1].segments
      -- Find the expression segment
      local expr_seg
      for _, seg in ipairs(segs) do
        if seg.kind == "expression" then
          expr_seg = seg
          break
        end
      end
      assert.is_not_nil(expr_seg)
      assert.is_not_nil(expr_seg.position.start_col)
      assert.is_not_nil(expr_seg.position.end_col)
      assert.is_true(expr_seg.position.end_col > expr_seg.position.start_col)
    end)

    it("treats @./ file references as plain text (handled by preprocessor)", function()
      local doc = parser.parse_lines({
        "@You:",
        "See @./readme.md for details",
      })
      local segs = doc.messages[1].segments
      -- Parser no longer converts @./file to expression segments
      assert.equals(1, #segs)
      assert.equals("text", segs[1].kind)
      assert.equals("See @./readme.md for details", segs[1].value)
    end)
  end)

  describe("find_segment_at_position", function()
    it("finds expression segment by line and column", function()
      local doc = parser.parse_lines({
        "@You:",
        "Hello {{ name }} world",
      })
      local seg, msg = ast.find_segment_at_position(doc, 2, 8)
      assert.is_not_nil(seg)
      assert.equals("expression", seg.kind)
      assert.equals("You", msg.role)
    end)

    it("returns text segment when not on expression", function()
      local doc = parser.parse_lines({
        "@You:",
        "Hello {{ name }} world",
      })
      local seg, msg = ast.find_segment_at_position(doc, 2, 1)
      assert.is_not_nil(seg)
      assert.equals("text", seg.kind)
      assert.equals("You", msg.role)
    end)

    it("returns nil for line outside any message", function()
      local doc = parser.parse_lines({
        "@You:",
        "Hello",
      })
      local seg, msg = ast.find_segment_at_position(doc, 99, 1)
      assert.is_nil(seg)
      assert.is_nil(msg)
    end)

    it("finds thinking segment by line", function()
      local doc = parser.parse_lines({
        "@Assistant:",
        "<thinking>",
        "I need to think about this",
        "</thinking>",
        "Here is my answer",
      })
      local seg, msg = ast.find_segment_at_position(doc, 3, 1)
      assert.is_not_nil(seg)
      assert.equals("thinking", seg.kind)
      assert.equals("Assistant", msg.role)
    end)

    it("finds tool_use segment by line", function()
      local doc = parser.parse_lines({
        "@Assistant:",
        "**Tool Use:** `bash` (`call_123`)",
        "```json",
        '{"command": "ls"}',
        "```",
      })
      local seg, msg = ast.find_segment_at_position(doc, 2, 1)
      assert.is_not_nil(seg)
      assert.equals("tool_use", seg.kind)
      assert.equals("Assistant", msg.role)
    end)

    it("distinguishes adjacent expressions on same line", function()
      local doc = parser.parse_lines({
        "@You:",
        "{{ a }} and {{ b }}",
      })
      -- First expression
      local seg1 = ast.find_segment_at_position(doc, 2, 1)
      assert.is_not_nil(seg1)
      assert.equals("expression", seg1.kind)
      assert.equals(" a ", seg1.code)

      -- Second expression
      local seg2 = ast.find_segment_at_position(doc, 2, 14)
      assert.is_not_nil(seg2)
      assert.equals("expression", seg2.kind)
      assert.equals(" b ", seg2.code)
    end)

    it("distinguishes text segments around an expression on same line", function()
      local doc = parser.parse_lines({
        "@You:",
        "Hello {{ name }} world",
      })
      -- "Hello " text segment at col 1
      local seg1 = ast.find_segment_at_position(doc, 2, 1)
      assert.is_not_nil(seg1)
      assert.equals("text", seg1.kind)
      assert.equals("Hello ", seg1.value)

      -- " world" text segment at col 17
      local seg3 = ast.find_segment_at_position(doc, 2, 17)
      assert.is_not_nil(seg3)
      assert.equals("text", seg3.kind)
      assert.equals(" world", seg3.value)
    end)

    it("finds segment on start line of multi-line text with end_col on different line", function()
      -- Simulates a rewriter-produced segment like [102:34 - 103:0]
      local doc = ast.document(nil, {
        ast.message("You", {
          ast.text("prefix ", { start_line = 1, start_col = 1, end_line = 1, end_col = 7 }),
          ast.expression("expr", { start_line = 1, start_col = 8, end_line = 1, end_col = 15 }),
          ast.text(" trailing\n", { start_line = 1, start_col = 16, end_line = 2, end_col = 0 }),
        }, { start_line = 1, end_line = 2 }),
      }, {}, { start_line = 1, end_line = 2 })

      -- Col 20 is on the start line of the multi-line text segment
      local seg = ast.find_segment_at_position(doc, 1, 20)
      assert.is_not_nil(seg)
      assert.equals("text", seg.kind)
      assert.equals(" trailing\n", seg.value)
    end)
  end)

  describe("parser text segment accumulation", function()
    it("produces single text segment for multi-line assistant content", function()
      local doc = parser.parse_lines({
        "@Assistant:",
        "Line one",
        "Line two",
        "Line three",
      })
      local msg = doc.messages[1]
      -- Should be one accumulated text segment, not per-line segments
      assert.equals(1, #msg.segments)
      assert.equals("text", msg.segments[1].kind)
      assert.equals("Line one\nLine two\nLine three", msg.segments[1].value)
    end)

    it("produces single text segment for multi-line user content without expressions", function()
      local doc = parser.parse_lines({
        "@You:",
        "Line one",
        "Line two",
        "Line three",
      })
      local msg = doc.messages[1]
      assert.equals(1, #msg.segments)
      assert.equals("text", msg.segments[1].kind)
      assert.equals("Line one\nLine two\nLine three", msg.segments[1].value)
    end)

    it("flushes accumulated text before structural markers in assistant messages", function()
      local doc = parser.parse_lines({
        "@Assistant:",
        "Text before",
        "<thinking>",
        "thought",
        "</thinking>",
        "Text after",
      })
      local msg = doc.messages[1]
      -- text, thinking, text
      assert.equals(3, #msg.segments)
      assert.equals("text", msg.segments[1].kind)
      assert.truthy(msg.segments[1].value:find("Text before"))
      assert.equals("thinking", msg.segments[2].kind)
      assert.equals("text", msg.segments[3].kind)
      assert.truthy(msg.segments[3].value:find("Text after"))
    end)

    it("sets consistent end_line/end_col for trailing newlines", function()
      local doc = parser.parse_lines({
        "@You:",
        "content",
        "",
        "@Assistant:",
        "response",
      })
      -- The @You text segment includes trailing \n
      local you_seg = doc.messages[1].segments[1]
      assert.equals("text", you_seg.kind)
      -- Trailing \n should bump end_line, end_col = 0
      if you_seg.value:match("\n$") then
        assert.equals(0, you_seg.position.end_col)
        assert.is_true(you_seg.position.end_line > you_seg.position.start_line)
      end
    end)
  end)

  describe("multi-turn API content stability", function()
    local json = require("flemma.utilities.json")
    local anthropic

    before_each(function()
      package.loaded["flemma.provider.adapters.anthropic"] = nil
      package.loaded["flemma.tools"] = nil
      package.loaded["flemma.tools.registry"] = nil
      package.loaded["flemma.tools.approval"] = nil
      anthropic = require("flemma.provider.adapters.anthropic")
      local tools = require("flemma.tools")
      tools.clear()
    end)

    ---Build an Anthropic API request body from raw buffer lines.
    ---@param buffer_lines string[]
    ---@return table request_body
    local function build_request_from_lines(buffer_lines)
      local doc = parser.parse_lines(buffer_lines)
      local prompt = pipeline.run(doc, nil, { bufnr = 0 })
      local provider = anthropic.new({ model = "claude-sonnet-4-20250514", max_tokens = 100 })
      return provider:build_request(prompt)
    end

    ---Extract text values from a request message's content blocks.
    ---@param msg table Anthropic message with content array
    ---@return string[] texts
    local function extract_texts(msg)
      local texts = {}
      for _, block in ipairs(msg.content or {}) do
        if block.type == "text" then
          table.insert(texts, block.text)
        end
      end
      return texts
    end

    it("appending a new turn does not change earlier message content", function()
      local req1 = build_request_from_lines({
        "@You:",
        "Hello world",
        "",
        "@Assistant:",
        "Hi there!",
      })

      -- Append a second exchange
      local req2 = build_request_from_lines({
        "@You:",
        "Hello world",
        "",
        "@Assistant:",
        "Hi there!",
        "",
        "@You:",
        "Follow-up question",
      })

      -- Append a third exchange
      local req3 = build_request_from_lines({
        "@You:",
        "Hello world",
        "",
        "@Assistant:",
        "Hi there!",
        "",
        "@You:",
        "Follow-up question",
        "",
        "@Assistant:",
        "Sure, here you go.",
        "",
        "@You:",
        "Thanks!",
      })

      -- First user message must be byte-identical across all three
      assert.same(extract_texts(req1.messages[1]), extract_texts(req2.messages[1]))
      assert.same(extract_texts(req1.messages[1]), extract_texts(req3.messages[1]))

      -- First assistant message must be byte-identical across req2 and req3
      assert.same(extract_texts(req1.messages[2]), extract_texts(req2.messages[2]))
      assert.same(extract_texts(req1.messages[2]), extract_texts(req3.messages[2]))

      -- No trailing newlines on any message in any request
      for _, req in ipairs({ req1, req2, req3 }) do
        for mi, msg in ipairs(req.messages) do
          for _, text in ipairs(extract_texts(msg)) do
            assert.is_falsy(
              text:match("\n$"),
              string.format("message %d (%s) should not end with newline: %s", mi, msg.role, text)
            )
          end
        end
      end
    end)

    it("JSON prefix is stable across turns (simulates diagnostics cache check)", function()
      local req1 = build_request_from_lines({
        "@You:",
        "What is 2+2?",
        "",
        "@Assistant:",
        "The answer is 4.",
      })

      local req2 = build_request_from_lines({
        "@You:",
        "What is 2+2?",
        "",
        "@Assistant:",
        "The answer is 4.",
        "",
        "@You:",
        "And 3+3?",
      })

      -- req1 has 2 messages, req2 has 3; the first 2 must be byte-identical when serialized
      local first_two_from_req1 = json.encode({ req1.messages[1], req1.messages[2] })
      local first_two_from_req2 = json.encode({ req2.messages[1], req2.messages[2] })
      assert.equals(first_two_from_req1, first_two_from_req2)
    end)

    it("multi-line user message with expressions has stable content across turns", function()
      local req1 = build_request_from_lines({
        "@You:",
        "Hello {{ 'world' }}! How are you?",
        "",
        "@Assistant:",
        "I am fine, thank you!",
      })

      local req2 = build_request_from_lines({
        "@You:",
        "Hello {{ 'world' }}! How are you?",
        "",
        "@Assistant:",
        "I am fine, thank you!",
        "",
        "@You:",
        "Great to hear!",
      })

      -- First user message content blocks must be identical
      assert.same(extract_texts(req1.messages[1]), extract_texts(req2.messages[1]))

      -- Verify the expression was evaluated and no trailing newlines
      local full = table.concat(extract_texts(req1.messages[1]))
      assert.truthy(full:find("world"), "expression should be evaluated")
      assert.is_falsy(full:match("\n"), "evaluated content should not contain newlines")
    end)

    it("multiple blank separator lines between messages do not leak into content", function()
      -- Some users leave extra blank lines between messages for readability
      local req1 = build_request_from_lines({
        "@You:",
        "First question",
        "",
        "",
        "",
        "@Assistant:",
        "First answer",
        "",
        "",
        "@You:",
        "Second question",
      })

      -- All messages should have clean content without trailing newlines
      for mi, msg in ipairs(req1.messages) do
        for _, text in ipairs(extract_texts(msg)) do
          assert.is_falsy(
            text:match("\n$"),
            string.format("message %d (%s) should not end with newline: %s", mi, msg.role, text)
          )
        end
      end

      -- Verify content is exactly what was typed, nothing more
      assert.equals("First question", extract_texts(req1.messages[1])[1])
      assert.equals("First answer", extract_texts(req1.messages[2])[1])
      assert.equals("Second question", extract_texts(req1.messages[3])[1])
    end)

    it("multi-line assistant content is stable across turns", function()
      local req1 = build_request_from_lines({
        "@You:",
        "Tell me about Lua.",
        "",
        "@Assistant:",
        "Lua is a lightweight scripting language.",
        "It was created in Brazil.",
        "It is used in game development.",
      })

      local req2 = build_request_from_lines({
        "@You:",
        "Tell me about Lua.",
        "",
        "@Assistant:",
        "Lua is a lightweight scripting language.",
        "It was created in Brazil.",
        "It is used in game development.",
        "",
        "@You:",
        "Tell me more.",
      })

      -- Assistant content must be identical
      local asst1 = extract_texts(req1.messages[2])
      local asst2 = extract_texts(req2.messages[2])
      assert.same(asst1, asst2)

      -- Should be one text block with internal newlines but no trailing newline
      assert.equals(1, #asst1)
      assert.is_falsy(asst1[1]:match("\n$"), "assistant text should not end with newline")
      assert.truthy(asst1[1]:find("\n"), "multi-line content should have internal newlines")
    end)
  end)
end)

describe("ast background job results", function()
  describe("job result parsing", function()
    local parser

    before_each(function()
      package.loaded["flemma.parser"] = nil
      package.loaded["flemma.ast"] = nil
      parser = require("flemma.parser")
    end)

    it("parses a successful job result block", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "**Job Result:** `job_k7x2m`",
        "",
        "```",
        "tests/flemma/core_spec.lua: 47 passed, 0 failed",
        "```",
      })
      local doc = parser.get_parsed_document(bufnr)
      assert.equals(1, #doc.messages)
      assert.equals("You", doc.messages[1].role)
      local segment = doc.messages[1].segments[1]
      assert.equals("job_result", segment.kind)
      assert.equals("job_k7x2m", segment.job_id)
      assert.is_nil(segment.status)
      assert.truthy(segment.content:match("47 passed"))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("parses an error job result block", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "**Job Result:** `job_9pfa3` (error)",
        "",
        "```",
        "Exit code 1: FAILED tests/flemma/agent_spec.lua",
        "```",
      })
      local doc = parser.get_parsed_document(bufnr)
      local segment = doc.messages[1].segments[1]
      assert.equals("job_result", segment.kind)
      assert.equals("job_9pfa3", segment.job_id)
      assert.equals("error", segment.status)
      assert.truthy(segment.content:match("Exit code 1"))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("parses an orphan recovery block", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "**Job Result:** `job_lost1` (error)",
        "",
        "```",
        "Job lost: session ended before completion.",
        "```",
      })
      local doc = parser.get_parsed_document(bufnr)
      local segment = doc.messages[1].segments[1]
      assert.equals("job_result", segment.kind)
      assert.equals("job_lost1", segment.job_id)
      assert.equals("error", segment.status)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    describe("to_generic_parts", function()
      it("converts job_result to a GenericJobResultPart", function()
        local nodes = require("flemma.ast.nodes")
        local evaluated_parts = {
          nodes.job_result("job_k7x2m", {
            content = "47 passed, 0 failed",
            start_line = 1,
            end_line = 5,
          }),
        }
        local generic_parts = nodes.to_generic_parts(evaluated_parts, "test.chat")
        assert.equals(1, #generic_parts)
        assert.equals("job_result", generic_parts[1].kind)
        assert.truthy(generic_parts[1].text:match("47 passed"))
        assert.equals("job_k7x2m", generic_parts[1].job_id)
      end)
    end)

    describe("pipeline enrichment", function()
      it("prefixes job result text with the originating tool context", function()
        local context = require("flemma.context")
        local pipeline = require("flemma.pipeline")
        local lines = {
          "@Assistant:",
          "**Tool Use:** `bash` (`tool_01`)",
          "",
          "```json",
          '{"command": "make qa"}',
          "```",
          "",
          "@You:",
          "**Tool Result:** `tool_01` (job=job_k7x2m)",
          "",
          "```",
          "Running in background.",
          "```",
          "",
          "@You:",
          "**Job Result:** `job_k7x2m`",
          "",
          "```",
          "qa: OK",
          "```",
        }

        local prompt =
          pipeline.run(parser.parse_lines(lines), context.from_file("tests/fixtures/doc.chat"), { bufnr = 0 })
        local text = prompt.history[#prompt.history].parts[1].text
        assert.truthy(text:match("%[Job result for bash %(tool_01%)%]"))
        assert.truthy(text:match("qa: OK"))
      end)

      it("prefixes unresolved job result text with job context", function()
        local context = require("flemma.context")
        local pipeline = require("flemma.pipeline")
        local lines = {
          "@You:",
          "**Job Result:** `job_lost1`",
          "",
          "```",
          "late output",
          "```",
        }

        local prompt =
          pipeline.run(parser.parse_lines(lines), context.from_file("tests/fixtures/doc.chat"), { bufnr = 0 })
        local text = prompt.history[1].parts[1].text
        assert.truthy(text:match("%[Job result for unknown tool %(job: job_lost1%)%]"))
        assert.truthy(text:match("late output"))
      end)
    end)
  end)
end)

describe("incremental parse", function()
  local parser = require("flemma.parser")
  local state = require("flemma.state")

  describe("parse_messages extraction", function()
    it("parse_lines produces same result after refactor - simple conversation", function()
      local lines = {
        "@System:",
        "You are helpful.",
        "@You:",
        "Hello",
        "@Assistant:",
        "Hi there!",
        "@You:",
        "Thanks",
      }
      local doc = parser.parse_lines(lines)
      assert.equals(4, #doc.messages)
      assert.equals("System", doc.messages[1].role)
      assert.equals("You", doc.messages[2].role)
      assert.equals("Assistant", doc.messages[3].role)
      assert.equals("You", doc.messages[4].role)
      assert.equals(1, doc.messages[1].position.start_line)
      assert.equals(2, doc.messages[1].position.end_line)
      assert.equals(3, doc.messages[2].position.start_line)
      assert.equals(4, doc.messages[2].position.end_line)
      assert.equals(5, doc.messages[3].position.start_line)
      assert.equals(6, doc.messages[3].position.end_line)
      assert.equals(7, doc.messages[4].position.start_line)
      assert.equals(8, doc.messages[4].position.end_line)
    end)

    it("parse_lines with frontmatter offsets positions correctly", function()
      local lines = {
        "```toml",
        'model = "test"',
        "```",
        "@You:",
        "Hello",
        "@Assistant:",
        "World",
      }
      local doc = parser.parse_lines(lines)
      assert.is_not_nil(doc.frontmatter)
      assert.equals(2, #doc.messages)
      assert.equals(4, doc.messages[1].position.start_line)
      assert.equals(5, doc.messages[1].position.end_line)
      assert.equals(6, doc.messages[2].position.start_line)
      assert.equals(7, doc.messages[2].position.end_line)
    end)
  end)

  describe("create_ast_snapshot_before_send", function()
    local bufnr

    before_each(function()
      package.loaded["flemma.parser"] = nil
      package.loaded["flemma.state"] = nil
      parser = require("flemma.parser")
      state = require("flemma.state")
      bufnr = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
      state.cleanup_buffer_state(bufnr)
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it("captures frontmatter and messages from buffer", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "```toml",
        'model = "test"',
        "```",
        "@System:",
        "You are helpful.",
        "@You:",
        "Hello",
      })

      parser.create_ast_snapshot_before_send(bufnr)

      local bs = state.get_buffer_state(bufnr)
      local snapshot = bs.ast_snapshot_before_send
      assert.is_not_nil(snapshot)
      assert.is_not_nil(snapshot.frontmatter)
      assert.equals("toml", snapshot.frontmatter.language)
      assert.equals(2, #snapshot.messages)
      assert.equals("System", snapshot.messages[1].role)
      assert.equals("You", snapshot.messages[2].role)
      assert.equals(8, snapshot.resume_line)
    end)

    it("sets resume_line to line after last content", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "Hello",
      })

      parser.create_ast_snapshot_before_send(bufnr)

      local snapshot = state.get_buffer_state(bufnr).ast_snapshot_before_send
      assert.equals(3, snapshot.resume_line)
    end)

    it("handles empty buffer", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

      parser.create_ast_snapshot_before_send(bufnr)

      local snapshot = state.get_buffer_state(bufnr).ast_snapshot_before_send
      assert.is_not_nil(snapshot)
      assert.is_nil(snapshot.frontmatter)
      assert.equals(0, #snapshot.messages)
    end)
  end)

  describe("clear_ast_snapshot_before_send", function()
    local bufnr

    before_each(function()
      package.loaded["flemma.parser"] = nil
      package.loaded["flemma.state"] = nil
      parser = require("flemma.parser")
      state = require("flemma.state")
      bufnr = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
      state.cleanup_buffer_state(bufnr)
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it("removes snapshot from buffer state", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "Hello",
      })

      parser.create_ast_snapshot_before_send(bufnr)
      assert.is_not_nil(state.get_buffer_state(bufnr).ast_snapshot_before_send)

      parser.clear_ast_snapshot_before_send(bufnr)
      assert.is_nil(state.get_buffer_state(bufnr).ast_snapshot_before_send)
    end)
  end)

  describe("incremental get_parsed_document", function()
    local bufnr

    before_each(function()
      package.loaded["flemma.parser"] = nil
      package.loaded["flemma.state"] = nil
      parser = require("flemma.parser")
      state = require("flemma.state")
      bufnr = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
      state.cleanup_buffer_state(bufnr)
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    --- Deep-compare two AST documents, ignoring table identity.
    --- Compares kind, role, positions, segment values — everything
    --- that matters for correctness.
    ---@param doc_a flemma.ast.DocumentNode
    ---@param doc_b flemma.ast.DocumentNode
    local function assert_docs_equal(doc_a, doc_b)
      -- Frontmatter
      if doc_a.frontmatter then
        assert.is_not_nil(doc_b.frontmatter, "Both docs should have frontmatter")
        assert.equals(doc_a.frontmatter.language, doc_b.frontmatter.language)
        assert.equals(doc_a.frontmatter.code, doc_b.frontmatter.code)
      else
        assert.is_nil(doc_b.frontmatter, "Neither doc should have frontmatter")
      end

      -- Messages
      assert.equals(#doc_a.messages, #doc_b.messages, "Message count should match")
      for i, msg_a in ipairs(doc_a.messages) do
        local msg_b = doc_b.messages[i]
        assert.equals(msg_a.role, msg_b.role, "Message " .. i .. " role")
        assert.equals(msg_a.position.start_line, msg_b.position.start_line, "Message " .. i .. " start_line")
        assert.equals(msg_a.position.end_line, msg_b.position.end_line, "Message " .. i .. " end_line")
        assert.equals(#msg_a.segments, #msg_b.segments, "Message " .. i .. " segment count")
        for j, seg_a in ipairs(msg_a.segments) do
          local seg_b = msg_b.segments[j]
          local prefix = "Message " .. i .. " segment " .. j
          assert.equals(seg_a.kind, seg_b.kind, prefix .. " kind")
          if seg_a.kind == "text" then
            assert.equals(seg_a.value, seg_b.value, prefix .. " value")
          elseif seg_a.kind == "thinking" then
            assert.equals(seg_a.content, seg_b.content, prefix .. " content")
          elseif seg_a.kind == "tool_use" then
            assert.equals(seg_a.id, seg_b.id, prefix .. " id")
            assert.equals(seg_a.name, seg_b.name, prefix .. " name")
          elseif seg_a.kind == "tool_result" then
            assert.equals(seg_a.tool_use_id, seg_b.tool_use_id, prefix .. " tool_use_id")
            assert.equals(seg_a.content, seg_b.content, prefix .. " content")
          end
        end
      end

      -- Document position
      assert.equals(doc_a.position.start_line, doc_b.position.start_line)
      assert.equals(doc_a.position.end_line, doc_b.position.end_line)

      -- Errors
      assert.equals(#doc_a.errors, #doc_b.errors, "Error count should match")
    end

    it("incremental parse produces same result as full parse", function()
      -- Phase 1: Set up buffer with existing conversation
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "```toml",
        'model = "test"',
        "```",
        "@System:",
        "You are helpful.",
        "@You:",
        "Hello",
      })

      -- Phase 2: Create snapshot (simulates pre-send)
      parser.create_ast_snapshot_before_send(bufnr)

      -- Phase 3: Append new content (simulates streaming)
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, {
        "@Assistant:",
        "Hi there! I can help you.",
        "",
        "What would you like to know?",
      })

      -- Phase 4: Get incremental parse result
      local incremental_doc = parser.get_parsed_document(bufnr)

      -- Phase 5: Clear snapshot and invalidate cache to force full parse
      parser.clear_ast_snapshot_before_send(bufnr)
      state.get_buffer_state(bufnr).ast_cache = nil
      local full_doc = parser.get_parsed_document(bufnr)

      -- Phase 6: Compare
      assert_docs_equal(full_doc, incremental_doc)
    end)

    it("incremental parse handles assistant with tool use", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "List files",
      })

      parser.create_ast_snapshot_before_send(bufnr)

      local line_count = vim.api.nvim_buf_line_count(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, {
        "@Assistant:",
        "",
        "**Tool Use:** `bash` (`call_abc`)",
        "```json",
        '{"command": "ls"}',
        "```",
      })

      local incremental_doc = parser.get_parsed_document(bufnr)

      parser.clear_ast_snapshot_before_send(bufnr)
      state.get_buffer_state(bufnr).ast_cache = nil
      local full_doc = parser.get_parsed_document(bufnr)

      assert_docs_equal(full_doc, incremental_doc)
    end)

    it("incremental parse handles assistant with thinking", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@System:",
        "Be thoughtful.",
        "@You:",
        "What is 2+2?",
      })

      parser.create_ast_snapshot_before_send(bufnr)

      local line_count = vim.api.nvim_buf_line_count(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, {
        "@Assistant:",
        "<thinking>",
        "Let me calculate: 2+2=4",
        "</thinking>",
        "The answer is 4.",
      })

      local incremental_doc = parser.get_parsed_document(bufnr)

      parser.clear_ast_snapshot_before_send(bufnr)
      state.get_buffer_state(bufnr).ast_cache = nil
      local full_doc = parser.get_parsed_document(bufnr)

      assert_docs_equal(full_doc, incremental_doc)
    end)

    it("incremental parse with blank lines between freeze and assistant", function()
      -- The merge step in get_parsed_document fixes up the last frozen
      -- message's end_line so it covers any blank separator lines that were
      -- inserted after the snapshot was taken (e.g., by start_progress).
      -- Incremental and full parse must now agree on @You: end_line.
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "Hello",
      })

      parser.create_ast_snapshot_before_send(bufnr)

      -- start_progress / on_content typically adds a blank line before @Assistant:
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, {
        "",
        "@Assistant:",
        "Response here",
      })

      local incremental_doc = parser.get_parsed_document(bufnr)

      parser.clear_ast_snapshot_before_send(bufnr)
      state.get_buffer_state(bufnr).ast_cache = nil
      local full_doc = parser.get_parsed_document(bufnr)

      -- Message count and roles must match
      assert.equals(#full_doc.messages, #incremental_doc.messages)
      assert.equals("You", incremental_doc.messages[1].role)
      assert.equals("Assistant", incremental_doc.messages[2].role)

      -- All positions now agree between incremental and full parse
      assert.equals(full_doc.messages[1].position.start_line, incremental_doc.messages[1].position.start_line)
      assert.equals(full_doc.messages[1].position.end_line, incremental_doc.messages[1].position.end_line)
      assert.equals(full_doc.messages[2].position.start_line, incremental_doc.messages[2].position.start_line)
      assert.equals(full_doc.messages[2].position.end_line, incremental_doc.messages[2].position.end_line)

      -- Sanity-check absolute values: @You: absorbs the blank separator
      assert.equals(3, incremental_doc.messages[1].position.end_line)
      assert.equals(3, full_doc.messages[1].position.end_line)
    end)

    it("uses changedtick cache even with snapshot", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "Hello",
      })

      parser.create_ast_snapshot_before_send(bufnr)

      local line_count = vim.api.nvim_buf_line_count(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, {
        "@Assistant:",
        "Hi",
      })

      -- First call parses
      local doc1 = parser.get_parsed_document(bufnr)
      -- Second call should return cached (same changedtick)
      local doc2 = parser.get_parsed_document(bufnr)
      assert.equals(doc1, doc2, "Should return same table reference from cache")
    end)

    it("full parse resumes after clear_ast_snapshot_before_send", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "Hello",
      })

      parser.create_ast_snapshot_before_send(bufnr)

      local line_count = vim.api.nvim_buf_line_count(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, {
        "@Assistant:",
        "Hi",
      })

      -- Incremental parse
      parser.get_parsed_document(bufnr)

      -- Clear snapshot
      parser.clear_ast_snapshot_before_send(bufnr)

      -- Append more content
      line_count = vim.api.nvim_buf_line_count(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, {
        "@You:",
        "Thanks",
      })

      -- Should do full parse now (no snapshot)
      local doc = parser.get_parsed_document(bufnr)
      assert.equals(3, #doc.messages)
      assert.equals("You", doc.messages[3].role)
    end)
  end)
end)

describe("parser tool-result segments", function()
  local parser = require("flemma.parser")

  describe("tool result segment parsing", function()
    local function parse_user_message_segments(lines)
      -- Build a @You: message from the given content lines and parse it
      local full_lines = { "@You:" }
      for _, line in ipairs(lines) do
        table.insert(full_lines, line)
      end
      local doc = parser.parse_lines(full_lines)
      assert.equals(1, #doc.messages)
      return doc.messages[1].segments
    end

    it("parses tool result fence content into segments", function()
      -- A tool result with expression should produce text + expression + text segments
      local lines = {
        "**Tool Result:** `tool_123`",
        "```",
        "Hello {{ 1 + 1 }} world",
        "```",
      }
      local segments = parse_user_message_segments(lines)

      assert.equals(1, #segments)
      local tr = segments[1]
      assert.equals("tool_result", tr.kind)
      assert.equals("tool_123", tr.tool_use_id)
      assert.equals("Hello {{ 1 + 1 }} world", tr.content)
      assert.is_true(#tr.segments >= 3)
      assert.equals("text", tr.segments[1].kind)
      assert.equals("expression", tr.segments[2].kind)
      assert.equals("text", tr.segments[3].kind)
    end)

    it("stores raw content for plain text tool results", function()
      local lines = {
        "**Tool Result:** `tool_456`",
        "```",
        '{"key": "value"}',
        "```",
      }
      local segments = parse_user_message_segments(lines)

      local tr = segments[1]
      assert.equals('{"key": "value"}', tr.content)
      assert.equals(1, #tr.segments)
      assert.equals("text", tr.segments[1].kind)
    end)

    it("preserves status blocks without segment parsing", function()
      local lines = {
        "**Tool Result:** `tool_789` (pending)",
        "```",
        "",
        "```",
      }
      local segments = parse_user_message_segments(lines)

      local tr = segments[1]
      assert.equals("pending", tr.status)
      assert.equals(0, #tr.segments)
    end)

    it("handles error tool results", function()
      local lines = {
        "**Tool Result:** `tool_err` (error)",
        "```",
        "Something went wrong",
        "```",
      }
      local segments = parse_user_message_segments(lines)

      local tr = segments[1]
      assert.equals("error", tr.status)
      assert.equals("Something went wrong", tr.content)
    end)
  end)

  describe("parse_segments", function()
    -- Use parse_inline_content as the public API for parse_segments
    local function parse(text)
      return parser.parse_inline_content(text)
    end

    describe("text only", function()
      it("returns single text segment for plain text", function()
        local segments = parse("hello world")
        assert.equals(1, #segments)
        assert.equals("text", segments[1].kind)
        assert.equals("hello world", segments[1].value)
      end)

      it("returns empty table for empty string", function()
        local segments = parse("")
        assert.equals(0, #segments)
      end)

      it("returns empty table for nil", function()
        local segments = parse(nil)
        assert.equals(0, #segments)
      end)
    end)

    describe("expressions {{ }}", function()
      it("parses single expression", function()
        local segments = parse("hello {{ name }} world")
        assert.equals(3, #segments)
        assert.equals("text", segments[1].kind)
        assert.equals("hello ", segments[1].value)
        assert.equals("expression", segments[2].kind)
        assert.equals(" name ", segments[2].code)
        assert.equals("text", segments[3].kind)
        assert.equals(" world", segments[3].value)
      end)

      it("parses expression at start", function()
        local segments = parse("{{ x }}tail")
        assert.equals(2, #segments)
        assert.equals("expression", segments[1].kind)
        assert.equals("text", segments[2].kind)
      end)

      it("parses expression at end", function()
        local segments = parse("head{{ x }}")
        assert.equals(2, #segments)
        assert.equals("text", segments[1].kind)
        assert.equals("expression", segments[2].kind)
      end)

      it("parses multiple expressions", function()
        local segments = parse("{{ a }} and {{ b }}")
        assert.equals(3, #segments)
        assert.equals("expression", segments[1].kind)
        assert.equals("text", segments[2].kind)
        assert.equals("expression", segments[3].kind)
      end)
    end)

    describe("code blocks {% %}", function()
      it("parses single code block", function()
        local segments = parse("before{% if x then %}after")
        assert.equals(3, #segments)
        assert.equals("text", segments[1].kind)
        assert.equals("before", segments[1].value)
        assert.equals("code", segments[2].kind)
        assert.equals(" if x then ", segments[2].code)
        assert.equals("text", segments[3].kind)
        assert.equals("after", segments[3].value)
      end)

      it("parses code block at start", function()
        local segments = parse("{% x = 1 %}rest")
        assert.equals(2, #segments)
        assert.equals("code", segments[1].kind)
        assert.equals("text", segments[2].kind)
      end)

      it("parses code block at end", function()
        local segments = parse("start{% end %}")
        assert.equals(2, #segments)
        assert.equals("text", segments[1].kind)
        assert.equals("code", segments[2].kind)
      end)

      it("parses mixed expressions and code blocks", function()
        local segments = parse("{% if x then %}{{ name }}{% end %}")
        assert.equals(3, #segments)
        assert.equals("code", segments[1].kind)
        assert.equals(" if x then ", segments[1].code)
        assert.equals("expression", segments[2].kind)
        assert.equals(" name ", segments[2].code)
        assert.equals("code", segments[3].kind)
        assert.equals(" end ", segments[3].code)
      end)
    end)

    describe("trim markers", function()
      it("parses {{- expression }}", function()
        local segments = parse("text {{- name }}")
        assert.equals(2, #segments)
        assert.equals("expression", segments[2].kind)
        assert.is_true(segments[2].trim_before)
        assert.is_nil(segments[2].trim_after)
      end)

      it("parses {{ expression -}}", function()
        local segments = parse("{{ name -}} text")
        assert.equals(2, #segments)
        assert.equals("expression", segments[1].kind)
        assert.is_nil(segments[1].trim_before)
        assert.is_true(segments[1].trim_after)
      end)

      it("parses {{- expression -}}", function()
        local segments = parse("{{- name -}}")
        assert.equals(1, #segments)
        assert.equals("expression", segments[1].kind)
        assert.is_true(segments[1].trim_before)
        assert.is_true(segments[1].trim_after)
      end)

      it("parses {%- code -%}", function()
        local segments = parse("{%- if x -%}")
        assert.equals(1, #segments)
        assert.equals("code", segments[1].kind)
        assert.is_true(segments[1].trim_before)
        assert.is_true(segments[1].trim_after)
      end)

      it("parses {% code -%} (trim after only)", function()
        local segments = parse("{% if x -%}")
        assert.equals(1, #segments)
        assert.equals("code", segments[1].kind)
        assert.is_nil(segments[1].trim_before)
        assert.is_true(segments[1].trim_after)
      end)
    end)

    describe("position tracking", function()
      it("tracks expression position", function()
        local segments = parse("ab{{ x }}cd")
        local expr = segments[2]
        assert.equals("expression", expr.kind)
        assert.is_not_nil(expr.position)
        -- base_line defaults to 0, char_to_line_col(3) -> line=0, col=3
        assert.equals(3, expr.position.start_col)
      end)

      it("tracks code block position", function()
        local segments = parse("ab{% y %}cd")
        local code = segments[2]
        assert.equals("code", code.kind)
        assert.is_not_nil(code.position)
      end)
    end)

    describe("string-aware expression parsing", function()
      it("parses expression with }} inside string (motivating case)", function()
        local segments = parse('{{ "email={{ customer.email }}" }}')
        assert.equals(1, #segments)
        assert.equals("expression", segments[1].kind)
        assert.equals(' "email={{ customer.email }}" ', segments[1].code)
      end)

      it("parses expression containing table literal", function()
        local segments = parse('{{ {key = "value"} }}')
        assert.equals(1, #segments)
        assert.equals("expression", segments[1].kind)
        assert.equals(' {key = "value"} ', segments[1].code)
      end)

      it("parses expression with string then code after it", function()
        local segments = parse('{{ "contains }}" .. other }}')
        assert.equals(1, #segments)
        assert.equals("expression", segments[1].kind)
        assert.equals(' "contains }}" .. other ', segments[1].code)
      end)

      it("parses code block with %} inside string", function()
        local segments = parse('{% local x = "has %}" %}')
        assert.equals(1, #segments)
        assert.equals("code", segments[1].kind)
        assert.equals(' local x = "has %}" ', segments[1].code)
      end)

      it("parses expression with long string containing }}", function()
        local segments = parse("{{ [[long string }}]] }}")
        assert.equals(1, #segments)
        assert.equals("expression", segments[1].kind)
        assert.equals(" [[long string }}]] ", segments[1].code)
      end)

      it("parses multi-line expression", function()
        local segments = parse("{{ x +\n y }}")
        assert.equals(1, #segments)
        assert.equals("expression", segments[1].kind)
        assert.equals(" x +\n y ", segments[1].code)
      end)

      it("parses mixed expressions and code with strings containing delimiters", function()
        local segments = parse('{% if "}}x" then %}{{ "}}" }}{% end %}')
        assert.equals(3, #segments)
        assert.equals("code", segments[1].kind)
        assert.equals(' if "}}x" then ', segments[1].code)
        assert.equals("expression", segments[2].kind)
        assert.equals(' "}}" ', segments[2].code)
        assert.equals("code", segments[3].kind)
        assert.equals(" end ", segments[3].code)
      end)

      it("parses expression with table adjacent to closing delimiter", function()
        local segments = parse("{{ {1,2,3}}}")
        assert.equals(1, #segments)
        assert.equals("expression", segments[1].kind)
        assert.equals(" {1,2,3}", segments[1].code)
      end)

      it("preserves text around string-aware expressions", function()
        local segments = parse('before {{ "}}" }} after')
        assert.equals(3, #segments)
        assert.equals("text", segments[1].kind)
        assert.equals("before ", segments[1].value)
        assert.equals("expression", segments[2].kind)
        assert.equals(' "}}" ', segments[2].code)
        assert.equals("text", segments[3].kind)
        assert.equals(" after", segments[3].value)
      end)
    end)
  end)
end)

describe("parser malformed JSON", function()
  local parser = require("flemma.parser")

  describe("parser malformed tool_use JSON", function()
    it("skips malformed tool_use without eating subsequent tool_use blocks", function()
      local lines = {
        "@Assistant:",
        "**Tool Use:** `tool_a` (`id_a`)",
        "",
        "```json",
        "{bad json here",
        "```",
        "",
        "**Tool Use:** `tool_b` (`id_b`)",
        "",
        "```json",
        '{"valid": true}',
        "```",
      }
      local doc = parser.parse_lines(lines)
      assert.equals(1, #doc.messages)

      local tool_uses = {}
      for _, seg in ipairs(doc.messages[1].segments) do
        if seg.kind == "tool_use" then
          table.insert(tool_uses, seg)
        end
      end

      assert.equals(1, #tool_uses, "expected tool_b to survive")
      assert.equals("tool_b", tool_uses[1].name)
      assert.equals("id_b", tool_uses[1].id)
      assert.is_true(tool_uses[1].input.valid)
    end)

    it("emits diagnostic for malformed JSON", function()
      local lines = {
        "@Assistant:",
        "**Tool Use:** `broken` (`id_broken`)",
        "",
        "```json",
        "{not valid}",
        "```",
      }
      local doc = parser.parse_lines(lines)

      assert.is_true(#doc.errors > 0, "expected a diagnostic for malformed JSON")
      local found = false
      for _, d in ipairs(doc.errors) do
        if d.type == "tool_use" and d.error:find("parse") then
          found = true
        end
      end
      assert.is_true(found, "expected a tool_use parse diagnostic")
    end)

    it("parses tool_use blocks after malformed one in the same message", function()
      local lines = {
        "@Assistant:",
        "**Tool Use:** `first` (`id_1`)",
        "",
        "```json",
        '{"good": 1}',
        "```",
        "",
        "**Tool Use:** `bad` (`id_2`)",
        "",
        "```json",
        "{broken",
        "```",
        "",
        "**Tool Use:** `third` (`id_3`)",
        "",
        "```json",
        '{"also_good": 2}',
        "```",
      }
      local doc = parser.parse_lines(lines)
      assert.equals(1, #doc.messages)

      local names = {}
      for _, seg in ipairs(doc.messages[1].segments) do
        if seg.kind == "tool_use" then
          table.insert(names, seg.name)
        end
      end

      assert.equals(2, #names, "expected first and third to parse")
      assert.equals("first", names[1])
      assert.equals("third", names[2])
    end)
  end)
end)
