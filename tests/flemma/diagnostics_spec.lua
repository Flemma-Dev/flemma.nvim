describe("flemma.diagnostics", function()
  local diagnostics

  before_each(function()
    package.loaded["flemma.diagnostics"] = nil
    diagnostics = require("flemma.diagnostics")
  end)

  describe("pretty_print_raw", function()
    it("formats a simple object with indentation", function()
      local input = '{"a":1,"b":2}'
      local result = diagnostics.pretty_print_raw(input)
      assert.are.equal('{\n  "a": 1,\n  "b": 2\n}', result)
    end)

    it("preserves key ordering (does not sort)", function()
      local input = '{"z":1,"a":2}'
      local result = diagnostics.pretty_print_raw(input)
      assert.are.equal('{\n  "z": 1,\n  "a": 2\n}', result)
    end)

    it("handles nested objects", function()
      local input = '{"outer":{"inner":true}}'
      local result = diagnostics.pretty_print_raw(input)
      local expected = '{\n  "outer": {\n    "inner": true\n  }\n}'
      assert.are.equal(expected, result)
    end)

    it("handles arrays", function()
      local input = '["a","b","c"]'
      local result = diagnostics.pretty_print_raw(input)
      assert.are.equal('[\n  "a",\n  "b",\n  "c"\n]', result)
    end)

    it("handles strings with braces and brackets", function()
      local input = '{"code":"use { and } in code"}'
      local result = diagnostics.pretty_print_raw(input)
      assert.are.equal('{\n  "code": "use { and } in code"\n}', result)
    end)

    it("handles strings with escaped quotes", function()
      local input = '{"msg":"say \\"hello\\""}'
      local result = diagnostics.pretty_print_raw(input)
      assert.are.equal('{\n  "msg": "say \\"hello\\""\n}', result)
    end)

    it("handles strings with escaped backslashes", function()
      local input = '{"path":"C:\\\\Users\\\\file"}'
      local result = diagnostics.pretty_print_raw(input)
      assert.are.equal('{\n  "path": "C:\\\\Users\\\\file"\n}', result)
    end)

    it("handles empty objects and arrays", function()
      local input = '{"obj":{},"arr":[]}'
      local result = diagnostics.pretty_print_raw(input)
      assert.are.equal('{\n  "obj": {},\n  "arr": []\n}', result)
    end)

    it("handles nested arrays of objects", function()
      local input = '[{"a":1},{"b":2}]'
      local result = diagnostics.pretty_print_raw(input)
      local expected = '[\n  {\n    "a": 1\n  },\n  {\n    "b": 2\n  }\n]'
      assert.are.equal(expected, result)
    end)

    it("handles string values with colons", function()
      local input = '{"url":"https://example.com:8080"}'
      local result = diagnostics.pretty_print_raw(input)
      assert.are.equal('{\n  "url": "https://example.com:8080"\n}', result)
    end)

    it("handles null, true, false literals", function()
      local input = '{"a":null,"b":true,"c":false}'
      local result = diagnostics.pretty_print_raw(input)
      assert.are.equal('{\n  "a": null,\n  "b": true,\n  "c": false\n}', result)
    end)

    it("handles numeric values including negatives and floats", function()
      local input = '{"int":42,"neg":-1,"float":3.14}'
      local result = diagnostics.pretty_print_raw(input)
      assert.are.equal('{\n  "int": 42,\n  "neg": -1,\n  "float": 3.14\n}', result)
    end)

    it("handles strings with unicode escapes", function()
      local input = '{"emoji":"\\u2603"}'
      local result = diagnostics.pretty_print_raw(input)
      assert.are.equal('{\n  "emoji": "\\u2603"\n}', result)
    end)

    it("returns empty string for empty input", function()
      assert.are.equal("", diagnostics.pretty_print_raw(""))
    end)
  end)

  describe("pretty_print_normalized", function()
    it("sorts keys alphabetically", function()
      local input = '{"z":1,"a":2,"m":3}'
      local result = diagnostics.pretty_print_normalized(input)
      assert.are.equal('{\n  "a": 2,\n  "m": 3,\n  "z": 1\n}', result)
    end)

    it("sorts keys at all nesting levels", function()
      local input = '{"b":{"z":1,"a":2},"a":true}'
      local result = diagnostics.pretty_print_normalized(input)
      local expected = '{\n  "a": true,\n  "b": {\n    "a": 2,\n    "z": 1\n  }\n}'
      assert.are.equal(expected, result)
    end)

    it("preserves array order (no sorting)", function()
      local input = '{"items":["c","a","b"]}'
      local result = diagnostics.pretty_print_normalized(input)
      local expected = '{\n  "items": [\n    "c",\n    "a",\n    "b"\n  ]\n}'
      assert.are.equal(expected, result)
    end)

    it("handles null values", function()
      local input = '{"b":null,"a":1}'
      local result = diagnostics.pretty_print_normalized(input)
      -- null becomes nil in Lua, so the key is dropped
      assert.are.equal('{\n  "a": 1\n}', result)
    end)

    it("returns empty string for empty input", function()
      assert.are.equal("", diagnostics.pretty_print_normalized(""))
    end)
  end)

  describe("find_prefix_divergence", function()
    it("returns nil when strings are identical", function()
      local result = diagnostics.find_prefix_divergence("abc", "abc")
      assert.is_nil(result)
    end)

    it("returns nil when new string extends old (append-only)", function()
      -- Raw prefix must literally match; current is previous + more bytes
      local result = diagnostics.find_prefix_divergence("abc", "abcdef")
      assert.is_nil(result)
    end)

    it("finds divergence byte when prefix changes", function()
      local result =
        diagnostics.find_prefix_divergence('{"system":"Hello","messages":[]}', '{"system":"World","messages":[]}')
      assert.is_not_nil(result)
      -- byte 12 is 'H' vs 'W'
      assert.are.equal(12, result.byte_offset)
    end)

    it("detects divergence at start", function()
      local result = diagnostics.find_prefix_divergence('{"model":"a"}', '{"model":"b"}')
      assert.is_not_nil(result)
      -- byte 11 is 'a' vs 'b'
      assert.are.equal(11, result.byte_offset)
    end)

    it("returns nil when previous is nil (first request)", function()
      local result = diagnostics.find_prefix_divergence(nil, '{"a":1}')
      assert.is_nil(result)
    end)

    it("detects when new request is shorter than old", function()
      local result = diagnostics.find_prefix_divergence(
        '{"messages":[{"role":"user"},{"role":"assistant"}]}',
        '{"messages":[{"role":"user"}]}'
      )
      assert.is_not_nil(result)
      -- byte 29 in old is ']', in new is ','  (the array closing bracket shifts)
      assert.are.equal(29, result.byte_offset)
    end)
  end)

  describe("analyze_structural_changes", function()
    it("returns empty list when requests are identical", function()
      local a = '{"model":"gpt-4","system":"hello","messages":[]}'
      local b = '{"model":"gpt-4","system":"hello","messages":[]}'
      local changes = diagnostics.analyze_structural_changes(a, b)
      assert.are.equal(0, #changes)
    end)

    it("detects system prompt change", function()
      local a = '{"system":"You are helpful"}'
      local b = '{"system":"You are creative"}'
      local changes = diagnostics.analyze_structural_changes(a, b)
      assert.is_true(#changes > 0)
      local found = false
      for _, c in ipairs(changes) do
        if c:match("system") then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)

    it("detects model change", function()
      local a = '{"model":"gpt-4"}'
      local b = '{"model":"gpt-4o"}'
      local changes = diagnostics.analyze_structural_changes(a, b)
      assert.is_true(#changes > 0)
      local found = false
      for _, c in ipairs(changes) do
        if c:match("model") then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)

    it("detects parameter changes", function()
      local a = '{"temperature":0.7}'
      local b = '{"temperature":0.5}'
      local changes = diagnostics.analyze_structural_changes(a, b)
      assert.is_true(#changes > 0)
    end)

    it("detects tool list changes", function()
      local a = '{"tools":[{"name":"bash"}]}'
      local b = '{"tools":[{"name":"bash"},{"name":"read"}]}'
      local changes = diagnostics.analyze_structural_changes(a, b)
      assert.is_true(#changes > 0)
    end)

    it("reports append-only messages as non-breaking", function()
      local a = '{"messages":[{"role":"user","content":"hi"}]}'
      local b = '{"messages":[{"role":"user","content":"hi"},{"role":"assistant","content":"hello"}]}'
      local changes = diagnostics.analyze_structural_changes(a, b)
      -- Appending messages preserves the prefix — should report as clean or informational
      local breaking = false
      for _, c in ipairs(changes) do
        if not c:match("appended") then
          breaking = true
        end
      end
      assert.is_false(breaking)
    end)

    it("detects modified existing message", function()
      local a = '{"messages":[{"role":"user","content":"hi"}]}'
      local b = '{"messages":[{"role":"user","content":"hello"}]}'
      local changes = diagnostics.analyze_structural_changes(a, b)
      assert.is_true(#changes > 0)
      local found = false
      for _, c in ipairs(changes) do
        if c:match("messages%[1%]") then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)

    it("returns nil for first request", function()
      local changes = diagnostics.analyze_structural_changes(nil, '{"a":1}')
      assert.is_nil(changes)
    end)
  end)

  describe("map_byte_to_path", function()
    it("maps a byte offset inside a top-level key", function()
      local input = '{"model":"gpt-4","system":"hello"}'
      -- byte 10 is inside the value of "model"
      local path = diagnostics.map_byte_to_path(input, 10)
      assert.are.equal("model", path)
    end)

    it("maps a byte offset inside a nested key", function()
      local input = '{"messages":[{"role":"user"}]}'
      -- byte 22 is inside the value of messages[0].role
      local path = diagnostics.map_byte_to_path(input, 22)
      assert.is_truthy(path:match("messages"))
    end)

    it("returns root for byte 1", function()
      local path = diagnostics.map_byte_to_path('{"a":1}', 1)
      assert.are.equal("$", path)
    end)
  end)

  describe("record_and_compare", function()
    it("does nothing on first request", function()
      -- Clear state before diagnostics so the fresh state module is captured
      package.loaded["flemma.state"] = nil
      package.loaded["flemma.diagnostics"] = nil
      local fresh_state = require("flemma.state")
      diagnostics = require("flemma.diagnostics")
      local bufnr = vim.api.nvim_create_buf(false, true)

      diagnostics.record_and_compare(bufnr, '{"model":"gpt-4","messages":[]}')

      local bs = fresh_state.get_buffer_state(bufnr)
      assert.are.equal('{"model":"gpt-4","messages":[]}', bs.diagnostics_current_request)
      assert.is_nil(bs.diagnostics_previous_request)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("rotates previous/current on second request", function()
      package.loaded["flemma.state"] = nil
      package.loaded["flemma.diagnostics"] = nil
      local fresh_state = require("flemma.state")
      diagnostics = require("flemma.diagnostics")
      local bufnr = vim.api.nvim_create_buf(false, true)

      diagnostics.record_and_compare(bufnr, '{"first":true}')
      diagnostics.record_and_compare(bufnr, '{"second":true}')

      local bs = fresh_state.get_buffer_state(bufnr)
      assert.are.equal('{"first":true}', bs.diagnostics_previous_request)
      assert.are.equal('{"second":true}', bs.diagnostics_current_request)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("open_diff", function()
    it("warns when no request data is available", function()
      package.loaded["flemma.state"] = nil
      package.loaded["flemma.diagnostics"] = nil
      require("flemma.state")
      diagnostics = require("flemma.diagnostics")
      local bufnr = vim.api.nvim_create_buf(false, true)

      -- Should not error, just notify
      diagnostics.open_diff(bufnr, false)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
