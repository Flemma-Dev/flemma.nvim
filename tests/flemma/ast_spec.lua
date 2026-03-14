local ast = require("flemma.ast")
local ctx = require("flemma.context")
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
    local env = ctx.to_eval_env(ext)
    assert.equals("/tmp/flemma.chat", env.__filename)
    assert.equals("/tmp", env.__dirname)
    assert.equals("bar", env.foo)
  end)

  it("sets __dirname to nil when context has no filename", function()
    local empty = ctx.clone(nil)
    local env = ctx.to_eval_env(empty)
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
    -- Expected: text("File1: "), text("hello"), text(" and File2: "), file, text(".")
    assert.equals("text", kinds[1])
    assert.equals("text", kinds[2])
    assert.equals("file", kinds[4])
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
    local prompt = pipeline.run(parser.parse_lines(lines), ctx.from_file("tests/fixtures/doc.chat"))
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
    local prompt = pipeline.run(doc, ctx.from_file("tests/fixtures/doc.chat"))

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
    local anthropic = require("flemma.provider.providers.anthropic")
    local provider = anthropic.new({ model = "claude-3-haiku-20240307", max_tokens = 256, temperature = 0 })

    local lines = {
      "@System:",
      "You are helpful.",
      "@You:",
      "Hello",
      "@Assistant:",
      "Hi there!",
    }
    local prompt = pipeline.run(parser.parse_lines(lines), ctx.from_file("tests/fixtures/doc.chat"))
    local req = provider:build_request(prompt, {})
    assert.is_not_nil(req.model)
    assert.equals("table", type(req.messages))
    assert.equals(2, #req.messages)
  end)

  it("builds OpenAI request from pipeline output", function()
    local openai = require("flemma.provider.providers.openai")
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
    local prompt = pipeline.run(doc, context)
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
    package.loaded["flemma.provider.providers.anthropic"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.tools.registry"] = nil
    package.loaded["flemma.tools.approval"] = nil
    anthropic = require("flemma.provider.providers.anthropic")
    local tools = require("flemma.tools")
    tools.clear()
  end)

  ---Build an Anthropic API request body from raw buffer lines.
  ---@param buffer_lines string[]
  ---@return table request_body
  local function build_request_from_lines(buffer_lines)
    local doc = parser.parse_lines(buffer_lines)
    local prompt = pipeline.run(doc)
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
