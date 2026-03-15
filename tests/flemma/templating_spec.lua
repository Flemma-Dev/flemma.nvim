describe("flemma.templating", function()
  local templating

  before_each(function()
    package.loaded["flemma.templating"] = nil
    package.loaded["flemma.templating.builtins.stdlib"] = nil
    package.loaded["flemma.templating.builtins.iterators"] = nil
    templating = require("flemma.templating")
    templating.clear()
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
    it("returns an empty table with no populators", function()
      local env = templating.create_env()
      assert.is_table(env)
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

  describe("clear", function()
    it("removes all populators", function()
      templating.register("test", {
        populate = function(env)
          env.val = true
        end,
      })
      templating.clear()
      local env = templating.create_env()
      assert.is_nil(env.val)
    end)

    it("resets module tracking", function()
      package.preload["test.templating.cleartest"] = function()
        return {
          name = "cleartest",
          priority = 300,
          populate = function(env)
            env.cleared = true
          end,
        }
      end

      templating.register_module("test.templating.cleartest")
      templating.clear()
      local env = templating.create_env()
      assert.is_nil(env.cleared)

      package.preload["test.templating.cleartest"] = nil
      package.loaded["test.templating.cleartest"] = nil
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
      assert.is_function(env.tostring)
      assert.is_nil(env.os)
      assert.is_nil(env.io)
    end)

    it("registers iterators built-in", function()
      templating.setup()
      local env = templating.create_env()
      assert.is_function(env.values)
      assert.is_function(env.each)
    end)
  end)
end)
