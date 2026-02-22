package.loaded["flemma.tools"] = nil
package.loaded["flemma.tools.registry"] = nil

local tools = require("flemma.tools")

describe("Async tool sources", function()
  before_each(function()
    tools.clear()
  end)

  describe("is_ready()", function()
    it("returns true by default (no async sources)", function()
      assert.is_true(tools.is_ready())
    end)

    it("returns false after register_async, true after done()", function()
      tools.register_async(function(_register, done)
        -- Don't call done yet
        assert.is_false(tools.is_ready())
        done()
      end)
      -- done() fires ready callbacks via vim.schedule, but is_ready() is synchronous
      assert.is_true(tools.is_ready())
    end)
  end)

  describe("register_async()", function()
    it("registered tools appear in get_all() after done()", function()
      tools.register_async(function(register, done)
        register("test_tool", {
          name = "test_tool",
          description = "A test tool",
          input_schema = { type = "object", properties = {} },
        })
        done()
      end)

      local all = tools.get_all()
      assert.is_not_nil(all.test_tool)
      assert.equals("A test tool", all.test_tool.description)
    end)

    it("done() is idempotent (double-call doesn't corrupt counter)", function()
      local captured_done
      tools.register_async(function(_register, done)
        captured_done = done
        done()
      end)
      assert.is_true(tools.is_ready())

      -- Second call should be a no-op
      captured_done()
      assert.is_true(tools.is_ready())
      -- Counter should not go negative
      captured_done()
      assert.is_true(tools.is_ready())
    end)

    it("error in resolve_fn auto-calls done()", function()
      tools.register_async(function(_register, _done)
        error("resolve failed!")
      end)
      -- Should still be ready because pcall caught the error and called done
      assert.is_true(tools.is_ready())
    end)

    it("timeout auto-completes with error", function()
      -- Use a very short timeout (1ms effective via timer)
      tools.register_async(function(_register, _done)
        -- Never call done — timeout should fire
      end, { timeout = 0 })

      assert.is_false(tools.is_ready())

      -- Wait for the timer to fire (libuv timer + vim.schedule)
      vim.wait(200, function()
        return tools.is_ready()
      end)

      assert.is_true(tools.is_ready())
    end)

    it("supports multiple async sources", function()
      local done_fns = {}

      tools.register_async(function(_register, done)
        table.insert(done_fns, done)
      end)
      tools.register_async(function(_register, done)
        table.insert(done_fns, done)
      end)

      assert.is_false(tools.is_ready())
      assert.equals(2, #done_fns)

      -- Complete first source
      done_fns[1]()
      assert.is_false(tools.is_ready())

      -- Complete second source
      done_fns[2]()
      assert.is_true(tools.is_ready())
    end)
  end)

  describe("on_ready()", function()
    it("fires immediately when already ready", function()
      local called = false
      tools.on_ready(function()
        called = true
      end)

      -- on_ready fires via vim.schedule, so we need to wait
      vim.wait(100, function()
        return called
      end)
      assert.is_true(called)
    end)

    it("deferred until all sources complete", function()
      local done_fns = {}
      local callback_count = 0

      tools.register_async(function(_register, done)
        table.insert(done_fns, done)
      end)
      tools.register_async(function(_register, done)
        table.insert(done_fns, done)
      end)

      tools.on_ready(function()
        callback_count = callback_count + 1
      end)

      -- Complete first source — callback should not fire
      done_fns[1]()
      vim.wait(50, function()
        return callback_count > 0
      end)
      assert.equals(0, callback_count)

      -- Complete second source — callback should fire
      done_fns[2]()
      vim.wait(100, function()
        return callback_count > 0
      end)
      assert.equals(1, callback_count)
    end)

    it("fires multiple callbacks", function()
      local captured_done
      tools.register_async(function(_register, done)
        captured_done = done
      end)

      local count_a, count_b = 0, 0
      tools.on_ready(function()
        count_a = count_a + 1
      end)
      tools.on_ready(function()
        count_b = count_b + 1
      end)

      captured_done()
      vim.wait(100, function()
        return count_a > 0 and count_b > 0
      end)
      assert.equals(1, count_a)
      assert.equals(1, count_b)
    end)
  end)

  describe("clear()", function()
    it("resets all async state", function()
      local captured_done
      tools.register_async(function(_register, done)
        captured_done = done
      end)
      assert.is_false(tools.is_ready())

      tools.clear()
      assert.is_true(tools.is_ready())

      -- Calling the old done should not corrupt state
      captured_done()
      assert.is_true(tools.is_ready())
    end)
  end)

  describe("register() dispatch", function()
    it("handles a function (async)", function()
      local captured_done
      tools.register(function(register, done)
        register("source_tool", {
          name = "source_tool",
          description = "From source",
          input_schema = { type = "object", properties = {} },
        })
        captured_done = done
      end)

      assert.is_false(tools.is_ready())
      captured_done()
      assert.is_true(tools.is_ready())

      local all = tools.get_all()
      assert.is_not_nil(all.source_tool)
    end)

    it("handles a table array of definitions (sync)", function()
      tools.register({
        {
          name = "def_a",
          description = "Definition A",
          input_schema = { type = "object", properties = {} },
        },
        {
          name = "def_b",
          description = "Definition B",
          input_schema = { type = "object", properties = {} },
        },
      })

      assert.is_true(tools.is_ready())
      local all = tools.get_all()
      assert.is_not_nil(all.def_a)
      assert.is_not_nil(all.def_b)
    end)

    it("handles a table with .resolve field (async)", function()
      local captured_done
      tools.register({
        resolve = function(register, done)
          register("resolved_tool", {
            name = "resolved_tool",
            description = "Async resolved",
            input_schema = { type = "object", properties = {} },
          })
          captured_done = done
        end,
      })

      assert.is_false(tools.is_ready())
      captured_done()
      assert.is_true(tools.is_ready())

      local all = tools.get_all()
      assert.is_not_nil(all.resolved_tool)
    end)

    it("handles a module name (sync)", function()
      -- Use an existing builtin module
      tools.register("extras.flemma.tools.calculator")

      assert.is_true(tools.is_ready())
      assert.is_true(tools.count() > 0)
      assert.is_not_nil(tools.get("calculator"))
    end)
  end)
end)
