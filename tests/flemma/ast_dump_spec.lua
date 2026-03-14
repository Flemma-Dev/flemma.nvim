describe("flemma.ast.dump", function()
  local dump
  local nodes

  before_each(function()
    package.loaded["flemma.ast.dump"] = nil
    package.loaded["flemma.ast.nodes"] = nil
    dump = require("flemma.ast.dump")
    nodes = require("flemma.ast.nodes")
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

    it("renders expression segment with inline code", function()
      local seg = nodes.expression("os.date()", { start_line = 7, end_line = 7, start_col = 12, end_col = 28 })
      local lines = dump.tree(seg)
      assert.equals('expression [7:12 - 7:28] code="os.date()"', lines[1])
      assert.equals(1, #lines)
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
      local seg = nodes.tool_result("call_123", "file contents here", {
        is_error = false,
        status = "approved",
        start_line = 9,
        end_line = 20,
      })
      local lines = dump.tree(seg)
      assert.is_truthy(lines[1]:find('tool_use_id="call_123"'))
      assert.is_truthy(lines[1]:find("is_error=false"))
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
      assert.equals("    text [5 - 5]", lines[6])
      assert.equals("      value:", lines[7])
      assert.equals("        Hello", lines[8])
      assert.equals('  message [6 - 7] role="Assistant"', lines[9])
      assert.equals("    text [7 - 7]", lines[10])
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
