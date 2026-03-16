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
      templating.clear()
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
