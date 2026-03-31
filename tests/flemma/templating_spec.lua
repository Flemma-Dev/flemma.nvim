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
