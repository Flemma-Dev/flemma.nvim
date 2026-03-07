describe("flemma.codeblock.parsers registry", function()
  local parsers

  before_each(function()
    package.loaded["flemma.codeblock.parsers"] = nil
    package.loaded["flemma.codeblock.parsers.lua"] = nil
    package.loaded["flemma.codeblock.parsers.json"] = nil
    parsers = require("flemma.codeblock.parsers")
  end)

  describe("clear()", function()
    it("removes all registered parsers", function()
      -- Force a lazy load by accessing json
      parsers.get("json")
      assert.is_true(parsers.count() > 0)

      parsers.clear()
      assert.are.equal(0, parsers.count())
    end)

    it("does not remove lazy-loadable modules from has()", function()
      parsers.clear()
      -- has() checks PARSER_MODULES, which survives clear
      assert.is_true(parsers.has("json"))
      assert.is_true(parsers.has("lua"))
    end)
  end)

  describe("count()", function()
    it("returns 0 before any access", function()
      assert.are.equal(0, parsers.count())
    end)

    it("increments after get() triggers lazy load", function()
      parsers.get("json")
      assert.are.equal(1, parsers.count())
    end)

    it("increments after explicit register()", function()
      parsers.register("yaml", function(code)
        return code
      end)
      assert.are.equal(1, parsers.count())
    end)
  end)

  describe("get_all()", function()
    it("eagerly loads all lazy modules", function()
      local all = parsers.get_all()
      assert.is_not_nil(all["json"])
      assert.is_not_nil(all["lua"])
    end)

    it("includes custom parsers", function()
      local fn = function(code)
        return code
      end
      parsers.register("yaml", fn)
      local all = parsers.get_all()
      assert.is_not_nil(all["yaml"])
    end)

    it("returns a copy", function()
      local all = parsers.get_all()
      all["json"] = nil
      assert.is_not_nil(parsers.get("json"))
    end)
  end)

  describe("unregister()", function()
    it("removes a loaded parser and returns true", function()
      parsers.get("json") -- trigger lazy load
      assert.is_true(parsers.unregister("json"))
      assert.are.equal(0, parsers.count())
    end)

    it("returns false for a parser that was never loaded", function()
      assert.is_false(parsers.unregister("json"))
    end)

    it("is case-insensitive", function()
      parsers.get("json")
      assert.is_true(parsers.unregister("JSON"))
    end)
  end)
end)
