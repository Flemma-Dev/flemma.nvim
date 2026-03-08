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
