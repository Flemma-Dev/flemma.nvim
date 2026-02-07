local ast = require("flemma.ast")
local ctx = require("flemma.context")
local parser = require("flemma.parser")
local processor = require("flemma.processor")
local pipeline = require("flemma.pipeline")

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

    local child = ctx.for_include(ext, "/tmp/child.txt")
    assert.equals("/tmp/child.txt", child:get_filename())
    local stack = child:get_include_stack()
    assert.is_true(#stack >= 2)
  end)

  it("creates eval environment from context", function()
    local base = ctx.from_file("/tmp/flemma.chat")
    local ext = ctx.extend(base, { foo = "bar" })
    local env = ctx.to_eval_env(ext)
    assert.equals("/tmp/flemma.chat", env.__filename)
    assert.equals("bar", env.foo)
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
      "@You: Hello {{1+1}} world @./a.txt.",
      "@Assistant: Ok",
    }
    local doc = parser.parse_lines(lines)
    local m1 = doc.messages[1]
    assert.equals("You", m1.role)
    local kinds = {}
    for _, s in ipairs(m1.segments) do
      kinds[#kinds + 1] = s.kind
    end
    -- Expected: text("Hello "), expression, text(" world "), file_reference, text(".")
    assert.equals("text", kinds[1])
    assert.equals("expression", kinds[2])
    assert.equals("text", kinds[3])
    assert.equals("file_reference", kinds[4])
  end)

  it("parses MIME override and URL-encoded filenames", function()
    local lines = {
      "@You: See @./my%20file.bin;type=image/png!",
    }
    local doc = parser.parse_lines(lines)
    local fr = doc.messages[1].segments[2]
    assert.equals("file_reference", fr.kind)
    assert.equals("image/png", fr.mime_override)
    assert.is_true(fr.path:match("my file.bin") ~= nil)
    assert.equals("!", fr.trailing_punct)
  end)

  it("parses thinking tags in Assistant messages", function()
    local lines = {
      "@Assistant: I think",
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

  it("parses thinking tags with line positions when on separate lines", function()
    local lines = {
      "@Assistant: Here is my response",
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
    assert.equals(2, thinking_seg.position.start_line, "Thinking should start at line 2")
    assert.equals(5, thinking_seg.position.end_line, "Thinking should end at line 5")
  end)
end)

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
      "@You: File1: {{ 'hello' }} and File2: @./a.txt.",
    }
    local doc = parser.parse_lines(lines)
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
      "@You: See @./my%20file.txt!",
    }
    local doc = parser.parse_lines(lines)
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
      "@You: Img: @./sample.bin;type=image/png",
    }
    local doc = parser.parse_lines(lines)
    local out = processor.evaluate(doc, base2)
    local parts = out.messages[1].parts
    assert.equals("file", parts[2].kind)
    assert.equals("image/png", parts[2].mime_type)
  end)

  it("handles circular includes gracefully", function()
    local lines = {
      "@You: {{ include('tests/fixtures/loop1.txt') }}",
    }
    local b = ctx.from_file("tests/fixtures/loop1.txt")
    local doc = parser.parse_lines(lines)
    local ok = pcall(processor.evaluate, doc, b)
    assert.is_true(ok, "Processor should not crash; include() error handled in expression eval as text")
  end)

  it("resolves @./ file references inside included content", function()
    local f = io.open("tests/fixtures/with_ref.txt", "w")
    f:write("Content: @./a.txt here")
    f:close()

    local lines = {
      "@You: {{ include('./with_ref.txt') }}",
    }
    local b = ctx.from_file("tests/fixtures/doc.chat")
    local doc = parser.parse_lines(lines)
    local out = processor.evaluate(doc, b)
    -- include() should have resolved @./a.txt to its content
    local text_parts = {}
    for _, p in ipairs(out.messages[1].parts) do
      if p.kind == "text" then
        table.insert(text_parts, p.text)
      end
    end
    local result = table.concat(text_parts, "")
    assert.is_true(result:match("hello A") ~= nil, "include() should have resolved @./a.txt")
  end)

  it("does not process expressions or file refs in @Assistant messages", function()
    local base = ctx.from_file("tests/fixtures/doc.chat")
    local lines = {
      "@Assistant: {{ 1 + 1 }} and @./a.txt should be literal",
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
      "@You: {{ 1 / 'x' }}",
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
      "@Assistant: I think",
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
      { kind = "unsupported_file", raw = "./unknown.bin" },
    })
    assert.equals("text", parts[1].kind)
    assert.equals("image", parts[2].kind)
    assert.equals("pdf", parts[3].kind)
    assert.equals("text_file", parts[4].kind)
    assert.equals("hello", parts[4].text)
    assert.equals("unsupported_file", parts[5].kind)
  end)
end)

describe("Pipeline Integration", function()
  it("runs full pipeline with system message", function()
    local lines = {
      "@System: You are helpful.",
      "@You: Hello",
      "@Assistant: Hi there!",
    }
    local prompt = pipeline.run(lines, ctx.from_file("tests/fixtures/doc.chat"))
    assert.equals("You are helpful.", prompt.system)
    assert.equals(2, #prompt.history)
  end)

  it("runs full pipeline with frontmatter, expressions, and files", function()
    local lines = {
      "```lua",
      "name = 'World'",
      "```",
      "@You: Hello {{ name }}! See @./tests/fixtures/a.txt",
      "@Assistant: Got it",
    }

    local prompt = pipeline.run(lines, ctx.from_file("tests/fixtures/doc.chat"))

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
      "@System: You are helpful.",
      "@You: Hello",
      "@Assistant: Hi there!",
    }
    local prompt = pipeline.run(lines, ctx.from_file("tests/fixtures/doc.chat"))
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
      "@You: Hello {{ name }}! See @./tests/fixtures/a.txt",
      "@Assistant: Got it",
    }

    local prompt = pipeline.run(lines, ctx.from_file("tests/fixtures/doc.chat"))
    local req = provider:build_request(prompt, {})
    assert.equals("user", req.messages[1].role)
  end)
end)
