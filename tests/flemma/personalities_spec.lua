local personalities

describe("flemma.personalities", function()
  before_each(function()
    package.loaded["flemma.personalities"] = nil
    personalities = require("flemma.personalities")
  end)

  describe("registry", function()
    it("implements flemma.Registry contract", function()
      assert.is_function(personalities.register)
      assert.is_function(personalities.unregister)
      assert.is_function(personalities.get)
      assert.is_function(personalities.get_all)
      assert.is_function(personalities.has)
      assert.is_function(personalities.clear)
      assert.is_function(personalities.count)
    end)

    it("registers and retrieves a personality", function()
      local mock = { render = function() return "test" end }
      personalities.register("test-personality", mock)
      assert.is_true(personalities.has("test-personality"))
      assert.equals(mock, personalities.get("test-personality"))
    end)

    it("returns nil for unknown personality", function()
      assert.is_nil(personalities.get("nonexistent"))
    end)

    it("rejects names with dots", function()
      assert.has_error(function()
        personalities.register("my.personality", { render = function() return "" end })
      end)
    end)

    it("unregisters a personality", function()
      personalities.register("temp", { render = function() return "" end })
      assert.is_true(personalities.unregister("temp"))
      assert.is_false(personalities.has("temp"))
    end)

    pending("registers built-in coding-assistant personality", function()
      -- Enabled after coding-assistant module is created (Task 5)
      personalities.setup()
      assert.is_true(personalities.has("coding-assistant"))
    end)
  end)
end)
