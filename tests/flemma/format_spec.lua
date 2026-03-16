describe("format.expand", function()
  local format

  before_each(function()
    package.loaded["flemma.utilities.format"] = nil
    format = require("flemma.utilities.format")
  end)

  describe("variable expansion", function()
    it("expands a simple variable", function()
      assert.are.equal("hello", format.expand("#{greeting}", { greeting = "hello" }))
    end)

    it("returns empty string for unknown variables", function()
      assert.are.equal("", format.expand("#{unknown}", {}))
    end)

    it("leaves plain text unchanged", function()
      assert.are.equal("plain text", format.expand("plain text", {}))
    end)

    it("expands multiple variables", function()
      local vars = { provider = "anthropic", model = "claude-sonnet-4-5" }
      assert.are.equal("anthropic:claude-sonnet-4-5", format.expand("#{provider}:#{model}", vars))
    end)

    it("handles variables adjacent to text", function()
      assert.are.equal("[hello]", format.expand("[#{x}]", { x = "hello" }))
    end)
  end)

  describe("comma escaping", function()
    it("renders escaped commas as literal commas", function()
      assert.are.equal("a,b", format.expand("a#,b", {}))
    end)
  end)

  describe("ternary conditionals", function()
    it("selects true branch when value is truthy", function()
      assert.are.equal("yes", format.expand("#{?#{x},yes,no}", { x = "active" }))
    end)

    it("selects false branch when value is empty", function()
      assert.are.equal("no", format.expand("#{?#{x},yes,no}", { x = "" }))
    end)

    it("selects false branch when value is 0", function()
      assert.are.equal("no", format.expand("#{?#{x},yes,no}", { x = "0" }))
    end)

    it("handles empty true branch", function()
      assert.are.equal("", format.expand("#{?#{x},,fallback}", { x = "active" }))
    end)

    it("handles empty false branch", function()
      assert.are.equal("shown", format.expand("#{?#{x},shown,}", { x = "active" }))
    end)

    it("handles both branches empty", function()
      assert.are.equal("", format.expand("#{?#{x},,}", { x = "active" }))
    end)

    it("expands variables inside branches", function()
      local vars = { flag = "1", model = "o3" }
      assert.are.equal("model: o3", format.expand("#{?#{flag},model: #{model},none}", vars))
    end)
  end)

  describe("string comparisons", function()
    it("returns 1 for equal strings", function()
      assert.are.equal("1", format.expand("#{==:#{x},hello}", { x = "hello" }))
    end)

    it("returns 0 for unequal strings", function()
      assert.are.equal("0", format.expand("#{==:#{x},hello}", { x = "world" }))
    end)

    it("returns 1 for not-equal when different", function()
      assert.are.equal("1", format.expand("#{!=:#{x},hello}", { x = "world" }))
    end)

    it("returns 0 for not-equal when same", function()
      assert.are.equal("0", format.expand("#{!=:#{x},hello}", { x = "hello" }))
    end)
  end)

  describe("boolean operators", function()
    it("&& returns 1 when both truthy", function()
      assert.are.equal("1", format.expand("#{&&:#{a},#{b}}", { a = "1", b = "1" }))
    end)

    it("&& returns 0 when one is empty", function()
      assert.are.equal("0", format.expand("#{&&:#{a},#{b}}", { a = "1", b = "" }))
    end)

    it("|| returns 1 when one is truthy", function()
      assert.are.equal("1", format.expand("#{||:#{a},#{b}}", { a = "", b = "1" }))
    end)

    it("|| returns 0 when both empty", function()
      assert.are.equal("0", format.expand("#{||:#{a},#{b}}", { a = "", b = "" }))
    end)
  end)

  describe("nesting", function()
    it("handles nested conditionals", function()
      local vars = { provider = "anthropic", thinking = "high" }
      local fmt = "#{?#{==:#{provider},anthropic},#{?#{thinking},A (#{thinking}),A},other}"
      assert.are.equal("A (high)", format.expand(fmt, vars))
    end)

    it("handles nested conditional with empty inner", function()
      local vars = { provider = "anthropic", thinking = "" }
      local fmt = "#{?#{==:#{provider},anthropic},#{?#{thinking},A (#{thinking}),A},other}"
      assert.are.equal("A", format.expand(fmt, vars))
    end)

    it("handles deeply nested expressions", function()
      local vars = { a = "1", b = "1", value = "deep" }
      local fmt = "#{?#{&&:#{a},#{b}},#{value},}"
      assert.are.equal("deep", format.expand(fmt, vars))
    end)
  end)

  describe("lazy evaluation", function()
    it("only resolves referenced variables", function()
      local call_count = 0
      local vars = setmetatable({}, {
        __index = function(self, key)
          call_count = call_count + 1
          local values = { model = "o3", thinking = "high", provider = "openai" }
          local value = values[key] or ""
          rawset(self, key, value)
          return value
        end,
      })

      format.expand("#{model}", vars)
      assert.are.equal(1, call_count, "should only resolve 'model'")
    end)

    it("caches resolved values for repeated access", function()
      local call_count = 0
      local vars = setmetatable({}, {
        __index = function(self, key)
          call_count = call_count + 1
          local value = key == "thinking" and "high" or ""
          rawset(self, key, value)
          return value
        end,
      })

      format.expand("#{?#{thinking}, (#{thinking}),}", vars)
      assert.are.equal(1, call_count, "should resolve 'thinking' only once")
    end)
  end)

  describe("default lualine format", function()
    local default_fmt = "#{model}#{?#{thinking}, (#{thinking}),}"

    it("shows model with thinking level", function()
      local vars = { model = "claude-sonnet-4-5", thinking = "high" }
      assert.are.equal("claude-sonnet-4-5 (high)", format.expand(default_fmt, vars))
    end)

    it("shows model only when thinking is off", function()
      local vars = { model = "claude-sonnet-4-5", thinking = "" }
      assert.are.equal("claude-sonnet-4-5", format.expand(default_fmt, vars))
    end)

    it("returns empty when no model", function()
      local vars = { model = "", thinking = "" }
      assert.are.equal("", format.expand(default_fmt, vars))
    end)
  end)

  describe("edge cases", function()
    it("handles unmatched #{ gracefully", function()
      assert.are.equal("#{broken", format.expand("#{broken", {}))
    end)

    it("handles empty format string", function()
      assert.are.equal("", format.expand("", {}))
    end)

    it("handles format with only literals", function()
      assert.are.equal("hello world", format.expand("hello world", {}))
    end)

    it("handles escaped comma inside conditional branch", function()
      assert.are.equal("a,b", format.expand("#{?#{x},a#,b,c}", { x = "1" }))
    end)

    it("handles # followed by non-special character", function()
      assert.are.equal("test#value", format.expand("test#value", {}))
    end)
  end)
end)
