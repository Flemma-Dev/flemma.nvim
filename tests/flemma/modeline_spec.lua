describe("flemma.utilities.modeline", function()
  local modeline = require("flemma.utilities.modeline")

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

    it("extracts provider and model from positional tokens", function()
      local result = modeline.parse("vertex gemini-2.5-flash-lite")

      assert.are.equal("vertex", result[1])
      assert.are.equal("gemini-2.5-flash-lite", result[2])
    end)

    it("supports positional tokens followed by assignments", function()
      local result = modeline.parse("vertex gemini-2.5-flash-lite thinking_budget=24576 max_tokens=65535")

      assert.are.equal("vertex", result[1])
      assert.are.equal("gemini-2.5-flash-lite", result[2])
      assert.are.equal(24576, result.thinking_budget)
      assert.are.equal(65535, result.max_tokens)
    end)

    it("coerces positional arguments to their natural types", function()
      local result = modeline.parse("true false 0 1 key=value")

      assert.is_true(result[1])
      assert.is_false(result[2])
      assert.are.equal(0, result[3])
      assert.are.equal(1, result[4])
      assert.are.equal("value", result.key)
    end)

    it("handles quoted keyword values with spaces", function()
      local result = modeline.parse('value1 key2="value 2 2 2"')

      assert.are.equal("value1", result[1])
      assert.are.equal("value 2 2 2", result.key2)
    end)

    it("preserves quoted values as strings without coercion", function()
      local result = modeline.parse('"true" "42" "nil"')

      assert.are.equal("true", result[1])
      assert.are.equal("42", result[2])
      assert.are.equal("nil", result[3])
    end)

    it("preserves quoted keyword values as strings without coercion", function()
      local result = modeline.parse('enabled="true" count="0" empty="nil"')

      assert.are.equal("true", result.enabled)
      assert.are.equal("0", result.count)
      assert.are.equal("nil", result.empty)
    end)

    it("handles quoted positional with spaces", function()
      local result = modeline.parse('"hello world" second')

      assert.are.equal("hello world", result[1])
      assert.are.equal("second", result[2])
    end)

    it("handles empty quoted keyword values", function()
      local result = modeline.parse('key="" other=value')

      assert.are.equal("", result.key)
      assert.are.equal("value", result.other)
    end)

    it("handles mixed quoted and unquoted tokens", function()
      local result = modeline.parse('provider model temperature=0.5 label="my chat" debug=false')

      assert.are.equal("provider", result[1])
      assert.are.equal("model", result[2])
      assert.are.equal(0.5, result.temperature)
      assert.are.equal("my chat", result.label)
      assert.is_false(result.debug)
    end)

    it("supports escaped quotes inside quoted values", function()
      local result = modeline.parse([[key="value with \"quotes\" inside"]])

      assert.are.equal('value with "quotes" inside', result.key)
    end)

    it("supports escaped backslash inside quoted values", function()
      local result = modeline.parse([[key="path\\to\\file"]])

      assert.are.equal([[path\to\file]], result.key)
    end)

    it("treats backslash as literal outside quotes", function()
      local result = modeline.parse([[path\to\file]])

      assert.are.equal([[path\to\file]], result[1])
    end)

    it("treats unclosed quotes as literal characters", function()
      local result = modeline.parse('"unclosed')

      assert.are.equal('"unclosed', result[1])
    end)

    it("coerces nil and null positionals to absent entries", function()
      local result = modeline.parse("keep nil null")

      assert.are.equal("keep", result[1])
      assert.is_nil(result[2])
      assert.is_nil(result[3])
    end)

    -- Single quote support
    it("handles single-quoted keyword values", function()
      local result = modeline.parse("key='hello world'")

      assert.are.equal("hello world", result.key)
    end)

    it("handles single-quoted positionals", function()
      local result = modeline.parse("'true' '42'")

      assert.are.equal("true", result[1])
      assert.are.equal("42", result[2])
    end)

    it("supports escaped single quote inside single-quoted values", function()
      local result = modeline.parse([[key='it\'s a test']])

      assert.are.equal("it's a test", result.key)
    end)

    it("supports escaped backslash inside single-quoted values", function()
      local result = modeline.parse([[key='path\\to\\file']])

      assert.are.equal([[path\to\file]], result.key)
    end)

    -- Empty value (key= vs key="")
    it("treats empty keyword value as nil", function()
      local result = modeline.parse("key= other=value")

      assert.is_nil(result.key)
      assert.are.equal("value", result.other)
    end)

    it('distinguishes key= (nil) from key="" (empty string)', function()
      local result = modeline.parse('absent= present=""')

      assert.is_nil(result.absent)
      assert.are.equal("", result.present)
    end)

    -- Comma-separated lists
    it("splits comma-separated values into a list", function()
      local result = modeline.parse("tags=foo,bar,baz")

      assert.are.same({ "foo", "bar", "baz" }, result.tags)
    end)

    it("coerces individual list items", function()
      local result = modeline.parse("values=1,2,3")

      assert.are.same({ 1, 2, 3 }, result.values)
    end)

    it("coerces mixed types in lists", function()
      local result = modeline.parse("mix=true,42,hello")

      assert.are.same({ true, 42, "hello" }, result.mix)
    end)

    it("preserves quoted comma as literal string", function()
      local result = modeline.parse('label="foo,bar"')

      assert.are.equal("foo,bar", result.label)
    end)

    it("handles quoted items in comma lists", function()
      local result = modeline.parse([[list="of strings","that can have, their own","commas"]])

      assert.are.same({ "of strings", "that can have, their own", "commas" }, result.list)
    end)

    it("handles mixed quoted and unquoted items in lists", function()
      local result = modeline.parse([[items="hello world",42,true]])

      assert.are.same({ "hello world", 42, true }, result.items)
    end)

    it("handles comma-separated positional values", function()
      local result = modeline.parse("a,b,c")

      assert.are.same({ "a", "b", "c" }, result[1])
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

    it("coerces positional arguments", function()
      local args = { "true", "42", "hello" }
      local result = modeline.parse_args(args)

      assert.is_true(result[1])
      assert.are.equal(42, result[2])
      assert.are.equal("hello", result[3])
    end)

    it("strips quotes from keyword values", function()
      local args = { 'key="value"' }
      local result = modeline.parse_args(args)

      assert.are.equal("value", result.key)
    end)

    it("splits comma-separated keyword values", function()
      local args = { "tags=a,b,c" }
      local result = modeline.parse_args(args)

      assert.are.same({ "a", "b", "c" }, result.tags)
    end)
  end)
end)
