describe("flemma.frontmatter", function()
  local frontmatter = require("flemma.frontmatter")
  local context_util = require("flemma.context")

  describe("parse", function()
    it("should parse Lua frontmatter", function()
      local lines = {
        "```lua",
        "x = 5",
        "```",
        "@You: test",
      }
      local language, code, content = frontmatter.parse(lines)
      assert.are.equal("lua", language)
      assert.are.equal("x = 5", code)
      assert.are.same({ "@You: test" }, content)
    end)

    it("should parse JSON frontmatter", function()
      local lines = {
        "```json",
        '{"name": "Alice", "age": 30}',
        "```",
        "@You: test",
      }
      local language, code, content = frontmatter.parse(lines)
      assert.are.equal("json", language)
      assert.are.equal('{"name": "Alice", "age": 30}', code)
      assert.are.same({ "@You: test" }, content)
    end)

    it("should return nil for no frontmatter", function()
      local lines = {
        "@You: test",
      }
      local language, code, content = frontmatter.parse(lines)
      assert.is_nil(language)
      assert.is_nil(code)
      assert.are.same(lines, content)
    end)

    it("should return nil for unclosed frontmatter", function()
      local lines = {
        "```lua",
        "x = 5",
        "@You: test",
      }
      local language, code, content = frontmatter.parse(lines)
      assert.is_nil(language)
      assert.is_nil(code)
      assert.are.same(lines, content)
    end)
  end)

  describe("execute with Lua", function()
    it("should execute Lua frontmatter and add variables to context", function()
      local code = "my_var = 'hello'\nmy_num = 42"
      local context = context_util.from_file("test.chat")
      local result = frontmatter.execute("lua", code, context)

      assert.are.equal("hello", result.my_var)
      assert.are.equal(42, result.my_num)
      assert.are.equal("test.chat", result.__filename)
    end)

    it("should support Lua functions in frontmatter", function()
      local code = "greet = function(name) return 'Hello, ' .. name end"
      local context = context_util.from_file("test.chat")
      local result = frontmatter.execute("lua", code, context)

      assert.is_function(result.greet)
      assert.are.equal("Hello, World", result.greet("World"))
    end)
  end)

  describe("execute with JSON", function()
    it("should parse JSON frontmatter and add variables to context", function()
      local code = '{"name": "Alice", "age": 30, "active": true}'
      local context = context_util.from_file("test.chat")
      local result = frontmatter.execute("json", code, context)

      assert.are.equal("Alice", result.name)
      assert.are.equal(30, result.age)
      assert.is_true(result.active)
      assert.are.equal("test.chat", result.__filename)
    end)

    it("should handle nested JSON objects", function()
      local code = '{"user": {"name": "Bob", "role": "admin"}, "count": 5}'
      local context = context_util.from_file("test.chat")
      local result = frontmatter.execute("json", code, context)

      assert.is_table(result.user)
      assert.are.equal("Bob", result.user.name)
      assert.are.equal("admin", result.user.role)
      assert.are.equal(5, result.count)
    end)

    it("should handle JSON arrays", function()
      local code = '{"tags": ["important", "urgent"], "version": 2}'
      local context = context_util.from_file("test.chat")
      local result = frontmatter.execute("json", code, context)

      assert.is_table(result.tags)
      assert.are.equal(2, #result.tags)
      assert.are.equal("important", result.tags[1])
      assert.are.equal("urgent", result.tags[2])
      assert.are.equal(2, result.version)
    end)

    it("should error on invalid JSON", function()
      local code = '{"invalid": json}'
      local context = context_util.from_file("test.chat")

      local ok, err = pcall(frontmatter.execute, "json", code, context)
      assert.is_false(ok)
      assert.is_truthy(err:match("JSON parse error"))
    end)

    it("should error on non-object JSON", function()
      local code = '"just a string"'
      local context = context_util.from_file("test.chat")

      local ok, err = pcall(frontmatter.execute, "json", code, context)
      assert.is_false(ok)
      assert.is_truthy(err:match("JSON frontmatter must be an object"))
    end)
  end)

  describe("execute with unsupported language", function()
    it("should error for unsupported language", function()
      local code = "some yaml content"
      local context = context_util.from_file("test.chat")

      local ok, err = pcall(frontmatter.execute, "yaml", code, context)
      assert.is_false(ok)
      assert.is_truthy(err:match("Unsupported frontmatter language 'yaml'"))
    end)
  end)

  describe("integration with templating", function()
    it("should use JSON frontmatter variables in Lua expressions", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      local lines = {
        "```json",
        '{"greeting": "Hello", "name": "World"}',
        "```",
        "@You: {{ greeting .. ', ' .. name }}!",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      local context = require("flemma.context").from_file("test.chat")
      local messages, fm_code, fm_context = require("flemma.buffers").parse_buffer(bufnr, context)

      assert.are.equal(1, #messages)
      assert.are.equal("You", messages[1].type)

      -- Process expressions using the frontmatter context
      local eval = require("flemma.eval")
      local processed_content, errors = eval.interpolate(messages[1].content, fm_context)

      assert.are.equal("Hello, World!", processed_content)
      assert.are.equal(0, #errors)
    end)
  end)
end)
