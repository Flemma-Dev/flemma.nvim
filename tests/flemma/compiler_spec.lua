local ast = require("flemma.ast")

describe("flemma.compiler", function()
  local compiler

  before_each(function()
    package.loaded["flemma.compiler"] = nil
    package.loaded["flemma.ast"] = nil
    package.loaded["flemma.ast.nodes"] = nil
    compiler = require("flemma.compiler")
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
        ast.tool_result("id123", "content", { start_line = 2, end_line = 3 }),
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
        ast.tool_result("id1", "result content", {
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
        ast.tool_result("id1", "content", { start_line = 2, end_line = 3 }),
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
end)
