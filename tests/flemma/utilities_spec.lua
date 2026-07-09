-- Merged pure-function utility specs.
-- Each top-level describe block owns its module isolation (before_each clears
-- and re-requires only its own module), keeping blocks independent.

package.loaded["flemma.utilities.truncate"] = nil
package.loaded["flemma.utilities.string"] = nil

describe("flemma.utilities.json.encode_ordered", function()
  local json

  before_each(function()
    package.loaded["flemma.utilities.json"] = nil
    json = require("flemma.utilities.json")
  end)

  describe("basic types", function()
    it("encodes a string", function()
      assert.are.equal('"hello"', json.encode_ordered("hello"))
    end)

    it("encodes an integer", function()
      assert.are.equal("42", json.encode_ordered(42))
    end)

    it("encodes a float", function()
      local result = json.encode_ordered(3.14)
      assert.is_truthy(result:match("3%.14"))
    end)

    it("encodes true", function()
      assert.are.equal("true", json.encode_ordered(true))
    end)

    it("encodes false", function()
      assert.are.equal("false", json.encode_ordered(false))
    end)

    it("encodes nil as null", function()
      assert.are.equal("null", json.encode_ordered(nil))
    end)
  end)

  describe("arrays", function()
    it("encodes a simple array", function()
      assert.are.equal("[1,2,3]", json.encode_ordered({ 1, 2, 3 }))
    end)

    it("preserves array element order", function()
      assert.are.equal('["c","a","b"]', json.encode_ordered({ "c", "a", "b" }))
    end)

    it("handles nested arrays", function()
      assert.are.equal("[[1,2],[3,4]]", json.encode_ordered({ { 1, 2 }, { 3, 4 } }))
    end)

    it("handles arrays of objects with sorted keys", function()
      local input = {
        { z = 1, a = 2 },
        { m = 3, b = 4 },
      }
      local result = json.encode_ordered(input)
      assert.are.equal('[{"a":2,"z":1},{"b":4,"m":3}]', result)
    end)
  end)

  describe("objects with sorted keys", function()
    it("sorts keys alphabetically", function()
      local input = { z = 1, a = 2, m = 3 }
      local result = json.encode_ordered(input)
      assert.are.equal('{"a":2,"m":3,"z":1}', result)
    end)

    it("sorts nested object keys recursively", function()
      local input = {
        outer = { z = true, a = false },
        config = { beta = 2, alpha = 1 },
      }
      local result = json.encode_ordered(input)
      assert.are.equal('{"config":{"alpha":1,"beta":2},"outer":{"a":false,"z":true}}', result)
    end)

    it("sorts keys at all nesting depths", function()
      local input = {
        c = {
          f = {
            z = "deep",
            a = "also deep",
          },
          b = "mid",
        },
        a = "top",
      }
      local result = json.encode_ordered(input)
      assert.are.equal('{"a":"top","c":{"b":"mid","f":{"a":"also deep","z":"deep"}}}', result)
    end)

    it("handles empty objects", function()
      local result = json.encode_ordered(vim.empty_dict())
      assert.are.equal("{}", result)
    end)

    it("handles mixed object and array nesting", function()
      local input = {
        z_key = { "first", "second" },
        a_key = { nested = true },
      }
      local result = json.encode_ordered(input)
      assert.are.equal('{"a_key":{"nested":true},"z_key":["first","second"]}', result)
    end)
  end)

  describe("trailing_keys parameter", function()
    it("moves specified keys to end in given order", function()
      local input = {
        messages = { "dynamic" },
        model = "gpt-4",
        tools = { "tool1" },
        stream = true,
      }
      local result = json.encode_ordered(input, { "tools", "messages" })
      -- Expected: model, stream sorted alphabetically first, then tools, then messages
      assert.are.equal('{"model":"gpt-4","stream":true,"tools":["tool1"],"messages":["dynamic"]}', result)
    end)

    it("sorts non-trailing keys alphabetically", function()
      local input = {
        z_param = 1,
        a_param = 2,
        messages = {},
      }
      local result = json.encode_ordered(input, { "messages" })
      assert.are.equal('{"a_param":2,"z_param":1,"messages":[]}', result)
    end)

    it("handles trailing keys that are absent from the table", function()
      local input = {
        model = "gpt-4",
        stream = true,
      }
      -- "messages" is in trailing_keys but not in the table — should not appear
      local result = json.encode_ordered(input, { "messages" })
      assert.are.equal('{"model":"gpt-4","stream":true}', result)
    end)

    it("handles all keys being trailing keys", function()
      local input = {
        tools = { "a" },
        messages = { "b" },
      }
      local result = json.encode_ordered(input, { "tools", "messages" })
      assert.are.equal('{"tools":["a"],"messages":["b"]}', result)
    end)

    it("does not affect nested object key ordering", function()
      local input = {
        config = { z = 1, a = 2 },
        messages = {},
      }
      local result = json.encode_ordered(input, { "messages" })
      -- config's keys should be sorted; messages trails
      assert.are.equal('{"config":{"a":2,"z":1},"messages":[]}', result)
    end)

    it("trailing_keys only applies to top level", function()
      local input = {
        wrapper = {
          messages = "inner",
          alpha = "first",
        },
        messages = "outer",
      }
      local result = json.encode_ordered(input, { "messages" })
      -- wrapper's "messages" key is sorted normally inside wrapper
      assert.are.equal('{"wrapper":{"alpha":"first","messages":"inner"},"messages":"outer"}', result)
    end)

    it("empty trailing_keys behaves like pure sorted encoding", function()
      local input = { z = 1, a = 2 }
      local sorted_result = json.encode_ordered(input)
      local empty_trailing_result = json.encode_ordered(input, {})
      assert.are.equal(sorted_result, empty_trailing_result)
    end)
  end)

  describe("determinism", function()
    it("produces identical output across multiple calls", function()
      local input = {
        model = "claude-sonnet-4-20250514",
        max_tokens = 8192,
        stream = true,
        temperature = 0.7,
        messages = { { role = "user", content = "hello" } },
        tools = { { name = "bash", description = "Run bash" } },
        system = "You are helpful",
      }
      local first = json.encode_ordered(input, { "system", "tools", "messages" })
      -- Call multiple times — must be identical every time
      for _ = 1, 20 do
        assert.are.equal(first, json.encode_ordered(input, { "system", "tools", "messages" }))
      end
    end)

    it("produces identical output regardless of table construction order", function()
      -- Construct the same logical table two different ways
      local a = { model = "gpt-4", stream = true, messages = {} }
      local b = {}
      b.messages = {}
      b.stream = true
      b.model = "gpt-4"

      assert.are.equal(json.encode_ordered(a, { "messages" }), json.encode_ordered(b, { "messages" }))
    end)
  end)

  describe("special values", function()
    it("encodes string values with special characters", function()
      local input = { key = 'value with "quotes" and \\backslash' }
      local result = json.encode_ordered(input)
      -- Should contain escaped quotes and backslash
      assert.is_truthy(result:match('\\"quotes\\"'))
      assert.is_truthy(result:match("\\\\backslash"))
    end)

    it("handles vim.NIL as null when present", function()
      -- vim.NIL should be encoded as null (though flemma.json.decode avoids it)
      local input = { a = vim.NIL }
      local result = json.encode_ordered(input)
      assert.are.equal('{"a":null}', result)
    end)
  end)

  describe("Anthropic request body shape", function()
    it("places config keys first, then system, tools, messages last", function()
      local request_body = {
        max_tokens = 16384,
        model = "claude-sonnet-4-20250514",
        messages = {
          { role = "user", content = { { type = "text", text = "Hello" } } },
        },
        cache_control = { type = "ephemeral" },
        thinking = { type = "enabled", budget_tokens = 10000 },
        stream = true,
        tool_choice = { type = "auto" },
        tools = {
          { name = "bash", description = "Execute bash commands", input_schema = {} },
        },
        system = {
          { type = "text", text = "You are helpful", cache_control = { type = "ephemeral" } },
        },
      }

      local result = json.encode_ordered(request_body, { "system", "tools", "messages" })

      -- Verify key order by finding positions in the output string
      local pos_cache_control = result:find('"cache_control"')
      local pos_max_tokens = result:find('"max_tokens"')
      local pos_model = result:find('"model"')
      local pos_stream = result:find('"stream"')
      local pos_thinking = result:find('"thinking"')
      local pos_tool_choice = result:find('"tool_choice"')
      local pos_system = result:find('"system"')
      local pos_tools = result:find('"tools"')
      local pos_messages = result:find('"messages"')

      -- Config keys sorted alphabetically first
      assert.is_truthy(pos_cache_control < pos_max_tokens)
      assert.is_truthy(pos_max_tokens < pos_model)
      assert.is_truthy(pos_model < pos_stream)
      assert.is_truthy(pos_stream < pos_thinking)
      assert.is_truthy(pos_thinking < pos_tool_choice)

      -- Then trailing keys in order: system, tools, messages
      assert.is_truthy(pos_tool_choice < pos_system)
      assert.is_truthy(pos_system < pos_tools)
      assert.is_truthy(pos_tools < pos_messages)
    end)
  end)

  describe("round-trip with json.decode", function()
    it("produces valid JSON that decodes to the same data", function()
      local input = {
        model = "test",
        stream = true,
        messages = { { role = "user", content = "hi" } },
      }
      local encoded = json.encode_ordered(input, { "messages" })
      local decoded = json.decode(encoded)
      assert.are.same(input, decoded)
    end)
  end)
end)

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

    -- preserve_nil option
    it("stores vim.NIL for keyword nil values when preserve_nil is true", function()
      local result = modeline.parse("temperature= other=value", { preserve_nil = true })

      assert.are.equal(vim.NIL, result.temperature)
      assert.are.equal("value", result.other)
    end)

    it("stores vim.NIL for nil/null keywords when preserve_nil is true", function()
      local result = modeline.parse("option=nil other=null keep=value", { preserve_nil = true })

      assert.are.equal(vim.NIL, result.option)
      assert.are.equal(vim.NIL, result.other)
      assert.are.equal("value", result.keep)
    end)

    it("does not affect positional nils when preserve_nil is true", function()
      local result = modeline.parse("keep nil null", { preserve_nil = true })

      assert.are.equal("keep", result[1])
      assert.is_nil(result[2])
      assert.is_nil(result[3])
    end)

    it('still distinguishes key= from key="" when preserve_nil is true', function()
      local result = modeline.parse('cleared= present=""', { preserve_nil = true })

      assert.are.equal(vim.NIL, result.cleared)
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

    it("stores vim.NIL for empty keyword values when preserve_nil is true", function()
      local args = { "openai", "gpt-4o", "temperature=" }
      local result = modeline.parse_args(args, 1, { preserve_nil = true })

      assert.are.equal("openai", result[1])
      assert.are.equal("gpt-4o", result[2])
      assert.are.equal(vim.NIL, result.temperature)
    end)
  end)

  describe("split_on", function()
    it("returns nil when the delimiter is absent", function()
      assert.is_nil(modeline.split_on("plain-value", ";"))
    end)

    it("splits on the delimiter outside quotes", function()
      assert.are.same({ "a", "b=1", "c=2" }, modeline.split_on("a;b=1;c=2", ";"))
    end)

    it("does not split inside quoted regions", function()
      assert.are.same({ "a", "note='x;y'" }, modeline.split_on("a;note='x;y'", ";"))
    end)
  end)

  describe("parse_matrix", function()
    it("returns the value unchanged when no matrix parameters are present", function()
      local primary, params = modeline.parse_matrix("vertex/gemini-3.1-pro-preview")
      assert.equals("vertex/gemini-3.1-pro-preview", primary)
      assert.are.same({}, params)
    end)

    it("splits the primary from key=value parameters", function()
      local primary, params = modeline.parse_matrix("vertex/gemini-3.1-pro-preview;project_id=stans-playground")
      assert.equals("vertex/gemini-3.1-pro-preview", primary)
      assert.are.same({ project_id = "stans-playground" }, params)
    end)

    it("coerces parameter values like the modeline grammar", function()
      local _, params = modeline.parse_matrix("m;n=3;flag=true;name=x")
      assert.are.same({ n = 3, flag = true, name = "x" }, params)
    end)

    it("keeps the last value for repeated keys", function()
      local _, params = modeline.parse_matrix("m;p=a;p=b")
      assert.are.same({ p = "b" }, params)
    end)

    it("respects quotes around the delimiter", function()
      local _, params = modeline.parse_matrix("m;note='a;b'")
      assert.are.same({ note = "a;b" }, params)
    end)

    it("ignores segments without an equals sign", function()
      local primary, params = modeline.parse_matrix("m;loose;k=v")
      assert.equals("m", primary)
      assert.are.same({ k = "v" }, params)
    end)

    it("returns raw ignored segments as extras", function()
      local primary, params, extras = modeline.parse_matrix("m;loose;k=v;api-key=1")
      assert.equals("m", primary)
      assert.are.same({ k = "v" }, params)
      assert.are.same({ "loose", "api-key=1" }, extras)
    end)

    it("returns empty extras when every segment parses", function()
      local _, _, extras = modeline.parse_matrix("m;k=v")
      assert.are.same({}, extras)
      local _, _, plain_extras = modeline.parse_matrix("plain-model")
      assert.are.same({}, plain_extras)
    end)

    it("drops explicit nil values by default", function()
      local _, params = modeline.parse_matrix("m;p=nil")
      assert.are.same({}, params)
    end)

    it("preserves explicit nil values as vim.NIL with preserve_nil", function()
      local _, params = modeline.parse_matrix("m;p=nil;q=1", { preserve_nil = true })
      assert.equals(vim.NIL, params.p)
      assert.equals(1, params.q)
    end)

    it("splits comma lists in parameter values", function()
      local _, params = modeline.parse_matrix("m;tags=a,b")
      assert.are.same({ tags = { "a", "b" } }, params)
    end)
  end)
end)

describe("flemma.utilities.color", function()
  local color

  before_each(function()
    package.loaded["flemma.utilities.color"] = nil
    color = require("flemma.utilities.color")
  end)

  describe("hex_to_rgb", function()
    it("should convert hex with hash prefix", function()
      local rgb = color.hex_to_rgb("#ff0000")
      assert.are.equal(255, rgb.r)
      assert.are.equal(0, rgb.g)
      assert.are.equal(0, rgb.b)
    end)

    it("should convert hex without hash prefix", function()
      local rgb = color.hex_to_rgb("00ff00")
      assert.are.equal(0, rgb.r)
      assert.are.equal(255, rgb.g)
      assert.are.equal(0, rgb.b)
    end)

    it("should return nil for nil input", function()
      assert.is_nil(color.hex_to_rgb(nil))
    end)

    it("should return nil for invalid hex length", function()
      assert.is_nil(color.hex_to_rgb("#fff"))
    end)
  end)

  describe("rgb_to_hex", function()
    it("should convert RGB to hex", function()
      assert.are.equal("#ff0000", color.rgb_to_hex({ r = 255, g = 0, b = 0 }))
      assert.are.equal("#000000", color.rgb_to_hex({ r = 0, g = 0, b = 0 }))
      assert.are.equal("#ffffff", color.rgb_to_hex({ r = 255, g = 255, b = 255 }))
    end)
  end)

  describe("blend", function()
    it("should add colors", function()
      local result = color.blend({ r = 100, g = 50, b = 0 }, { r = 10, g = 20, b = 30 }, "+")
      assert.are.equal(110, result.r)
      assert.are.equal(70, result.g)
      assert.are.equal(30, result.b)
    end)

    it("should subtract colors", function()
      local result = color.blend({ r = 100, g = 50, b = 30 }, { r = 10, g = 20, b = 30 }, "-")
      assert.are.equal(90, result.r)
      assert.are.equal(30, result.g)
      assert.are.equal(0, result.b)
    end)

    it("should clamp to 0-255", function()
      local result = color.blend({ r = 250, g = 0, b = 0 }, { r = 10, g = 10, b = 10 }, "+")
      assert.are.equal(255, result.r)

      local sub = color.blend({ r = 5, g = 0, b = 0 }, { r = 10, g = 10, b = 10 }, "-")
      assert.are.equal(0, sub.r)
      assert.are.equal(0, sub.g)
    end)
  end)

  describe("relative_luminance", function()
    it("should return 0 for black", function()
      assert.is_near(0.0, color.relative_luminance("#000000"), 0.001)
    end)

    it("should return 1 for white", function()
      assert.is_near(1.0, color.relative_luminance("#ffffff"), 0.001)
    end)

    it("should compute luminance for mid-gray", function()
      -- #808080 -> each channel 128/255 = 0.502
      -- linearized: ((0.502 + 0.055) / 1.055)^2.4 ≈ 0.2159
      -- luminance: 0.2126*0.2159 + 0.7152*0.2159 + 0.0722*0.2159 ≈ 0.2159
      local lum = color.relative_luminance("#808080")
      assert.is_near(0.2159, lum, 0.01)
    end)
  end)

  describe("contrast_ratio", function()
    it("should return 21:1 for black on white", function()
      assert.is_near(21.0, color.contrast_ratio("#ffffff", "#000000"), 0.1)
    end)

    it("should return 1:1 for same color", function()
      assert.is_near(1.0, color.contrast_ratio("#ff0000", "#ff0000"), 0.01)
    end)

    it("should be symmetric", function()
      local ratio_ab = color.contrast_ratio("#336699", "#ccddee")
      local ratio_ba = color.contrast_ratio("#ccddee", "#336699")
      assert.is_near(ratio_ab, ratio_ba, 0.001)
    end)
  end)

  describe("ensure_contrast", function()
    it("should return fg unchanged when contrast is sufficient", function()
      -- White on black is 21:1 — well above 4.5
      local result = color.ensure_contrast("#ffffff", "#000000", 4.5)
      assert.are.equal("#ffffff", result)
    end)

    it("should lighten fg against dark bg when contrast is insufficient", function()
      -- Dark gray on black — very low contrast
      local result = color.ensure_contrast("#222222", "#000000", 4.5)
      -- Result should be lighter than #222222
      local original_lum = color.relative_luminance("#222222")
      local adjusted_lum = color.relative_luminance(result)
      assert.is_true(adjusted_lum > original_lum, "should lighten toward white")
      -- And should meet the target ratio
      local ratio = color.contrast_ratio(result, "#000000")
      assert.is_true(ratio >= 4.5, "should meet 4.5:1 contrast: got " .. tostring(ratio))
    end)

    it("should darken fg against light bg when contrast is insufficient", function()
      -- Light gray on white — very low contrast
      local result = color.ensure_contrast("#dddddd", "#ffffff", 4.5)
      local original_lum = color.relative_luminance("#dddddd")
      local adjusted_lum = color.relative_luminance(result)
      assert.is_true(adjusted_lum < original_lum, "should darken toward black")
      local ratio = color.contrast_ratio(result, "#ffffff")
      assert.is_true(ratio >= 4.5, "should meet 4.5:1 contrast: got " .. tostring(ratio))
    end)

    it("should handle extreme case: same color as bg", function()
      local result = color.ensure_contrast("#336699", "#336699", 4.5)
      local ratio = color.contrast_ratio(result, "#336699")
      assert.is_true(ratio >= 4.5, "should meet 4.5:1 even when fg == bg: got " .. tostring(ratio))
    end)
  end)
end)

describe("truncate_line()", function()
  local truncate = require("flemma.utilities.truncate")

  it("returns short lines unchanged", function()
    local result = truncate.truncate_line("hello world", 500)
    assert.equals("hello world", result.text)
    assert.is_false(result.truncated)
  end)

  it("truncates long lines with suffix", function()
    local long = string.rep("x", 600)
    local result = truncate.truncate_line(long, 500)
    assert.is_true(result.truncated)
    assert.truthy(result.text:find("%[truncated%]$"))
    assert.truthy(#result.text <= 500)
  end)

  it("uses default max_chars when not specified", function()
    local long = string.rep("x", 600)
    local result = truncate.truncate_line(long)
    assert.is_true(result.truncated)
    assert.truthy(#result.text <= truncate.MAX_LINE_CHARS)
  end)

  it("handles exact boundary length", function()
    local exact = string.rep("x", 500)
    local result = truncate.truncate_line(exact, 500)
    assert.equals(exact, result.text)
    assert.is_false(result.truncated)
  end)

  it("handles empty string", function()
    local result = truncate.truncate_line("", 500)
    assert.equals("", result.text)
    assert.is_false(result.truncated)
  end)

  it("handles very small max_chars", function()
    local result = truncate.truncate_line("hello world", 5)
    assert.is_true(result.truncated)
    assert.truthy(#result.text > 0)
  end)

  it("does not split multi-byte UTF-8 characters", function()
    -- U+2500 (─) is 3 bytes: 0xe2 0x94 0x80
    -- Build a line: "aaa" (3 bytes) + 200 box-drawing chars (600 bytes) = 603 bytes
    local line = "aaa" .. string.rep("\xe2\x94\x80", 200)
    -- max_chars=20, suffix "... [truncated]" is 15 bytes, budget = 5
    -- Budget of 5 fits "aaa" (3 bytes) but not the next box char (needs 3 more bytes)
    local result = truncate.truncate_line(line, 20)
    assert.is_true(result.truncated)
    assert.truthy(result.text:find("%[truncated%]$"))
    -- The kept prefix must end at a valid UTF-8 boundary — just "aaa"
    local suffix = "... [truncated]"
    local kept = result.text:sub(1, #result.text - #suffix)
    assert.equals("aaa", kept)
  end)

  it("keeps complete multi-byte characters that fit", function()
    -- 2 box-drawing chars (6 bytes) + 1 ASCII = 7 bytes total
    local line = "\xe2\x94\x80\xe2\x94\x80x"
    -- Not truncated when limit is large enough
    local result = truncate.truncate_line(line, 500)
    assert.is_false(result.truncated)
    assert.equals(line, result.text)
  end)

  it("does not split 2-byte Cyrillic characters", function()
    -- U+041F (П) is 2 bytes: 0xd0 0x9f; U+0440 (р) is 2 bytes: 0xd1 0x80
    -- "Привет" = 12 bytes (6 Cyrillic chars x 2 bytes each)
    local privet = "\xd0\x9f\xd1\x80\xd0\xb8\xd0\xb2\xd0\xb5\xd1\x82" -- "Привет"
    local line = string.rep(privet, 50) -- 600 bytes
    -- max_chars=20, suffix=15 bytes, budget=5 — fits 2 complete 2-byte chars (4 bytes)
    local result = truncate.truncate_line(line, 20)
    assert.is_true(result.truncated)
    local suffix = "... [truncated]"
    local kept = result.text:sub(1, #result.text - #suffix)
    -- 5 byte budget: 2 Cyrillic chars (4 bytes) fit, 3rd (bytes 5-6) does not
    assert.equals(4, #kept)
    assert.equals("\xd0\x9f\xd1\x80", kept) -- "П" + "р"
  end)

  it("does not split 4-byte emoji characters", function()
    -- U+1F600 (grinning face) is 4 bytes: 0xf0 0x9f 0x98 0x80
    local emoji = "\xf0\x9f\x98\x80" -- U+1F600 😀
    local line = string.rep(emoji, 150) -- 600 bytes
    -- max_chars=20, suffix=15 bytes, budget=5 — 4-byte emoji fits once (4 bytes)
    local result = truncate.truncate_line(line, 20)
    assert.is_true(result.truncated)
    local suffix = "... [truncated]"
    local kept = result.text:sub(1, #result.text - #suffix)
    assert.equals(4, #kept)
    assert.equals(emoji, kept)
  end)

  it("handles cut point landing on each byte of a 4-byte emoji", function()
    -- "ab" (2 bytes) + U+1F600 (4 bytes) + padding = line that truncates mid-emoji
    local emoji = "\xf0\x9f\x98\x80" -- U+1F600 😀
    -- budget lands on byte 3 of the emoji (offset 5 in the string)
    -- "ab" = 2 bytes, emoji starts at byte 3, so budget=4 lands on 2nd byte of emoji
    local line = "ab" .. string.rep(emoji, 150)
    local result = truncate.truncate_line(line, 19)
    -- budget = 19 - 15 = 4; "ab" (2 bytes) + emoji byte 1-2 don't complete, keep "ab"
    assert.is_true(result.truncated)
    local suffix = "... [truncated]"
    local kept = result.text:sub(1, #result.text - #suffix)
    assert.equals("ab", kept)
  end)
end)

describe("flemma.utilities.string", function()
  local str = require("flemma.utilities.string")

  describe("strwidth", function()
    it("returns 0 for empty string", function()
      assert.are.equal(0, str.strwidth(""))
    end)

    it("returns byte count for ASCII", function()
      assert.are.equal(5, str.strwidth("hello"))
    end)

    it("returns 1 for single-column multibyte character", function()
      -- "…" (U+2026) is 3 bytes, 1 display column
      assert.are.equal(1, str.strwidth("…"))
    end)

    it("returns 2 for CJK double-width character", function()
      -- "你" (U+4F60) is 3 bytes, 2 display columns
      assert.are.equal(2, str.strwidth("你"))
    end)

    it("counts mixed ASCII and multibyte correctly", function()
      -- "hi你" = 2 (ASCII) + 2 (CJK) = 4 display columns
      assert.are.equal(4, str.strwidth("hi你"))
    end)

    it("counts Unicode symbols used in the usage bar", function()
      -- "Σ" (U+03A3) is 1 display column
      assert.are.equal(1, str.strwidth("Σ"))
      -- "↑" (U+2191) is 1 display column
      assert.are.equal(1, str.strwidth("↑"))
      -- "ℹ" (U+2139) is 1 display column
      assert.are.equal(1, str.strwidth("ℹ"))
    end)
  end)

  describe("truncate", function()
    it("returns text unchanged when it fits", function()
      assert.are.equal("hello", str.truncate("hello", 10))
    end)

    it("returns text unchanged when exactly at limit", function()
      assert.are.equal("hello", str.truncate("hello", 5))
    end)

    it("truncates ASCII text with default suffix", function()
      local result = str.truncate("hello world", 8)
      -- "hello w" = 7 cols + "…" = 1 col = 8 cols
      assert.are.equal("hello w…", result)
    end)

    it("truncates with custom suffix", function()
      local result = str.truncate("hello world", 8, "..")
      -- "hello " = 6 cols + ".." = 2 cols = 8 cols
      assert.are.equal("hello ..", result)
    end)

    it("returns empty string when max_width is 0", function()
      assert.are.equal("", str.truncate("hello", 0))
    end)

    it("returns empty string when max_width is negative", function()
      assert.are.equal("", str.truncate("hello", -1))
    end)

    it("returns just the suffix when only suffix fits", function()
      -- max_width=1 with default "…" (1 col) → just the suffix
      assert.are.equal("…", str.truncate("hello world", 1))
    end)

    -- Multibyte safety
    it("does not split multibyte UTF-8 sequences", function()
      -- "café" = 4 chars, 4 display cols (é is 1 col, 2 bytes)
      local result = str.truncate("café mocha", 6)
      -- Should be "café …" (4+1+1=6) not a broken byte sequence
      assert.are.equal("café …", result)
      -- Verify valid UTF-8 by checking strwidth doesn't error
      assert.are.equal(6, str.strwidth(result))
    end)

    it("handles CJK double-width characters correctly", function()
      -- "你好世界" = 4 chars, 8 display cols (each char is 2 cols)
      local result = str.truncate("你好世界test", 7)
      -- "你好世" = 6 cols + "…" = 1 col = 7 cols
      assert.are.equal("你好世…", result)
      assert.are.equal(7, str.strwidth(result))
    end)

    it("skips double-width character that would exceed budget", function()
      -- "你好世界" = 8 cols. Truncate to 4 cols:
      -- "你" = 2 cols, budget left = 4-1(suffix)=3. "你" fits (2 ≤ 3).
      -- "你好" = 4 cols > 3. So only "你" fits.
      local result = str.truncate("你好世界", 4)
      assert.are.equal("你…", result)
      assert.are.equal(3, str.strwidth(result))
    end)

    it("handles mixed ASCII and CJK", function()
      -- "hi你好" = 2+2+2 = 6 cols. Truncate to 5:
      -- target = 5-1 = 4 cols for text. "hi你" = 4 cols. Fits.
      local result = str.truncate("hi你好world", 5)
      assert.are.equal("hi你…", result)
      assert.are.equal(5, str.strwidth(result))
    end)

    it("handles single-column multibyte chars (accented, symbols)", function()
      -- "αβγδ" = 4 chars, 4 display cols (Greek letters are 1 col each)
      local result = str.truncate("αβγδεζ", 5)
      assert.are.equal("αβγδ…", result)
      assert.are.equal(5, str.strwidth(result))
    end)

    it("handles truncation marker that is multi-byte", function()
      -- Custom suffix "→" is 3 bytes but 1 display column
      local result = str.truncate("hello world", 8, "→")
      assert.are.equal("hello w→", result)
    end)

    it("handles text that is all multibyte", function()
      -- "↑↓←→" = 4 chars, 4 cols (arrows are 1 col each)
      local result = str.truncate("↑↓←→", 3)
      assert.are.equal("↑↓…", result)
    end)
  end)

  describe("format_number", function()
    it("adds comma separators", function()
      assert.are.equal("20,449", str.format_number(20449))
      assert.are.equal("1,000,000", str.format_number(1000000))
      assert.are.equal("100", str.format_number(100))
      assert.are.equal("0", str.format_number(0))
    end)
  end)

  describe("format_tokens", function()
    it("returns raw number below 4000", function()
      assert.are.equal("500", str.format_tokens(500))
    end)

    it("comma-separates numbers between 1000 and 3999", function()
      assert.are.equal("1,500", str.format_tokens(1500))
      assert.are.equal("3,999", str.format_tokens(3999))
    end)

    it("uses K suffix at 4000 and above", function()
      assert.are.equal("4K", str.format_tokens(4000))
      assert.are.equal("15K", str.format_tokens(15000))
      assert.are.equal("4.5K", str.format_tokens(4500))
    end)

    it("uses M suffix at 1000000 and above", function()
      assert.are.equal("2M", str.format_tokens(2000000))
      assert.are.equal("1.5M", str.format_tokens(1500000))
    end)

    it("drops trailing .0 from K and M", function()
      assert.are.equal("4K", str.format_tokens(4000))
      assert.are.equal("2M", str.format_tokens(2000000))
    end)
  end)

  describe("format_money", function()
    it("formats zero without decimals", function()
      assert.are.equal("$0", str.format_money(0))
    end)

    it("formats integers without decimals", function()
      assert.are.equal("$15", str.format_money(15))
      assert.are.equal("$75", str.format_money(75))
      assert.are.equal("$3", str.format_money(3))
    end)

    it("formats values >= 1 with 2 decimal places", function()
      assert.are.equal("$1.50", str.format_money(1.5))
      assert.are.equal("$2.50", str.format_money(2.5))
    end)

    it("formats values in [0.01, 1) with 3 decimals, stripping trailing zeros", function()
      assert.are.equal("$0.375", str.format_money(0.375))
      assert.are.equal("$0.075", str.format_money(0.075))
      assert.are.equal("$0.02", str.format_money(0.02))
      assert.are.equal("$0.01", str.format_money(0.01))
      assert.are.equal("$0.20", str.format_money(0.20))
    end)

    it("formats sub-cent values with 4 decimals, stripping trailing zeros", function()
      assert.are.equal("$0.0034", str.format_money(0.0034))
      assert.are.equal("$0.005", str.format_money(0.005))
      assert.are.equal("$0.001", str.format_money(0.001))
    end)
  end)

  describe("format_pricing_suffix", function()
    it("formats integer per-MTok rates", function()
      assert.are.equal("$3 input / $15 output per MTok", str.format_pricing_suffix({ input = 3, output = 15 }))
    end)

    it("formats fractional per-MTok rates with two-decimal precision", function()
      assert.are.equal("$1.25 input / $5.50 output per MTok", str.format_pricing_suffix({ input = 1.25, output = 5.5 }))
    end)
  end)

  describe("format_estimate", function()
    local middot = "\xc2\xb7"

    it("includes cost and per-MTok suffix when pricing is provided", function()
      -- 5432 × 3 / 1e6 = 0.016296 → formatted as "$0.016"
      local expected = "5,432 input tokens "
        .. middot
        .. " $0.016 "
        .. middot
        .. " claude-sonnet-4-6 ($3 input / $15 output per MTok)"
      assert.are.equal(expected, str.format_estimate(5432, "claude-sonnet-4-6", { input = 3.0, output = 15.0 }))
    end)

    it("falls back to tokens-only output when pricing is nil", function()
      assert.are.equal(
        "1,234 input tokens " .. middot .. " unknown-model",
        str.format_estimate(1234, "unknown-model", nil)
      )
    end)
  end)

  describe("format_size", function()
    it("formats bytes", function()
      assert.are.equal("500B", str.format_size(500))
    end)

    it("formats kilobytes", function()
      assert.are.equal("1.5KB", str.format_size(1536))
    end)

    it("formats megabytes", function()
      assert.are.equal("2.0MB", str.format_size(2 * 1024 * 1024))
    end)

    it("formats gigabytes", function()
      assert.are.equal("1.0GB", str.format_size(1024 * 1024 * 1024))
    end)

    it("formats zero", function()
      assert.are.equal("0B", str.format_size(0))
    end)

    it("formats exactly 1KB", function()
      assert.are.equal("1.0KB", str.format_size(1024))
    end)
  end)

  describe("format_percent", function()
    it("appends percent sign", function()
      assert.are.equal("80%", str.format_percent(80))
      assert.are.equal("0%", str.format_percent(0))
      assert.are.equal("100%", str.format_percent(100))
    end)
  end)

  describe("format_elapsed", function()
    it("formats seconds only", function()
      assert.equals("0s", str.format_elapsed(0))
      assert.equals("1s", str.format_elapsed(1))
      assert.equals("59s", str.format_elapsed(59))
    end)

    it("formats minutes and seconds", function()
      assert.equals("1m 0s", str.format_elapsed(60))
      assert.equals("1m 3s", str.format_elapsed(63))
      assert.equals("12m 45s", str.format_elapsed(765))
    end)

    it("floors fractional seconds", function()
      assert.equals("3s", str.format_elapsed(3.7))
      assert.equals("1m 3s", str.format_elapsed(63.9))
    end)
  end)
end)

describe("utilities.variables", function()
  local variables

  before_each(function()
    package.loaded["flemma.utilities.variables"] = nil
    variables = require("flemma.utilities.variables")
  end)

  describe("expand", function()
    it("returns literal paths unchanged", function()
      assert.are.equal("/tmp", variables.expand("/tmp"))
    end)

    it("expands URN variables using registered resolvers", function()
      variables.register("urn:flemma:cwd", function()
        return "/home/user/project"
      end)
      assert.are.equal("/home/user/project", variables.expand("urn:flemma:cwd"))
    end)

    it("returns nil when URN resolver returns nil", function()
      variables.register("urn:flemma:buffer:path", function()
        return nil
      end)
      assert.is_nil(variables.expand("urn:flemma:buffer:path"))
    end)

    it("expands $VAR from environment", function()
      -- HOME is always set
      local home = os.getenv("HOME")
      assert.are.equal(home, variables.expand("$HOME"))
    end)

    it("returns nil for unset $VAR without default", function()
      assert.is_nil(variables.expand("$FLEMMA_TEST_NONEXISTENT_VAR_12345"))
    end)

    it("expands ${VAR:-default} using env value when set", function()
      local home = os.getenv("HOME")
      assert.are.equal(home, variables.expand("${HOME:-/fallback}"))
    end)

    it("expands ${VAR:-default} using default when unset", function()
      assert.are.equal("/fallback/path", variables.expand("${FLEMMA_TEST_NONEXISTENT_VAR_12345:-/fallback/path}"))
    end)

    it("expands ~ in default values", function()
      local home = os.getenv("HOME")
      assert.are.equal(home .. "/.cache", variables.expand("${FLEMMA_TEST_NONEXISTENT_VAR_12345:-~/.cache}"))
    end)

    it("expands ~ at start of literal paths", function()
      local home = os.getenv("HOME")
      assert.are.equal(home .. "/.config", variables.expand("~/.config"))
    end)

    it("does not expand ~ in the middle of a path", function()
      assert.are.equal("/home/~/weird", variables.expand("/home/~/weird"))
    end)

    it("errors on unregistered URN", function()
      assert.has_error(function()
        variables.expand("urn:flemma:nonexistent")
      end)
    end)

    it("passes context to URN resolvers", function()
      variables.register("urn:flemma:test", function(ctx)
        return ctx.some_value
      end)
      assert.are.equal("hello", variables.expand("urn:flemma:test", { some_value = "hello" }))
    end)
  end)

  describe("expand_list", function()
    it("expands all entries and drops nils", function()
      variables.register("urn:flemma:cwd", function()
        return "/project"
      end)
      variables.register("urn:flemma:buffer:path", function()
        return nil -- unnamed buffer
      end)
      local result = variables.expand_list({
        "urn:flemma:cwd",
        "urn:flemma:buffer:path",
        "/tmp",
      })
      assert.are.same({ "/project", "/tmp" }, result)
    end)
  end)

  describe("expand_inline", function()
    it("terminates on mutually-referential inline resolvers", function()
      variables.register_inline("SPEC_RING_A", function()
        return "$SPEC_RING_B"
      end)
      variables.register_inline("SPEC_RING_B", function()
        return "$SPEC_RING_A"
      end)
      local result = variables.expand_inline("x $SPEC_RING_A y")
      assert.is_string(result)
    end)

    it("expands ${VAR:-default} within a larger string", function()
      local original = os.getenv("FLEMMA_TEST_UNSET_VAR_1")
      assert.is_nil(original)
      local result = variables.expand_inline("${FLEMMA_TEST_UNSET_VAR_1:-/fallback}/sub/path")
      assert.equals("/fallback/sub/path", result)
    end)

    it("expands ${VAR:-default} using env value when set", function()
      vim.env.FLEMMA_TEST_INLINE_1 = "/custom"
      local result = variables.expand_inline("${FLEMMA_TEST_INLINE_1:-/fallback}/sub/path")
      vim.env.FLEMMA_TEST_INLINE_1 = nil
      assert.equals("/custom/sub/path", result)
    end)

    it("expands bare $VAR inline", function()
      vim.env.FLEMMA_TEST_INLINE_2 = "resolved"
      local result = variables.expand_inline("prefix/$FLEMMA_TEST_INLINE_2/suffix")
      vim.env.FLEMMA_TEST_INLINE_2 = nil
      assert.equals("prefix/resolved/suffix", result)
    end)

    it("expands tilde in defaults", function()
      local home = os.getenv("HOME") or ""
      local result = variables.expand_inline("${FLEMMA_TEST_UNSET_VAR_2:-~/.local/share}/flemma")
      assert.equals(home .. "/.local/share/flemma", result)
    end)

    it("leaves {{...}} template expressions untouched", function()
      local result = variables.expand_inline("${FLEMMA_TEST_UNSET_VAR_3:-/tmp}/flemma_{{ source }}_{{ id }}.txt")
      assert.equals("/tmp/flemma_{{ source }}_{{ id }}.txt", result)
    end)

    it("handles multiple expansions in one string", function()
      vim.env.FLEMMA_TEST_INLINE_A = "aaa"
      vim.env.FLEMMA_TEST_INLINE_B = "bbb"
      local result = variables.expand_inline("$FLEMMA_TEST_INLINE_A/${FLEMMA_TEST_INLINE_B:-fallback}")
      vim.env.FLEMMA_TEST_INLINE_A = nil
      vim.env.FLEMMA_TEST_INLINE_B = nil
      assert.equals("aaa/bbb", result)
    end)

    it("returns string unchanged when no patterns match", function()
      local result = variables.expand_inline("/plain/path/no/vars")
      assert.equals("/plain/path/no/vars", result)
    end)

    it("replaces bare $VAR with empty string when unset", function()
      local result = variables.expand_inline("prefix/$FLEMMA_TEST_UNSET_VAR_4/suffix")
      assert.equals("prefix//suffix", result)
    end)

    it("expands leading tilde", function()
      local home = os.getenv("HOME") or ""
      local result = variables.expand_inline("~/documents/file.txt")
      assert.equals(home .. "/documents/file.txt", result)
    end)

    it("expands $VAR inside ${VAR:-default} fallback", function()
      local home = os.getenv("HOME")
      local result = variables.expand_inline("${FLEMMA_TEST_NONEXISTENT_12345:-$HOME/.flemma}/store")
      assert.equals(home .. "/.flemma/store", result)
    end)

    it("expands nested ${VAR:-default} in fallback", function()
      local result =
        variables.expand_inline("${FLEMMA_TEST_NONEXISTENT_12345:-${FLEMMA_TEST_ALSO_NONEXISTENT:-/final}}/x")
      assert.equals("/final/x", result)
    end)
  end)

  describe("register_inline", function()
    it("resolves inline-registered variables before os.getenv", function()
      variables.register_inline("FLEMMA_TEST_INLINE_VAR", function()
        return "/resolved/path"
      end)
      local result = variables.expand_inline("prefix/$FLEMMA_TEST_INLINE_VAR/suffix")
      assert.equals("prefix//resolved/path/suffix", result)
    end)

    it("falls back to default when inline resolver returns nil", function()
      variables.register_inline("FLEMMA_TEST_NIL_VAR", function()
        return nil
      end)
      local result = variables.expand_inline("${FLEMMA_TEST_NIL_VAR:-/fallback}/x")
      assert.equals("/fallback/x", result)
    end)

    it("is cleared by clear()", function()
      variables.register_inline("FLEMMA_TEST_CLEARED", function()
        return "/value"
      end)
      variables.clear()
      local result = variables.expand_inline("$FLEMMA_TEST_CLEARED")
      assert.equals("", result)
    end)
  end)

  describe("deduplicate_by_prefix", function()
    it("removes paths subsumed by a parent", function()
      local result = variables.deduplicate_by_prefix({
        "/tmp",
        "/tmp/foo/bar",
        "/home/user",
        "/home/user/project",
      })
      assert.are.same({ "/home/user", "/tmp" }, result)
    end)

    it("keeps distinct paths", function()
      local result = variables.deduplicate_by_prefix({
        "/tmp",
        "/home/user",
        "/data/project",
      })
      assert.are.same({ "/data/project", "/home/user", "/tmp" }, result)
    end)

    it("handles single path", function()
      local result = variables.deduplicate_by_prefix({ "/tmp" })
      assert.are.same({ "/tmp" }, result)
    end)

    it("handles empty list", function()
      local result = variables.deduplicate_by_prefix({})
      assert.are.same({}, result)
    end)

    it("does not treat /tmp as parent of /tmpfs", function()
      local result = variables.deduplicate_by_prefix({ "/tmp", "/tmpfs" })
      assert.are.same({ "/tmp", "/tmpfs" }, result)
    end)
  end)
end)
