describe("flemma.templating", function()
  local templating

  before_each(function()
    package.loaded["flemma.templating"] = nil
    package.loaded["flemma.templating.builtins.stdlib"] = nil
    package.loaded["flemma.templating.builtins.iterators"] = nil
    templating = require("flemma.templating")
  end)

  describe("register", function()
    it("accepts a populator and uses it during create_env", function()
      templating.register("test", {
        priority = 100,
        populate = function(env)
          env.greeting = "hello"
        end,
      })
      local env = templating.create_env()
      assert.equals("hello", env.greeting)
    end)

    it("defaults priority to 500", function()
      local order = {}
      templating.register("early", {
        priority = 100,
        populate = function()
          table.insert(order, "early")
        end,
      })
      templating.register("default_prio", {
        populate = function()
          table.insert(order, "default")
        end,
      })
      templating.create_env()
      assert.equals("early", order[1])
      assert.equals("default", order[2])
    end)

    it("replaces existing populator with same name", function()
      templating.register("dup", {
        priority = 100,
        populate = function(env)
          env.val = "first"
        end,
      })
      templating.register("dup", {
        priority = 100,
        populate = function(env)
          env.val = "second"
        end,
      })
      local env = templating.create_env()
      assert.equals("second", env.val)
    end)
  end)

  describe("create_env", function()
    it("returns a table with no data keys when no populators registered", function()
      local env = templating.create_env()
      assert.is_table(env)
      -- No data keys (metatable is present for strict checking but doesn't add entries)
      assert.is_nil(next(env))
    end)

    it("runs populators in priority order (lower first)", function()
      local order = {}
      templating.register("second", {
        priority = 200,
        populate = function()
          table.insert(order, "second")
        end,
      })
      templating.register("first", {
        priority = 100,
        populate = function()
          table.insert(order, "first")
        end,
      })
      templating.create_env()
      assert.equals("first", order[1])
      assert.equals("second", order[2])
    end)

    it("allows populators to override earlier entries", function()
      templating.register("base", {
        priority = 100,
        populate = function(env)
          env.val = "original"
        end,
      })
      templating.register("override", {
        priority = 200,
        populate = function(env)
          env.val = "custom"
        end,
      })
      local env = templating.create_env()
      assert.equals("custom", env.val)
    end)

    it("allows populators to remove earlier entries", function()
      templating.register("base", {
        priority = 100,
        populate = function(env)
          env.dangerous = true
        end,
      })
      templating.register("restrictor", {
        priority = 200,
        populate = function(env)
          env.dangerous = nil
        end,
      })
      local env = templating.create_env()
      assert.is_nil(env.dangerous)
    end)
  end)

  describe("register_module", function()
    it("lazily loads modules on first create_env", function()
      local load_count = 0
      package.preload["test.templating.fixture"] = function()
        load_count = load_count + 1
        return {
          name = "fixture",
          priority = 300,
          populate = function(env)
            env.fixture_loaded = true
          end,
        }
      end

      templating.register_module("test.templating.fixture")
      assert.equals(0, load_count)

      local env = templating.create_env()
      assert.equals(1, load_count)
      assert.is_true(env.fixture_loaded)

      -- Second create_env should not re-load
      templating.create_env()
      assert.equals(1, load_count)

      package.preload["test.templating.fixture"] = nil
      package.loaded["test.templating.fixture"] = nil
    end)

    it("does not double-load already loaded modules", function()
      local load_count = 0
      package.preload["test.templating.counted"] = function()
        load_count = load_count + 1
        return {
          name = "counted",
          priority = 300,
          populate = function(env)
            env.counted = true
          end,
        }
      end

      templating.register_module("test.templating.counted")
      templating.create_env() -- triggers load
      templating.register_module("test.templating.counted") -- no-op
      templating.create_env() -- should not re-load
      assert.equals(1, load_count)

      package.preload["test.templating.counted"] = nil
      package.loaded["test.templating.counted"] = nil
    end)
  end)

  describe("from_context", function()
    local ctx_mod, sym

    before_each(function()
      -- Clear all three together so they share the same symbols instance
      package.loaded["flemma.context"] = nil
      package.loaded["flemma.symbols"] = nil
      package.loaded["flemma.templating"] = nil
      package.loaded["flemma.templating.builtins.stdlib"] = nil
      package.loaded["flemma.templating.builtins.iterators"] = nil
      ctx_mod = require("flemma.context")
      sym = require("flemma.symbols")
      templating = require("flemma.templating")
    end)

    it("sets __filename and __dirname from context", function()
      local ctx = ctx_mod.from_file("/tmp/flemma.chat")
      local env = templating.from_context(ctx)
      assert.equals("/tmp/flemma.chat", env.__filename)
      assert.equals("/tmp", env.__dirname)
    end)

    it("sets __filename and __dirname to nil when context has no filename", function()
      local ctx = ctx_mod.clone(nil)
      local env = templating.from_context(ctx)
      assert.is_nil(env.__filename)
      assert.is_nil(env.__dirname)
    end)

    it("merges user variables as top-level string keys", function()
      local base = ctx_mod.from_file("/tmp/flemma.chat")
      local ext = ctx_mod.extend(base, { foo = "bar" })
      local env = templating.from_context(ext)
      assert.equals("bar", env.foo)
    end)

    it("sets buffer number from explicit parameter", function()
      local buf = vim.api.nvim_create_buf(false, true)
      local ctx = ctx_mod.from_buffer(buf)
      local env = templating.from_context(ctx, buf)
      assert.equals(buf, env[sym.BUFFER_NUMBER])
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("buffer number is nil when not provided", function()
      local ctx = ctx_mod.from_file("/tmp/test.chat")
      local env = templating.from_context(ctx)
      assert.is_nil(env[sym.BUFFER_NUMBER])
    end)

    it("handles nil context gracefully", function()
      local env = templating.from_context(nil)
      assert.is_nil(env.__filename)
      assert.is_nil(env.__dirname)
      assert.is_nil(env[sym.BUFFER_NUMBER])
    end)

    it("symbol-keyed fields are invisible to sandbox iteration", function()
      local buf = vim.api.nvim_create_buf(false, true)
      local ctx = ctx_mod.from_buffer(buf)
      local env = templating.from_context(ctx, buf)
      local string_keys = {}
      for k, _ in pairs(env) do
        if type(k) == "string" then
          string_keys[k] = true
        end
      end
      assert.is_nil(string_keys["__opts"])
      assert.is_nil(string_keys["__bufnr"])
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("setup", function()
    it("registers stdlib built-in", function()
      templating.setup()
      local env = templating.create_env()
      assert.is_table(env.string)
      assert.is_table(env.math)
      assert.is_table(env.table)
      assert.is_function(env.ipairs)
      assert.is_function(env.pairs)
      assert.is_function(env.pcall)
      assert.is_function(env.tostring)
      -- os exposes only safe time functions; io is not exposed
      assert.is_table(env.os)
      assert.is_function(env.os.date)
      assert.is_function(env.os.time)
      assert.is_function(env.os.clock)
      assert.is_function(env.os.difftime)
      assert.is_nil(rawget(env.os, "execute"))
      assert.is_nil(rawget(env.os, "exit"))
      assert.is_nil(rawget(env.os, "getenv"))
      assert.is_nil(rawget(env.os, "remove"))
      assert.is_nil(rawget(env, "io"))
    end)

    it("registers iterators built-in", function()
      templating.setup()
      local env = templating.create_env()
      assert.is_function(env.values)
      assert.is_function(env.each)
    end)
  end)

  describe("strict undefined variable checking", function()
    it("errors on access to undefined variables", function()
      templating.setup()
      local env = templating.create_env()
      assert.has_error(function()
        local _ = env.nonexistent
      end, "Undefined variable 'nonexistent'")
    end)

    it("allows access to variables defined by populators", function()
      templating.register("test_var", {
        populate = function(env)
          env.greeting = "hello"
        end,
      })
      local env = templating.create_env()
      assert.equals("hello", env.greeting)
    end)

    it("allows access to variables added after creation", function()
      local env = templating.create_env()
      env.name = "Alice"
      assert.equals("Alice", env.name)
    end)

    it("returns nil for framework-internal keys", function()
      local env = templating.create_env()
      -- Framework keys (__filename, __emit, etc.) are pre-registered and return nil
      assert.is_nil(env.__filename)
      assert.is_nil(env.__emit)
    end)

    it("errors on underscore-prefixed user variables", function()
      local env = templating.create_env()
      -- User-style underscore names like __name__ are NOT exempt
      assert.has_error(function()
        local _ = env.__name__
      end)
      assert.has_error(function()
        local _ = env._private
      end)
    end)

    it("returns nil for non-string keys", function()
      local env = templating.create_env()
      local symbol = {}
      assert.is_nil(env[symbol])
    end)

    it("returns nil for keys set then removed by populators", function()
      templating.register("setter", {
        priority = 100,
        populate = function(env)
          env.temporary = true
        end,
      })
      templating.register("remover", {
        priority = 200,
        populate = function(env)
          env.temporary = nil
        end,
      })
      local env = templating.create_env()
      -- Key was set then removed: known but absent, returns nil without error
      assert.is_nil(env.temporary)
    end)
  end)
end)

describe("flemma.templating.compiler", function()
  local ast
  local compiler

  before_each(function()
    package.loaded["flemma.templating.compiler"] = nil
    package.loaded["flemma.ast"] = nil
    package.loaded["flemma.ast.nodes"] = nil
    ast = require("flemma.ast")
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

    it("re-raises readiness suspense from expression evaluation", function()
      local readiness = require("flemma.readiness")
      readiness._reset_for_tests()
      local boundary = readiness.get_or_create_boundary("test:expr", function(done)
        done()
      end)

      local segments = {
        ast.expression(" raise_suspense() ", { start_line = 1 }),
      }
      local result = compiler.compile(segments)
      local env = {
        __filename = "test.chat",
        raise_suspense = function()
          error(readiness.Suspense.new("test suspend", boundary))
        end,
      }
      local ok, err = pcall(compiler.execute, result, env)
      assert.is_false(ok)
      assert.is_true(readiness.is_suspense(err))
      assert.equals("test suspend", err.message)
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
      assert.truthy(result.source:find("__capture_start"))
      assert.truthy(result.source:find("__capture_end"))
      assert.truthy(result.source:find("__emit_part"))
    end)

    it("compiles opaque tool_result as structural pass-through", function()
      local segments = {
        ast.tool_result("id456", { content = "plain text", start_line = 1, end_line = 2 }),
      }
      local result = compiler.compile(segments)
      assert.is_nil(result.error)
      assert.truthy(result.source:find("__emit_part"))
      assert.falsy(result.source:find("__capture_start"))
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
      assert.is_nil(parts[1].status)
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

describe("flemma.templating.eval", function()
  local eval
  local templating

  -- Before each test, get a fresh instance of the eval module
  before_each(function()
    -- Invalidate the package cache to ensure we get a fresh module
    package.loaded["flemma.templating.eval"] = nil
    package.loaded["flemma.templating"] = nil
    package.loaded["flemma.templating.builtins.stdlib"] = nil
    package.loaded["flemma.templating.builtins.iterators"] = nil
    eval = require("flemma.templating.eval")
    templating = require("flemma.templating")
    templating.setup()
  end)

  describe("eval_expression", function()
    it("should evaluate a simple expression correctly", function()
      local env = templating.create_env()
      local result = eval.eval_expression("1 + 1", env)
      assert.are.equal(2, result)
    end)

    it("should evaluate an expression using the provided environment", function()
      local env = templating.create_env()
      env.my_var = 10
      local result = eval.eval_expression("my_var * 2", env)
      assert.are.equal(20, result)
    end)

    it("should error on a syntactically invalid expression", function()
      local env = templating.create_env()
      local ok, err = pcall(eval.eval_expression, "1 +", env)
      assert.is_false(ok)
      assert.equals("table", type(err))
      assert.equals("expression", err.type)
      assert.equals("error", err.severity)
      assert.truthy(err.error:match("Parse error"))
    end)

    it("should error on undefined variable access", function()
      local env = templating.create_env()
      local ok, err = pcall(eval.eval_expression, "mane", env)
      assert.is_false(ok)
      assert.equals("table", type(err))
      assert.equals("expression", err.type)
      assert.truthy(err.error:match("Undefined variable 'mane'"))
    end)

    it("should error on undefined variable inside stdlib call", function()
      local env = templating.create_env()
      local ok, err = pcall(eval.eval_expression, "string.upper(mane)", env)
      assert.is_false(ok)
      assert.equals("table", type(err))
      assert.equals("expression", err.type)
      assert.truthy(err.error:match("Undefined variable 'mane'"))
    end)

    it("should allow access to defined variables", function()
      local env = templating.create_env()
      env.name = "Alice"
      local result = eval.eval_expression("name", env)
      assert.are.equal("Alice", result)
    end)
  end)

  describe("execute_frontmatter", function()
    it("should execute code and return new globals", function()
      local env = templating.create_env()
      local globals = eval.execute_frontmatter("my_var = 'test'", env)
      assert.are.equal("test", globals.my_var)
    end)

    it("should not return pre-existing environment variables as new globals", function()
      local env = templating.create_env()
      env.existing_var = "hello"
      local globals = eval.execute_frontmatter("new_var = 'world'", env)
      assert.are.equal("world", globals.new_var)
      assert.is_nil(globals.existing_var)
    end)
  end)

  describe("include() isolation", function()
    it("should NOT propagate user variables from caller environment to included file", function()
      -- Setup: Create test files
      local temp_dir = vim.fn.tempname() .. "_include_isolation_test"
      vim.fn.mkdir(temp_dir, "p")

      -- Create an included file that uses a variable from the parent
      local include_file = temp_dir .. "/child.txt"
      local f = io.open(include_file, "w")
      f:write("Hello {{ name }}!")
      f:close()

      -- Create parent file
      local parent_file = temp_dir .. "/parent.chat"

      -- Create environment with user variable 'name'
      local env = templating.create_env()
      env.__filename = parent_file
      env.__dirname = temp_dir
      env.name = "World" -- User variable defined in frontmatter

      -- Include should error because 'name' is not passed to the child env,
      -- and the child's strict env will reject the undefined variable access.
      local ok, err = pcall(eval.eval_expression, "include('child.txt')", env)
      assert.is_false(ok)
      assert.equals("table", type(err))
      assert.truthy(err.error:match("Undefined variable 'name'"))

      -- Cleanup
      vim.fn.delete(temp_dir, "rf")
    end)
  end)

  describe("include() binary mode", function()
    it("should return a binary IncludePart for binary includes", function()
      local emittable = require("flemma.emittable")

      local temp_dir = vim.fn.tempname() .. "_include_binary_test"
      vim.fn.mkdir(temp_dir, "p")

      -- Create a test file
      local test_file = temp_dir .. "/test.txt"
      local f = io.open(test_file, "w")
      f:write("file content")
      f:close()

      local parent_file = temp_dir .. "/parent.chat"
      local env = templating.create_env()
      env.__filename = parent_file
      env.__dirname = temp_dir

      local result = eval.eval_expression("include('test.txt', { [symbols.BINARY] = true })", env)
      assert.is_true(emittable.is_emittable(result))

      -- Emit and check it produces a file part
      local ctx = emittable.EmitContext.new()
      result:emit(ctx)
      assert.equals(1, #ctx.parts)
      assert.equals("file", ctx.parts[1].kind)
      assert.equals(temp_dir .. "/test.txt", ctx.parts[1].filename)

      vim.fn.delete(temp_dir, "rf")
    end)

    it("should handle binary data with NUL bytes without E976 error", function()
      local emittable = require("flemma.emittable")

      local temp_dir = vim.fn.tempname() .. "_include_binary_nul_test"
      vim.fn.mkdir(temp_dir, "p")

      -- Create a file with binary content containing NUL bytes (like a real PNG)
      local test_file = temp_dir .. "/image.png"
      local f = io.open(test_file, "wb")
      f:write("\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01")
      f:close()

      local parent_file = temp_dir .. "/parent.chat"
      local env = templating.create_env()
      env.__filename = parent_file
      env.__dirname = temp_dir

      -- This previously threw Vim:E976: Using a Blob as a String
      -- because check_file_drift called vim.fn.sha256 on binary data
      local ok, result = pcall(eval.eval_expression, "include('image.png', { [symbols.BINARY] = true })", env)
      assert.is_true(ok, "binary include with NUL bytes should not error: " .. tostring(result))
      assert.is_true(emittable.is_emittable(result))

      local ctx = emittable.EmitContext.new()
      result:emit(ctx)
      assert.equals(1, #ctx.parts)
      assert.equals("file", ctx.parts[1].kind)
      assert.equals("image/png", ctx.parts[1].mime_type)

      vim.fn.delete(temp_dir, "rf")
    end)
  end)

  describe("include() circular detection", function()
    it("should detect circular includes", function()
      local temp_dir = vim.fn.tempname() .. "_include_circular_test"
      vim.fn.mkdir(temp_dir, "p")

      local f1 = io.open(temp_dir .. "/loop1.txt", "w")
      f1:write("{{ include('loop2.txt') }}")
      f1:close()

      local f2 = io.open(temp_dir .. "/loop2.txt", "w")
      f2:write("{{ include('loop1.txt') }}")
      f2:close()

      local parent_file = temp_dir .. "/parent.chat"
      local env = templating.create_env()
      env.__filename = parent_file
      env.__dirname = temp_dir

      local ok, err = pcall(eval.eval_expression, "include('loop1.txt')", env)
      assert.is_false(ok)
      assert.equals("table", type(err))
      assert.equals("file", err.type)
      assert.truthy(err.error:match("Circular include"))

      vim.fn.delete(temp_dir, "rf")
    end)
  end)

  describe("include() structured errors", function()
    it("should throw structured error for missing files in binary mode", function()
      local temp_dir = vim.fn.tempname() .. "_include_error_test"
      vim.fn.mkdir(temp_dir, "p")

      local parent_file = temp_dir .. "/parent.chat"
      local env = templating.create_env()
      env.__filename = parent_file
      env.__dirname = temp_dir

      local ok, err = pcall(eval.eval_expression, "include('nonexistent.png', { [symbols.BINARY] = true })", env)
      assert.is_false(ok)
      -- Structured error table is preserved through eval_expression
      assert.equals("table", type(err))
      assert.equals("file", err.type)
      assert.is_true(err.error:match("File not found") ~= nil)

      vim.fn.delete(temp_dir, "rf")
    end)

    it("should propagate structured errors through execute_frontmatter (frontmatter)", function()
      local temp_dir = vim.fn.tempname() .. "_include_frontmatter_error_test"
      vim.fn.mkdir(temp_dir, "p")

      local parent_file = temp_dir .. "/parent.chat"
      local env = templating.create_env()
      env.__filename = parent_file
      env.__dirname = temp_dir

      local ok, err = pcall(eval.execute_frontmatter, "include('nonexistent.txt')", env)
      assert.is_false(ok)
      -- Structured error table must survive execute_frontmatter, not become "table: 0x..."
      assert.equals("table", type(err))
      assert.equals("file", err.type)
      assert.is_true(err.error:match("File not found") ~= nil)
      -- Include stack should contain the parent file
      assert.is_table(err.include_stack)
      assert.equals(1, #err.include_stack)
      assert.equals(parent_file, err.include_stack[1])

      vim.fn.delete(temp_dir, "rf")
    end)

    it("should treat @./ in included content as plain text (preprocessor handles document level)", function()
      local temp_dir = vim.fn.tempname() .. "_include_nested_text_test"
      vim.fn.mkdir(temp_dir, "p")

      -- middle.txt contains @./ reference — now treated as plain text inside includes
      local middle_file = temp_dir .. "/middle.txt"
      local f = io.open(middle_file, "w")
      f:write("some text @./nonexistent.png and more")
      f:close()

      local parent_file = temp_dir .. "/parent.chat"
      local env = templating.create_env()
      env.__filename = parent_file
      env.__dirname = temp_dir

      -- Should succeed: @./nonexistent.png is plain text, not an include() call
      local ok, result = pcall(eval.eval_expression, "include('middle.txt')", env)
      assert.is_true(ok)
      -- Result should contain the raw @./ reference as text
      assert.is_not_nil(result)

      vim.fn.delete(temp_dir, "rf")
    end)
  end)

  describe("include() parameterized arguments", function()
    it("should pass arguments to the included template", function()
      local emittable_mod = require("flemma.emittable")

      local temp_dir = vim.fn.tempname() .. "_include_args_test"
      vim.fn.mkdir(temp_dir, "p")

      -- Create a template file that uses a parameter
      local greeting_file = temp_dir .. "/greeting.md"
      local f = io.open(greeting_file, "w")
      f:write("Hello, {{ name }}!")
      f:close()

      -- Create parent environment
      local parent_file = temp_dir .. "/parent.chat"
      local env = templating.create_env()
      env.__filename = parent_file
      env.__dirname = temp_dir

      -- Call include() with arguments
      local result = eval.eval_expression("include('greeting.md', { name = 'Alice' })", env)
      assert.is_true(emittable_mod.is_emittable(result))

      -- Emit and check the output
      local ctx = emittable_mod.EmitContext.new()
      result:emit(ctx)

      local texts = {}
      for _, part in ipairs(ctx.parts) do
        if part.kind == "text" then
          table.insert(texts, part.text)
        end
      end
      local output = table.concat(texts, "")
      assert.are.equal("Hello, Alice!", output)

      vim.fn.delete(temp_dir, "rf")
    end)

    it("should isolate arguments from parent environment", function()
      local emittable_mod = require("flemma.emittable")

      local temp_dir = vim.fn.tempname() .. "_include_isolation_args_test"
      vim.fn.mkdir(temp_dir, "p")

      -- Create a template file that uses 'name'
      local child_file = temp_dir .. "/child.md"
      local f = io.open(child_file, "w")
      f:write("{{ name }}")
      f:close()

      -- Create parent environment with name = "Parent"
      local parent_file = temp_dir .. "/parent.chat"
      local env = templating.create_env()
      env.__filename = parent_file
      env.__dirname = temp_dir
      env.name = "Parent"

      -- Call include() with name = "Child" as argument
      local result = eval.eval_expression("include('child.md', { name = 'Child' })", env)
      assert.is_true(emittable_mod.is_emittable(result))

      -- Emit and check the child got "Child", not "Parent"
      local ctx = emittable_mod.EmitContext.new()
      result:emit(ctx)

      local texts = {}
      for _, part in ipairs(ctx.parts) do
        if part.kind == "text" then
          table.insert(texts, part.text)
        end
      end
      local output = table.concat(texts, "")
      assert.are.equal("Child", output)

      -- Verify parent environment is unchanged
      assert.are.equal("Parent", env.name)

      vim.fn.delete(temp_dir, "rf")
    end)
  end)

  describe("include() with {% %} code blocks", function()
    it("should evaluate code blocks inside included files", function()
      local emittable_mod = require("flemma.emittable")

      local temp_dir = vim.fn.tempname() .. "_include_code_blocks"
      vim.fn.mkdir(temp_dir, "p")

      local template_path = temp_dir .. "/conditional.md"
      local f = io.open(template_path, "w")
      f:write("{% if mode == 'strict' then %}Be strict.{% else %}Be friendly.{% end %}")
      f:close()

      local env = templating.create_env()
      env.__filename = temp_dir .. "/test.chat"
      env.__dirname = temp_dir

      -- Test with mode = "strict"
      local result = eval.eval_expression("include('conditional.md', { mode = 'strict' })", env)
      assert.is_true(emittable_mod.is_emittable(result))

      local ctx = emittable_mod.EmitContext.new()
      result:emit(ctx)

      local texts = {}
      for _, part in ipairs(ctx.parts) do
        if part.kind == "text" then
          table.insert(texts, part.text)
        end
      end
      local output = table.concat(texts, "")
      assert.truthy(output:find("Be strict"))
      assert.is_nil(output:find("Be friendly"))

      vim.fn.delete(temp_dir, "rf")
    end)
  end)

  describe("include() absolute paths", function()
    it("should resolve absolute paths without prepending dirname", function()
      local emittable = require("flemma.emittable")

      local temp_dir = vim.fn.tempname() .. "_include_abspath_test"
      vim.fn.mkdir(temp_dir, "p")

      -- Create target file
      local target_file = temp_dir .. "/target.txt"
      local f = io.open(target_file, "w")
      f:write("absolute content")
      f:close()

      -- Set dirname to a DIFFERENT directory to prove absolute path ignores it
      local other_dir = vim.fn.tempname() .. "_include_abspath_other"
      vim.fn.mkdir(other_dir, "p")

      local env = templating.create_env()
      env.__filename = other_dir .. "/parent.chat"
      env.__dirname = other_dir

      local result = eval.eval_expression("include('" .. target_file .. "')", env)
      assert.is_true(emittable.is_emittable(result))

      local ctx = emittable.EmitContext.new()
      result:emit(ctx)

      local texts = {}
      for _, part in ipairs(ctx.parts) do
        if part.kind == "text" then
          table.insert(texts, part.text)
        end
      end
      assert.are.equal("absolute content", table.concat(texts, ""))

      vim.fn.delete(temp_dir, "rf")
      vim.fn.delete(other_dir, "rf")
    end)
  end)

  describe("strict env through compiler (integration)", function()
    local compiler = require("flemma.templating.compiler")
    local ast = require("flemma.ast.nodes")

    it("undefined variable produces expression diagnostic", function()
      local pos = { start_line = 5 }
      local segments = {
        ast.text("Hello ", pos),
        ast.expression(" mane ", pos),
        ast.text("!", pos),
      }
      local result = compiler.compile(segments)
      assert.is_nil(result.error)

      local env = templating.create_env()
      env.__filename = "test.chat"
      local parts, diagnostics = compiler.execute(result, env)

      -- Expression degrades to raw text
      local text = ""
      for _, p in ipairs(parts) do
        if p.kind == "text" then
          text = text .. p.text
        end
      end
      assert.truthy(text:find("{{ mane }}"))

      -- Diagnostic is produced with the undefined variable error
      assert.is_true(#diagnostics > 0)
      assert.equals("expression", diagnostics[1].type)
      assert.equals("warning", diagnostics[1].severity)
      assert.truthy(diagnostics[1].error:find("Undefined variable 'mane'"))
    end)

    it("underscore-prefixed user variable is caught", function()
      local pos = { start_line = 1 }
      local segments = { ast.expression(" __name__ ", pos) }
      local result = compiler.compile(segments)

      local env = templating.create_env()
      env.__filename = "test.chat"
      local parts, diagnostics = compiler.execute(result, env)

      -- Should degrade to raw text, not silently produce nil
      local text = ""
      for _, p in ipairs(parts) do
        if p.kind == "text" then
          text = text .. p.text
        end
      end
      assert.truthy(text:find("__name__"))
      assert.is_true(#diagnostics > 0)
      assert.truthy(diagnostics[1].error:find("Undefined variable '__name__'"))
    end)
  end)

  describe("strict env through pipeline (E2E)", function()
    it("undefined variable in @You message produces diagnostic", function()
      local parser = require("flemma.parser")
      local pipeline = require("flemma.pipeline")
      local ctx = require("flemma.context")

      local lines = {
        "@You:",
        "Hello {{ mane }}!",
      }
      local context = ctx.from_file("test.chat")
      local prompt, evaluated = pipeline.run(parser.parse_lines(lines), context, { bufnr = 0 })

      -- Expression degrades to raw text in the output
      local user_msg = prompt.history[1]
      local text = ""
      for _, p in ipairs(user_msg.parts) do
        if p.kind == "text" then
          text = text .. (p.text or "")
        end
      end
      assert.truthy(text:find("{{ mane }}"), "expected raw expression text, got: " .. text)

      -- Diagnostic is present in the evaluated result
      local found_diagnostic = false
      for _, d in ipairs(evaluated.diagnostics) do
        if d.type == "expression" and d.error and d.error:find("Undefined variable 'mane'") then
          found_diagnostic = true
          break
        end
      end
      assert.is_true(found_diagnostic, "expected diagnostic about undefined variable 'mane'")
    end)
  end)
end)

describe("templating.scanner", function()
  local scanner

  before_each(function()
    package.loaded["flemma.templating.scanner"] = nil
    scanner = require("flemma.templating.scanner")
  end)

  -- Helpers: call find_closing with default start_pos=1
  local function scan_expr(s, start)
    return scanner.find_closing(s, start or 1, "expression")
  end

  local function scan_code(s, start)
    return scanner.find_closing(s, start or 1, "code")
  end

  -- Extract the matched delimiter text from return values
  local function delimiter(s, cs, ce)
    return s:sub(cs, ce)
  end

  -- Extract content before the delimiter
  local function content_before(s, cs)
    return s:sub(1, cs - 1)
  end

  describe("find_closing", function()
    -- ================================================================
    -- 1. Basic expressions (no special content)
    -- ================================================================
    describe("basic expressions", function()
      it("finds simple closing delimiter", function()
        local s = " x + 1 }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" x + 1 ", content_before(s, cs))
      end)

      it("finds closing at start of string", function()
        local s = "}}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(1, cs)
      end)

      it("finds closing with only whitespace before", function()
        local s = "  }}"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals("  ", content_before(s, cs))
      end)

      it("finds closing when delimiter is entire string", function()
        local cs, ce = scan_expr("}}")
        assert.is_not_nil(cs)
        assert.equals(1, cs)
        assert.equals(2, ce)
      end)

      it("returns nil when no closing delimiter exists", function()
        local cs, ce = scan_expr(" x + 1 ")
        assert.is_nil(cs)
        assert.is_nil(ce)
      end)

      it("returns nil for single closing brace", function()
        local cs, ce = scan_expr(" x } rest")
        assert.is_nil(cs)
        assert.is_nil(ce)
      end)

      it("skips lone } at depth 0 when not followed by }", function()
        local s = " x } + y }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" x } + y ", content_before(s, cs))
      end)

      it("returns nil for empty input", function()
        local cs, ce = scan_expr("")
        assert.is_nil(cs)
        assert.is_nil(ce)
      end)
    end)

    -- ================================================================
    -- 2. String literals containing }}
    -- ================================================================
    describe("string literals containing closing delimiter", function()
      it("skips }} inside double-quoted string", function()
        local s = [[ "hello }}" }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find('"hello }}"', 1, true))
      end)

      it("skips }} inside single-quoted string", function()
        local s = [[ 'hello }}' }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find("'hello }}'", 1, true))
      end)

      it("skips }} inside long string [[]]", function()
        local s = [=[ [[hello }}]] }}rest]=]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find("[[hello }}]]", 1, true))
      end)

      it("skips }} inside leveled long string [=[]=]", function()
        local s = [==[ [=[}}]=] }}rest]==]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find("[=[}}]=]", 1, true))
      end)

      it("skips }} in string at end of expression", function()
        local s = [[ "val}}" }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find('"val}}"', 1, true))
      end)

      it("skips }} in multiple strings", function()
        local s = [[ "a}}" .. "b}}" }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find('"b}}"', 1, true))
      end)

      it("handles empty string before closing", function()
        local s = [[ "" }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("skips {{ and }} inside string", function()
        local s = [[ "{{x}}" }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find('"{{x}}"', 1, true))
      end)
    end)

    -- ================================================================
    -- 3. Escape sequences in strings
    -- ================================================================
    describe("escape sequences in strings", function()
      it("handles escaped quotes in double-quoted string", function()
        -- Buffer text: "he said \"yes\"" }}rest
        -- The \" inside the string should not end it
        local s = [[ "he said \"yes\"" }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find("he said", 1, true))
      end)

      it("handles escaped backslash before closing quote", function()
        -- Buffer text: "\\" }}rest
        -- \\ is escaped backslash, then " closes the string
        local s = [[ "\\" }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("handles escaped backslash before escaped quote", function()
        -- Buffer text: "\\\"" }}rest
        -- \\ is escaped backslash, \" is escaped quote, then " closes
        local s = [[ "\\\"" }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("handles escape followed by }} inside string", function()
        -- Buffer text: "a\"b}}c" }}rest
        -- \" doesn't end string, }} inside string is skipped
        local s = [[ "a\"b}}c" }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find("b}}c", 1, true))
      end)

      it("handles escaped single quote in single-quoted string", function()
        -- Buffer text: 'it\'s }}' }}rest
        local s = [[ 'it\'s }}' }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)
    end)

    -- ================================================================
    -- 4. Brace balancing (expression mode)
    -- ================================================================
    describe("brace balancing", function()
      it("balances simple table constructor", function()
        local s = " {a=1} }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" {a=1} ", content_before(s, cs))
      end)

      it("balances nested tables", function()
        local s = " {a={b=1}} }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" {a={b=1}} ", content_before(s, cs))
      end)

      it("handles table closing brace adjacent to delimiter", function()
        -- Three }s: first closes table, remaining two are delimiter
        local s = " {1}}}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" {1}", content_before(s, cs))
      end)

      it("balances empty table", function()
        local s = " {} }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" {} ", content_before(s, cs))
      end)

      it("balances multiple tables", function()
        local s = " {1} .. {2} }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" {1} .. {2} ", content_before(s, cs))
      end)

      it("balances empty table adjacent to delimiter", function()
        -- {}}} = empty table close, then }} closing delimiter
        local s = " {}}}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" {}", content_before(s, cs))
      end)

      it("balances table with string containing single }", function()
        -- String "val}" has one } inside — does not affect brace depth
        local s = [[ {key="val}"} }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find('{key="val}"}', 1, true))
      end)

      it("balances table with string containing }}", function()
        -- String "}}" inside table — skipped entirely
        local s = [[ {key="}}"} }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find('{key="}}"}', 1, true))
      end)

      it("balances deeply nested tables", function()
        local s = " {{{1}}} }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" {{{1}}} ", content_before(s, cs))
      end)

      it("balances nested tables adjacent to delimiter", function()
        -- {a={b=1}}}} = nested table (4 }s: 2 close tables, 2 close expression)
        local s = " {a={b=1}}}}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" {a={b=1}}", content_before(s, cs))
      end)

      it("balances maximum depth nesting", function()
        local s = " {{{{{}}}}} }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" {{{{{}}}}} ", content_before(s, cs))
      end)
    end)

    -- ================================================================
    -- 5. Comments containing }}
    -- ================================================================
    describe("comments containing closing delimiter", function()
      it("skips }} in single-line comment", function()
        local s = " x -- }} comment\n }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        -- Content includes the comment line
        assert.truthy(content_before(s, cs):find("-- }}", 1, true))
      end)

      it("skips }} in long comment --[[]]", function()
        local s = " x --[[}}]] }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find("--[[}}]]", 1, true))
      end)

      it("skips }} in leveled long comment --[=[]=]", function()
        local s = [==[ x --[=[}}]=] }}rest]==]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("returns nil when }} only in comment at EOF", function()
        local s = " x -- }}"
        local cs, ce = scan_expr(s)
        assert.is_nil(cs)
        assert.is_nil(ce)
      end)

      it("finds }} on next line after single-line comment", function()
        local s = " x --comment\n}}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)
    end)

    -- ================================================================
    -- 6. Code block mode (%})
    -- ================================================================
    describe("code block mode", function()
      it("finds simple %} closing", function()
        local s = " if x then %}rest"
        local cs, ce = scan_code(s)
        assert.is_not_nil(cs)
        assert.equals("%}", delimiter(s, cs, ce))
        assert.equals(" if x then ", content_before(s, cs))
      end)

      it("skips %} inside double-quoted string", function()
        local s = [[ "contains %}" %}rest]]
        local cs, ce = scan_code(s)
        assert.is_not_nil(cs)
        assert.equals("%}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find('"contains %}"', 1, true))
      end)

      it("skips %} inside single-quoted string", function()
        local s = [[ 'contains %}' %}rest]]
        local cs, ce = scan_code(s)
        assert.is_not_nil(cs)
        assert.equals("%}", delimiter(s, cs, ce))
      end)

      it("skips %} inside long string", function()
        local s = [=[ [[contains %}]] %}rest]=]
        local cs, ce = scan_code(s)
        assert.is_not_nil(cs)
        assert.equals("%}", delimiter(s, cs, ce))
      end)

      it("skips %} inside single-line comment", function()
        local s = " x --%}\n %}rest"
        local cs, ce = scan_code(s)
        assert.is_not_nil(cs)
        assert.equals("%}", delimiter(s, cs, ce))
      end)

      it("does not track brace depth in code mode", function()
        -- Unbalanced { should not prevent finding %}
        local s = " { %}rest"
        local cs, ce = scan_code(s)
        assert.is_not_nil(cs)
        assert.equals("%}", delimiter(s, cs, ce))
      end)

      it("does not match lone % in code mode", function()
        -- % is Lua's modulo operator — only %} is a closing delimiter
        local s = " x % 2 %}rest"
        local cs, ce = scan_code(s)
        assert.is_not_nil(cs)
        assert.equals("%}", delimiter(s, cs, ce))
        assert.equals(" x % 2 ", content_before(s, cs))
      end)
    end)

    -- ================================================================
    -- 7. Trim variants
    -- ================================================================
    describe("trim variants", function()
      it("detects trim-after on expression -}}", function()
        local s = " x -}}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("-}}", delimiter(s, cs, ce))
        assert.equals(" x ", content_before(s, cs))
      end)

      it("detects trim-after on code block -%}", function()
        local s = " x -%}rest"
        local cs, ce = scan_code(s)
        assert.is_not_nil(cs)
        assert.equals("-%}", delimiter(s, cs, ce))
        assert.equals(" x ", content_before(s, cs))
      end)

      it("does not false-match trim when dash is not adjacent", function()
        local s = " x - }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.equals(" x - ", content_before(s, cs))
      end)

      it("skips -}} inside string then finds real trim close", function()
        local s = [[ "-}}" -}}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("-}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find('"-}}"', 1, true))
      end)

      it("detects trim on brace-balanced expression", function()
        local s = " {1} -}}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("-}}", delimiter(s, cs, ce))
        assert.equals(" {1} ", content_before(s, cs))
      end)
    end)

    -- ================================================================
    -- 8. Multi-line expressions
    -- ================================================================
    describe("multi-line expressions", function()
      it("finds closing on different line", function()
        local s = " x +\n y }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("finds closing when on its own line", function()
        local s = " x\n}}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("skips multi-line string containing }}", function()
        local s = ' "line1\nline2}}" }}rest'
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        assert.truthy(content_before(s, cs):find("line2}}", 1, true))
      end)

      it("skips comment on same line, finds }} on next", function()
        local s = " x -- }}\n}}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("skips multi-line long string containing }}", function()
        local s = [=[ [[
}}
]] }}rest]=]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("finds multi-line code block close", function()
        local s = " for i = 1, 10 do\n  print(i)\n %}rest"
        local cs, ce = scan_code(s)
        assert.is_not_nil(cs)
        assert.equals("%}", delimiter(s, cs, ce))
      end)
    end)

    -- ================================================================
    -- 9. Edge cases
    -- ================================================================
    describe("edge cases", function()
      it("returns nil for unclosed double-quoted string", function()
        local s = [[ "unterminated }}]]
        local cs, ce = scan_expr(s)
        assert.is_nil(cs)
        assert.is_nil(ce)
      end)

      it("returns nil for unclosed single-quoted string", function()
        local s = [[ 'unterminated }}]]
        local cs, ce = scan_expr(s)
        assert.is_nil(cs)
        assert.is_nil(ce)
      end)

      it("returns nil for unclosed long string", function()
        local s = " [[unterminated }}"
        local cs, ce = scan_expr(s)
        assert.is_nil(cs)
        assert.is_nil(ce)
      end)

      it("returns nil for unclosed long comment", function()
        local s = " --[[unterminated }}"
        local cs, ce = scan_expr(s)
        assert.is_nil(cs)
        assert.is_nil(ce)
      end)

      it("does not close long string with wrong level", function()
        -- [=[ needs ]=] not ]]
        local s = [==[ [=[ ]] ]=] }}rest]==]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("does not close long string with single ]", function()
        local s = [==[ [=[ ] ]=] }}rest]==]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("handles } as last character without second }", function()
        local cs, ce = scan_expr(" x }")
        assert.is_nil(cs)
        assert.is_nil(ce)
      end)

      it("respects start_pos parameter", function()
        -- }} exists before start_pos but should be ignored
        local s = "}}abc }}rest"
        local cs, ce = scan_expr(s, 4)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
        -- Should find the second }}, not the first
        assert.truthy(cs > 3)
      end)

      it("returns nil for code mode with no %}", function()
        local cs, ce = scan_code(" if true then end")
        assert.is_nil(cs)
        assert.is_nil(ce)
      end)

      it("does not confuse -- with long comment when not followed by [", function()
        -- -- without [[ is single-line comment, ends at newline
        local s = " x -- not long\n }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("treats --[ as single-line comment not long comment", function()
        -- --[ without a second [ is a regular single-line comment
        local s = " x --[ }}]\n }}rest"
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("handles string immediately followed by }}", function()
        -- No space between closing quote and }}
        local s = [[ "str"}}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)

      it("handles alternating string types", function()
        local s = [[ "a}}" .. 'b}}' }}rest]]
        local cs, ce = scan_expr(s)
        assert.is_not_nil(cs)
        assert.equals("}}", delimiter(s, cs, ce))
      end)
    end)
  end)
end)

describe("flemma.templating.builtins.iterators", function()
  local iterators

  before_each(function()
    package.loaded["flemma.templating.builtins.iterators"] = nil
    iterators = require("flemma.templating.builtins.iterators")
  end)

  describe("values()", function()
    it("iterates over array values without index", function()
      local env = {}
      iterators.populate(env)

      local items = { "a", "b", "c" }
      local result = {}
      for item in env.values(items) do
        table.insert(result, item)
      end
      assert.are.same({ "a", "b", "c" }, result)
    end)

    it("returns nothing for empty table", function()
      local env = {}
      iterators.populate(env)

      local count = 0
      for _ in env.values({}) do
        count = count + 1
      end
      assert.equals(0, count)
    end)

    it("stops at first nil in sequence", function()
      local env = {}
      iterators.populate(env)

      local sparse = { "a", "b" }
      sparse[4] = "d" -- gap at index 3
      local result = {}
      for item in env.values(sparse) do
        table.insert(result, item)
      end
      assert.are.same({ "a", "b" }, result)
    end)
  end)

  describe("each()", function()
    it("yields value and loop context", function()
      local env = {}
      iterators.populate(env)

      local items = { "x", "y", "z" }
      local results = {}
      for item, loop in env.each(items) do
        table.insert(results, {
          item = item,
          index = loop.index,
          index0 = loop.index0,
          first = loop.first,
          last = loop.last,
          length = loop.length,
        })
      end

      assert.equals(3, #results)

      assert.equals("x", results[1].item)
      assert.equals(1, results[1].index)
      assert.equals(0, results[1].index0)
      assert.is_true(results[1].first)
      assert.is_false(results[1].last)
      assert.equals(3, results[1].length)

      assert.equals("y", results[2].item)
      assert.equals(2, results[2].index)
      assert.is_false(results[2].first)
      assert.is_false(results[2].last)

      assert.equals("z", results[3].item)
      assert.equals(3, results[3].index)
      assert.is_false(results[3].first)
      assert.is_true(results[3].last)
    end)

    it("handles single-element array", function()
      local env = {}
      iterators.populate(env)

      local results = {}
      for item, loop in env.each({ "only" }) do
        table.insert(results, { item = item, first = loop.first, last = loop.last })
      end
      assert.equals(1, #results)
      assert.equals("only", results[1].item)
      assert.is_true(results[1].first)
      assert.is_true(results[1].last)
    end)

    it("handles empty array", function()
      local env = {}
      iterators.populate(env)

      local count = 0
      for _ in env.each({}) do
        count = count + 1
      end
      assert.equals(0, count)
    end)

    it("reuses loop context table across iterations", function()
      local env = {}
      iterators.populate(env)

      local refs = {}
      for _, loop in env.each({ "a", "b" }) do
        table.insert(refs, loop)
      end
      -- Same table reference reused (not allocating per iteration)
      assert.equals(refs[1], refs[2])
    end)
  end)

  describe("compiler integration", function()
    local compiler
    local ast

    before_each(function()
      package.loaded["flemma.templating.compiler"] = nil
      package.loaded["flemma.ast"] = nil
      package.loaded["flemma.ast.nodes"] = nil
      package.loaded["flemma.templating"] = nil
      package.loaded["flemma.templating.builtins.stdlib"] = nil
      package.loaded["flemma.templating.builtins.iterators"] = nil
      compiler = require("flemma.templating.compiler")
      ast = require("flemma.ast.nodes")
      local templating = require("flemma.templating")
      templating.setup()
    end)

    it("values() works in template blocks", function()
      local templating = require("flemma.templating")
      local pos = { start_line = 1 }
      local segments = {
        ast.code("for item in values(items) do", pos),
        ast.text("- ", pos),
        ast.expression(" item ", pos),
        ast.text("\n", pos),
        ast.code("end", pos),
      }
      local result = compiler.compile(segments)
      assert.is_nil(result.error)
      local env = templating.create_env()
      env.items = { "alpha", "beta" }
      env.__filename = "test.chat"
      local parts, diagnostics = compiler.execute(result, env)
      assert.equals(0, #diagnostics)
      local texts = {}
      for _, p in ipairs(parts) do
        if p.kind == "text" then
          table.insert(texts, p.text)
        end
      end
      local output = table.concat(texts)
      assert.truthy(output:find("- alpha"))
      assert.truthy(output:find("- beta"))
    end)

    it("each() provides loop metadata in templates", function()
      local templating = require("flemma.templating")
      local pos = { start_line = 1 }
      local segments = {
        ast.code("for item, loop in each(items) do", pos),
        ast.expression(" loop.index ", pos),
        ast.text(": ", pos),
        ast.expression(" item ", pos),
        ast.text("\n", pos),
        ast.code("end", pos),
      }
      local result = compiler.compile(segments)
      assert.is_nil(result.error)
      local env = templating.create_env()
      env.items = { "first", "second" }
      env.__filename = "test.chat"
      local parts, diagnostics = compiler.execute(result, env)
      assert.equals(0, #diagnostics)
      local texts = {}
      for _, p in ipairs(parts) do
        if p.kind == "text" then
          table.insert(texts, p.text)
        end
      end
      local output = table.concat(texts)
      assert.truthy(output:find("1: first"))
      assert.truthy(output:find("2: second"))
    end)
  end)
end)
