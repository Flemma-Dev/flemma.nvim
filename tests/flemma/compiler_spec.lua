local ast = require("flemma.ast")

describe("flemma.templating.compiler", function()
  local compiler

  before_each(function()
    package.loaded["flemma.templating.compiler"] = nil
    package.loaded["flemma.ast"] = nil
    package.loaded["flemma.ast.nodes"] = nil
    compiler = require("flemma.templating.compiler")
  end)

  describe("compile", function()
    it("compiles text-only segments", function()
      local segments = { ast.text("hello world", { start_line = 1 }) }
      local result = compiler.compile(segments)
      assert.is_nil(result.error)
      assert.is_string(result.source)
      assert.is_table(result.line_map)
      assert.is_table(result.segments)
      assert.truthy(result.source:find("__emit%("))
    end)

    it("compiles expression segments with pcall wrapper", function()
      local segments = { ast.expression(" name ", { start_line = 1 }) }
      local result = compiler.compile(segments)
      assert.is_nil(result.error)
      assert.truthy(result.source:find("pcall"))
      assert.truthy(result.source:find("__emit"))
    end)

    it("compiles code segments as raw code", function()
      local segments = { ast.code(" if true then ", { start_line = 1 }) }
      local result = compiler.compile(segments)
      assert.truthy(result.source:find("if true then"))
    end)

    it("compiles structural segments as __emit_part calls", function()
      local segments = {
        ast.text("before", { start_line = 1 }),
        ast.tool_result("id123", { content = "content", start_line = 2, end_line = 3 }),
        ast.text("after", { start_line = 4 }),
      }
      local result = compiler.compile(segments)
      assert.truthy(result.source:find("__emit_part"))
      assert.truthy(result.source:find("__segments%[2%]"))
    end)

    it("builds line map entries", function()
      local segments = {
        ast.text("line1", { start_line = 5 }),
        ast.code(" x = 1 ", { start_line = 7 }),
      }
      local result = compiler.compile(segments)
      assert.is_true(#result.line_map > 0)
      -- First entry should map to the text segment's line
      assert.equals(5, result.line_map[1].lnum)
    end)

    it("handles empty segment list", function()
      local result = compiler.compile({})
      assert.is_nil(result.error)
      assert.is_string(result.source)
    end)

    it("detects syntax error in code block", function()
      local segments = { ast.code(" iff true then ", { start_line = 3 }) }
      local result = compiler.compile(segments)
      assert.is_string(result.error)
    end)
  end)

  describe("execute", function()
    it("executes text-only template", function()
      local segments = { ast.text("hello world", { start_line = 1 }) }
      local result = compiler.compile(segments)
      local env = { __filename = "test.chat" }
      local parts, diagnostics = compiler.execute(result, env)
      assert.equals(1, #parts)
      assert.equals("text", parts[1].kind)
      assert.equals("hello world", parts[1].text)
      assert.equals(0, #diagnostics)
    end)

    it("executes expression with env variable", function()
      local segments = {
        ast.text("hello ", { start_line = 1 }),
        ast.expression(" name ", { start_line = 1 }),
      }
      local result = compiler.compile(segments)
      local env = { name = "Alice", __filename = "test.chat" }
      local parts, diagnostics = compiler.execute(result, env)
      assert.equals(0, #diagnostics)
      local text = ""
      for _, p in ipairs(parts) do
        if p.kind == "text" then
          text = text .. p.text
        end
      end
      assert.equals("hello Alice", text)
    end)

    it("expression error emits raw expression text", function()
      local segments = {
        ast.text("before", { start_line = 1 }),
        ast.expression(" undefined_var.field ", { start_line = 2 }),
        ast.text("after", { start_line = 3 }),
      }
      local result = compiler.compile(segments)
      local env = { __filename = "test.chat" }
      local parts, _ = compiler.execute(result, env)
      local text = ""
      for _, p in ipairs(parts) do
        if p.kind == "text" then
          text = text .. p.text
        end
      end
      assert.truthy(text:find("{{ undefined_var.field }}"))
      assert.truthy(text:find("before"))
      assert.truthy(text:find("after"))
    end)

    it("code block controls output", function()
      local segments = {
        ast.code(" if true then ", { start_line = 1 }),
        ast.text("visible", { start_line = 2 }),
        ast.code(" end ", { start_line = 3 }),
      }
      local result = compiler.compile(segments)
      local env = { __filename = "test.chat" }
      local parts, diagnostics = compiler.execute(result, env)
      assert.equals(0, #diagnostics)
      assert.equals(1, #parts)
      assert.equals("visible", parts[1].text)
    end)

    it("code block false branch omits text", function()
      local segments = {
        ast.code(" if false then ", { start_line = 1 }),
        ast.text("hidden", { start_line = 2 }),
        ast.code(" end ", { start_line = 3 }),
      }
      local result = compiler.compile(segments)
      local env = { __filename = "test.chat" }
      local parts, diagnostics = compiler.execute(result, env)
      assert.equals(0, #diagnostics)
      assert.equals(0, #parts)
    end)

    it("structural segments pass through", function()
      local segments = {
        ast.text("before", { start_line = 1 }),
        ast.tool_result("id1", {
          content = "result content",
          start_line = 2,
          end_line = 4,
        }),
        ast.text("after", { start_line = 5 }),
      }
      local result = compiler.compile(segments)
      local env = { __filename = "test.chat" }
      local parts, diagnostics = compiler.execute(result, env)
      assert.equals(0, #diagnostics)
      assert.equals(3, #parts)
      assert.equals("text", parts[1].kind)
      assert.equals("tool_result", parts[2].kind)
      assert.equals("id1", parts[2].tool_use_id)
      assert.equals("text", parts[3].kind)
    end)

    it("code block wrapping structural segment", function()
      local segments = {
        ast.code(" if show then ", { start_line = 1 }),
        ast.tool_result("id1", { content = "content", start_line = 2, end_line = 3 }),
        ast.code(" end ", { start_line = 4 }),
      }
      local result = compiler.compile(segments)
      local env = { show = true, __filename = "test.chat" }
      local parts, _ = compiler.execute(result, env)
      assert.equals(1, #parts)
      assert.equals("tool_result", parts[1].kind)

      -- Now with show = false
      local env2 = { show = false, __filename = "test.chat" }
      local parts2, _ = compiler.execute(result, env2)
      assert.equals(0, #parts2)
    end)

    it("nil expression produces no output", function()
      local segments = { ast.expression(" nil_var ", { start_line = 1 }) }
      local result = compiler.compile(segments)
      local env = { __filename = "test.chat" }
      local parts, _ = compiler.execute(result, env)
      local text = ""
      for _, p in ipairs(parts) do
        if p.kind == "text" then
          text = text .. p.text
        end
      end
      assert.equals("", text)
    end)

    it("table expression is JSON-encoded", function()
      local segments = { ast.expression(" {a = 1} ", { start_line = 1 }) }
      local result = compiler.compile(segments)
      local env = { __filename = "test.chat" }
      local parts, _ = compiler.execute(result, env)
      assert.equals(1, #parts)
      assert.truthy(parts[1].text:find('"a"'))
    end)

    it("runtime error in code block produces diagnostic", function()
      local segments = {
        ast.code(" error('boom') ", { start_line = 5 }),
      }
      local result = compiler.compile(segments)
      local env = { __filename = "test.chat" }
      local parts, diagnostics = compiler.execute(result, env)
      assert.equals(0, #parts)
      assert.is_true(#diagnostics > 0)
      assert.equals("template", diagnostics[1].type)
      assert.truthy(diagnostics[1].error:find("boom"))
    end)

    it("syntax error in code block produces diagnostic", function()
      local segments = { ast.code(" iff true then ", { start_line = 3 }) }
      local result = compiler.compile(segments)
      local env = { __filename = "test.chat" }
      local parts, diagnostics = compiler.execute(result, env)
      assert.equals(0, #parts)
      assert.is_true(#diagnostics > 0)
      assert.equals("template", diagnostics[1].type)
    end)

    it("for loop repeats text", function()
      local segments = {
        ast.code(" for i = 1, 3 do ", { start_line = 1 }),
        ast.text("x", { start_line = 2 }),
        ast.code(" end ", { start_line = 3 }),
      }
      local result = compiler.compile(segments)
      local env = { __filename = "test.chat" }
      local parts, _ = compiler.execute(result, env)
      local text = ""
      for _, p in ipairs(parts) do
        if p.kind == "text" then
          text = text .. p.text
        end
      end
      assert.equals("xxx", text)
    end)
  end)

  describe("print", function()
    ---@param segments flemma.ast.Segment[]
    ---@param env? table
    ---@return string text Concatenated text output
    local function render(segments, env)
      env = env or { __filename = "test.chat" }
      local result = compiler.compile(segments)
      assert.is_nil(result.error, "compile error: " .. (result.error or ""))
      local parts, diagnostics = compiler.execute(result, env)
      assert.equals(0, #diagnostics, "unexpected diagnostics: " .. vim.inspect(diagnostics))
      local texts = {}
      for _, p in ipairs(parts) do
        if p.kind == "text" then
          table.insert(texts, p.text)
        end
      end
      return table.concat(texts)
    end

    local pos = { start_line = 1 }

    it("emits a single string argument into template output", function()
      local output = render({ ast.code(" print('hello') ", pos) })
      assert.equals("hello", output)
    end)

    it("concatenates multiple arguments without separators", function()
      local output = render({ ast.code(" print('hello', ' ', 'world') ", pos) })
      assert.equals("hello world", output)
    end)

    it("does not append a trailing newline", function()
      local output = render({
        ast.code(" print('first') ", pos),
        ast.code(" print('second') ", pos),
      })
      assert.equals("firstsecond", output)
    end)

    it("coerces numbers via tostring", function()
      local output = render({ ast.code(" print(42) ", pos) })
      assert.equals("42", output)
    end)

    it("produces no output when called with no arguments", function()
      local output = render({
        ast.text("before", pos),
        ast.code(" print() ", pos),
        ast.text("after", pos),
      })
      assert.equals("beforeafter", output)
    end)

    it("interleaves with text and expression segments", function()
      local output = render({
        ast.text("Hello, ", pos),
        ast.code(" print('world') ", pos),
        ast.text("!", pos),
      })
      assert.equals("Hello, world!", output)
    end)

    it("builds a list in a loop", function()
      local output = render({
        ast.code(" local rules = {'Be concise', 'Be direct', 'Be helpful'} ", pos),
        ast.code(" for i, rule in ipairs(rules) do ", pos),
        ast.code(" print(i .. '. ' .. rule .. '\\n') ", pos),
        ast.code(" end ", pos),
      }, { ipairs = ipairs, __filename = "test.chat" })
      assert.equals("1. Be concise\n2. Be direct\n3. Be helpful\n", output)
    end)
  end)

  describe("capture mechanism", function()
    it("compiles compound tool_result with capture open/close", function()
      local inner = {
        ast.text("hello", { start_line = 2 }),
      }
      local segments = {
        ast.text("before", { start_line = 1 }),
        ast.tool_result("id123", { segments = inner, content = "hello", start_line = 2, end_line = 3 }),
        ast.text("after", { start_line = 4 }),
      }
      local result = compiler.compile(segments)
      assert.is_nil(result.error)
      assert.truthy(result.source:find("__capture_open"))
      assert.truthy(result.source:find("__capture_close"))
      assert.truthy(result.source:find("__emit_part"))
    end)

    it("compiles opaque tool_result as structural pass-through", function()
      local segments = {
        ast.tool_result("id456", { content = "plain text", start_line = 1, end_line = 2 }),
      }
      local result = compiler.compile(segments)
      assert.is_nil(result.error)
      assert.truthy(result.source:find("__emit_part"))
      assert.falsy(result.source:find("__capture_open"))
    end)

    it("generates unique tmp vars for nested captures", function()
      local inner1 = { ast.text("a", { start_line = 2 }) }
      local inner2 = { ast.text("b", { start_line = 5 }) }
      local segments = {
        ast.tool_result("id1", { segments = inner1, content = "a", start_line = 1, end_line = 3 }),
        ast.tool_result("id2", { segments = inner2, content = "b", start_line = 4, end_line = 6 }),
      }
      local result = compiler.compile(segments)
      assert.is_nil(result.error)
      assert.truthy(result.source:find("__tmp1"))
      assert.truthy(result.source:find("__tmp2"))
    end)
  end)

  describe("capture execution", function()
    it("captures parts into tool_result envelope", function()
      local inner = {
        ast.text("captured text", { start_line = 2 }),
      }
      local segments = {
        ast.tool_result("id_cap", {
          segments = inner,
          content = "captured text",
          is_error = false,
          start_line = 1,
          end_line = 3,
        }),
      }
      local result = compiler.compile(segments)
      assert.is_nil(result.error)

      local env = { pcall = pcall, tostring = tostring, error = error }
      local parts, _ = compiler.execute(result, env)

      assert.equals(1, #parts)
      assert.equals("tool_result", parts[1].kind)
      assert.equals("id_cap", parts[1].tool_use_id)
      assert.is_false(parts[1].is_error)
      assert.equals("captured text", parts[1].content)
      assert.equals(1, #parts[1].parts)
      assert.equals("text", parts[1].parts[1].kind)
      assert.equals("captured text", parts[1].parts[1].text)
    end)

    it("produces empty parts for empty capture", function()
      local segments = {
        ast.tool_result("id_empty", {
          segments = {},
          content = "",
          start_line = 1,
          end_line = 2,
        }),
      }
      local result = compiler.compile(segments)
      local env = { pcall = pcall, tostring = tostring, error = error }
      local parts, _ = compiler.execute(result, env)

      -- Empty segments = opaque pass-through, not a capture
      assert.equals(1, #parts)
      assert.equals("tool_result", parts[1].kind)
      assert.equals("", parts[1].content)
    end)
  end)

  describe("apply_trim (via compile+execute)", function()
    ---@param segments flemma.ast.Segment[]
    ---@param env? table
    ---@return string text Concatenated text output
    local function render(segments, env)
      env = env or { __filename = "test.chat" }
      local result = compiler.compile(segments)
      assert.is_nil(result.error, "compile error: " .. (result.error or ""))
      local parts, diagnostics = compiler.execute(result, env)
      assert.equals(0, #diagnostics, "unexpected diagnostics: " .. vim.inspect(diagnostics))
      local texts = {}
      for _, p in ipairs(parts) do
        if p.kind == "text" then
          table.insert(texts, p.text)
        end
      end
      return table.concat(texts)
    end

    local pos = { start_line = 1 }

    -- ── trim_before: next segment has trim_before=true ──────────────

    it("trim_before strips trailing whitespace+newline from preceding text", function()
      local output = render({
        ast.text("hello  \n  ", pos),
        ast.expression(" 'world' ", pos, { trim_before = true }),
      })
      assert.equals("helloworld", output)
    end)

    it("trim_before strips trailing tabs+newline", function()
      local output = render({
        ast.text("hello\t\n\t\t", pos),
        ast.code(" -- noop ", pos, { trim_before = true }),
        ast.text("after", pos),
      })
      assert.equals("helloafter", output)
    end)

    it("trim_before strips only last newline and surrounding whitespace", function()
      local output = render({
        ast.text("line1\nline2\n  ", pos),
        ast.expression(" 'x' ", pos, { trim_before = true }),
      })
      -- Should strip "  \n  " from end, preserving "line1\nline2"
      assert.equals("line1\nline2x", output)
    end)

    it("trim_before falls back to stripping all trailing whitespace when no newline", function()
      local output = render({
        ast.text("hello   ", pos),
        ast.expression(" 'world' ", pos, { trim_before = true }),
      })
      assert.equals("helloworld", output)
    end)

    it("trim_before on all-whitespace text produces empty", function()
      local output = render({
        ast.text("  \n  ", pos),
        ast.expression(" 'x' ", pos, { trim_before = true }),
      })
      assert.equals("x", output)
    end)

    it("trim_before with no preceding text is a no-op", function()
      local output = render({
        ast.expression(" 'hello' ", pos, { trim_before = true }),
      })
      assert.equals("hello", output)
    end)

    -- ── trim_after: previous segment has trim_after=true ────────────

    it("trim_after strips leading newline+whitespace from following text", function()
      local output = render({
        ast.expression(" 'hello' ", pos, { trim_after = true }),
        ast.text("\n  world", pos),
      })
      assert.equals("helloworld", output)
    end)

    it("trim_after strips leading tabs+newline", function()
      local output = render({
        ast.code(" -- noop ", pos, { trim_after = true }),
        ast.text("\n\t\tafter", pos),
      })
      assert.equals("after", output)
    end)

    it("trim_after strips only first newline and surrounding whitespace", function()
      local output = render({
        ast.expression(" 'x' ", pos, { trim_after = true }),
        ast.text("\n  line1\nline2", pos),
      })
      -- Should strip "\n  " from start, preserving "line1\nline2"
      assert.equals("xline1\nline2", output)
    end)

    it("trim_after falls back to stripping all leading whitespace when no newline", function()
      local output = render({
        ast.expression(" 'hello' ", pos, { trim_after = true }),
        ast.text("   world", pos),
      })
      assert.equals("helloworld", output)
    end)

    it("trim_after on all-whitespace text produces empty", function()
      local output = render({
        ast.expression(" 'x' ", pos, { trim_after = true }),
        ast.text("  \n  ", pos),
      })
      assert.equals("x", output)
    end)

    it("trim_after with no following text is a no-op", function()
      local output = render({
        ast.expression(" 'hello' ", pos, { trim_after = true }),
      })
      assert.equals("hello", output)
    end)

    -- ── Both trims ──────────────────────────────────────────────────

    it("code block with both trims removes surrounding whitespace", function()
      local output = render({
        ast.text("before\n  ", pos),
        ast.code(" if true then ", pos, { trim_before = true, trim_after = true }),
        ast.text("\n  middle\n  ", pos),
        ast.code(" end ", pos, { trim_before = true, trim_after = true }),
        ast.text("\nafter", pos),
      })
      -- trim_before on `if` strips "before\n  " → "before"
      -- trim_after on `if` strips "\n  middle\n  " → "middle\n  "
      -- trim_before on `end` strips "middle\n  " → "middle"
      -- trim_after on `end` strips "\nafter" → "after"
      assert.equals("beforemiddleafter", output)
    end)

    it("expression with both trims on its own line", function()
      local output = render({
        ast.text("line1\n  ", pos),
        ast.expression(" 'VALUE' ", pos, { trim_before = true, trim_after = true }),
        ast.text("\nline2", pos),
      })
      assert.equals("line1VALUEline2", output)
    end)

    it("text between two trimming expressions is fully trimmed", function()
      local output = render({
        ast.expression(" 'A' ", pos, { trim_after = true }),
        ast.text("\n  \n  ", pos),
        ast.expression(" 'B' ", pos, { trim_before = true }),
      })
      -- trim_after A strips leading "\n  " → "\n  "
      -- trim_before B strips trailing "\n  " → ""
      -- Wait, let me think more carefully.
      -- Text is "\n  \n  "
      -- trim_after from A: gsub("^[\t ]*\n[\t ]*", "") on "\n  \n  " → "\n  " (strips first "\n  ")
      -- trim_before from B: gsub("[\t ]*\n[\t ]*$", "") on "\n  " → "" (strips trailing "\n  ")
      assert.equals("AB", output)
    end)

    -- ── No trim (default preservation) ──────────────────────────────

    it("preserves all whitespace when no trim flags set", function()
      local output = render({
        ast.text("hello  \n  ", pos),
        ast.expression(" 'world' ", pos),
        ast.text("\n  end", pos),
      })
      assert.equals("hello  \n  world\n  end", output)
    end)

    it("preserves whitespace around code blocks without trim flags", function()
      local output = render({
        ast.text("before\n", pos),
        ast.code(" if true then ", pos),
        ast.text("\nmiddle\n", pos),
        ast.code(" end ", pos),
        ast.text("\nafter", pos),
      })
      assert.equals("before\n\nmiddle\n\nafter", output)
    end)

    -- ── Edge cases ──────────────────────────────────────────────────

    it("non-text segments pass through unchanged regardless of adjacent trim flags", function()
      local segments = {
        ast.code(" if true then ", pos, { trim_after = true }),
        ast.tool_result("id1", { content = "content", start_line = 2, end_line = 3 }),
        ast.code(" end ", pos, { trim_before = true }),
      }
      local result = compiler.compile(segments)
      local env = { __filename = "test.chat" }
      local parts, diagnostics = compiler.execute(result, env)
      assert.equals(0, #diagnostics)
      assert.equals(1, #parts)
      assert.equals("tool_result", parts[1].kind)
    end)

    it("trim on empty text segment is harmless", function()
      local output = render({
        ast.expression(" 'A' ", pos, { trim_after = true }),
        ast.text("", pos),
        ast.expression(" 'B' ", pos, { trim_before = true }),
      })
      assert.equals("AB", output)
    end)

    it("trim_before only affects the immediately adjacent text segment", function()
      -- text1, text2, expression(trim_before) — only text2 is trimmed
      local output = render({
        ast.text("first \n ", pos),
        ast.text("second \n ", pos),
        ast.expression(" 'x' ", pos, { trim_before = true }),
      })
      -- text1 is not adjacent to the expression, so not trimmed (keeps trailing " \n ")
      -- text2 IS adjacent (index 2, expression at index 3), so its trailing " \n " is trimmed
      assert.equals("first \n secondx", output)
    end)

    it("mixed trim flags across expression and code", function()
      -- Simulate: text {%- if cond -%} text {{- expr -}} text {%- end -%} text
      local output = render({
        ast.text("A \n ", pos),
        ast.code(" if true then ", pos, { trim_before = true, trim_after = true }),
        ast.text(" \n B \n ", pos),
        ast.expression(" 'C' ", pos, { trim_before = true, trim_after = true }),
        ast.text(" \n D \n ", pos),
        ast.code(" end ", pos, { trim_before = true, trim_after = true }),
        ast.text(" \n E", pos),
      })
      assert.equals("ABCDE", output)
    end)

    it("trim with only spaces and no newline between tags", function()
      local output = render({
        ast.text("hello", pos),
        ast.expression(" ' ' ", pos, { trim_before = true, trim_after = true }),
        ast.text("world", pos),
      })
      -- No whitespace to trim around "hello" and "world" (no trailing/leading ws)
      assert.equals("hello world", output)
    end)
  end)
end)
