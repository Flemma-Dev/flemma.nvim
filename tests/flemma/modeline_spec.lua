describe("flemma.modeline", function()
  local modeline = require("flemma.modeline")

  describe("parse", function()
    it("coerces primitive types from a string line", function()
      local result = modeline.parse("temperature=0.5 retries=3 enabled=true name=chat")

      assert.are.equal(0.5, result.temperature)
      assert.are.equal(3, result.retries)
      assert.is_true(result.enabled)
      assert.are.equal("chat", result.name)
    end)

    it("treats nil-like values as absent keys", function()
      local result = modeline.parse("option=nil other=null keep=value")

      assert.is_nil(result.option)
      assert.is_nil(result.other)
      assert.are.equal("value", result.keep)
    end)

    it("returns empty table when input has no assignments", function()
      local result = modeline.parse("no_equals here")

      assert.are.same({}, result)
    end)
  end)

  describe("parse_args", function()
    it("parses assignments from an argument list", function()
      local args = { "openai", "gpt-4o", "temperature=0.4", "debug=false", "timeout=30" }
      local result = modeline.parse_args(args, 3)

      assert.are.equal(0.4, result.temperature)
      assert.is_false(result.debug)
      assert.are.equal(30, result.timeout)
    end)

    it("ignores arguments before the start index", function()
      local args = { "temperature=0.2", "debug=true" }
      local result = modeline.parse_args(args, 2)

      assert.are.equal(true, result.debug)
      assert.is_nil(result.temperature)
    end)

    it("handles empty lists safely", function()
      assert.are.same({}, modeline.parse_args({}, 1))
    end)
  end)
end)
