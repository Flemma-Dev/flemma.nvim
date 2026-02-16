describe("flemma.codeblock", function()
  local parser = require("flemma.parser")
  local processor = require("flemma.processor")
  local pipeline = require("flemma.pipeline")
  local ctx = require("flemma.context")

  describe("parse via AST", function()
    it("should parse Lua frontmatter", function()
      local lines = {
        "```lua",
        "x = 5",
        "```",
        "@You: test",
      }
      local doc = parser.parse_lines(lines)
      assert.is_not_nil(doc.frontmatter)
      assert.are.equal("lua", doc.frontmatter.language)
      assert.are.equal("x = 5", doc.frontmatter.code)
    end)

    it("should parse JSON frontmatter", function()
      local lines = {
        "```json",
        '{"name": "Alice", "age": 30}',
        "```",
        "@You: test",
      }
      local doc = parser.parse_lines(lines)
      assert.is_not_nil(doc.frontmatter)
      assert.are.equal("json", doc.frontmatter.language)
      assert.are.equal('{"name": "Alice", "age": 30}', doc.frontmatter.code)
    end)

    it("should return nil frontmatter when none present", function()
      local lines = {
        "@You: test",
      }
      local doc = parser.parse_lines(lines)
      assert.is_nil(doc.frontmatter)
    end)

    it("should return nil frontmatter for unclosed fence", function()
      local lines = {
        "```lua",
        "x = 5",
        "@You: test",
      }
      local doc = parser.parse_lines(lines)
      assert.is_nil(doc.frontmatter)
    end)
  end)

  describe("execute via processor with Lua", function()
    it("should execute Lua frontmatter and make variables available to expressions", function()
      local lines = {
        "```lua",
        "my_var = 'hello'",
        "my_num = 42",
        "```",
        "@You: Value is {{ my_var }} and number is {{ my_num }}",
      }
      local base_context = ctx.from_file("test.chat")
      local prompt = pipeline.run(parser.parse_lines(lines), base_context)

      -- Check that expressions were evaluated using frontmatter variables
      assert.are.equal(1, #prompt.history)
      local user_msg = prompt.history[1]
      local all_text = {}
      for _, p in ipairs(user_msg.parts) do
        if p.kind == "text" then
          table.insert(all_text, p.text or "")
        end
      end
      local content = table.concat(all_text, "")
      assert.are.equal("Value is hello and number is 42", content)
    end)

    it("should support Lua functions in frontmatter", function()
      local lines = {
        "```lua",
        "greet = function(name) return 'Hello, ' .. name end",
        "```",
        "@You: {{ greet('World') }}",
      }
      local base_context = ctx.from_file("test.chat")
      local prompt = pipeline.run(parser.parse_lines(lines), base_context)

      -- Check that function was called successfully
      assert.are.equal(1, #prompt.history)
      local user_msg = prompt.history[1]
      local all_text = {}
      for _, p in ipairs(user_msg.parts) do
        if p.kind == "text" then
          table.insert(all_text, p.text or "")
        end
      end
      local content = table.concat(all_text, "")
      assert.are.equal("Hello, World", content)
    end)
  end)

  describe("execute via processor with JSON", function()
    it("should parse JSON frontmatter and make variables available to expressions", function()
      local lines = {
        "```json",
        '{"name": "Alice", "age": 30}',
        "```",
        "@You: Name is {{ name }} and age is {{ age }}",
      }
      local base_context = ctx.from_file("test.chat")
      local prompt = pipeline.run(parser.parse_lines(lines), base_context)

      -- Check that expressions were evaluated using frontmatter variables
      assert.are.equal(1, #prompt.history)
      local user_msg = prompt.history[1]
      local all_text = {}
      for _, p in ipairs(user_msg.parts) do
        if p.kind == "text" then
          table.insert(all_text, p.text or "")
        end
      end
      local content = table.concat(all_text, "")
      assert.are.equal("Name is Alice and age is 30", content)
    end)

    it("should handle nested JSON objects", function()
      local lines = {
        "```json",
        '{"user": {"name": "Bob", "role": "admin"}}',
        "```",
        "@You: User {{ user.name }} has role {{ user.role }}",
      }
      local base_context = ctx.from_file("test.chat")
      local prompt = pipeline.run(parser.parse_lines(lines), base_context)

      -- Check nested access works
      assert.are.equal(1, #prompt.history)
      local user_msg = prompt.history[1]
      local all_text = {}
      for _, p in ipairs(user_msg.parts) do
        if p.kind == "text" then
          table.insert(all_text, p.text or "")
        end
      end
      local content = table.concat(all_text, "")
      assert.are.equal("User Bob has role admin", content)
    end)

    it("should handle JSON arrays", function()
      local lines = {
        "```json",
        '{"tags": ["important", "urgent"]}',
        "```",
        "@You: First tag is {{ tags[1] }} and second is {{ tags[2] }}",
      }
      local base_context = ctx.from_file("test.chat")
      local prompt = pipeline.run(parser.parse_lines(lines), base_context)

      -- Check array access works
      assert.are.equal(1, #prompt.history)
      local user_msg = prompt.history[1]
      local all_text = {}
      for _, p in ipairs(user_msg.parts) do
        if p.kind == "text" then
          table.insert(all_text, p.text or "")
        end
      end
      local content = table.concat(all_text, "")
      assert.are.equal("First tag is important and second is urgent", content)
    end)

    it("should report error on invalid JSON", function()
      local lines = {
        "```json",
        '{"invalid": json}',
        "```",
      }
      local doc = parser.parse_lines(lines)
      local context = ctx.from_file("test.chat")
      local evaluated = processor.evaluate(doc, context)

      -- Should have error diagnostic
      assert.is_true(#evaluated.diagnostics > 0)
      local has_json_error = false
      for _, diag in ipairs(evaluated.diagnostics) do
        if diag.type == "frontmatter" and diag.severity == "error" then
          has_json_error = true
          assert.is_truthy(diag.error:match("JSON"))
        end
      end
      assert.is_true(has_json_error)
    end)

    it("should decode JSON null values as nil, not vim.NIL", function()
      local json_parser = require("flemma.codeblock.parsers.json")
      local result = json_parser.parse('{"offset": null, "limit": null, "name": "test"}')
      assert.is_nil(result.offset)
      assert.is_nil(result.limit)
      assert.are.equal("test", result.name)
    end)

    it("should decode JSON null in arrays as nil", function()
      local json_parser = require("flemma.codeblock.parsers.json")
      local result = json_parser.parse('{"items": [1, null, 3]}')
      assert.are.equal(1, result.items[1])
      assert.is_nil(result.items[2])
      assert.are.equal(3, result.items[3])
    end)

    it("should report error on non-object JSON", function()
      local lines = {
        "```json",
        '"just a string"',
        "```",
      }
      local doc = parser.parse_lines(lines)
      local context = ctx.from_file("test.chat")
      local evaluated = processor.evaluate(doc, context)

      -- Should have warning diagnostic (parse succeeded but result is not an object)
      assert.is_true(#evaluated.diagnostics > 0)
      local has_object_warning = false
      for _, diag in ipairs(evaluated.diagnostics) do
        if diag.type == "frontmatter" and diag.severity == "warning" then
          has_object_warning = true
          assert.is_truthy(diag.error:match("object"))
        end
      end
      assert.is_true(has_object_warning)
    end)
  end)

  describe("execute with unsupported language", function()
    it("should report error for unsupported language", function()
      local lines = {
        "```yaml",
        "some: yaml",
        "```",
      }
      local doc = parser.parse_lines(lines)
      local context = ctx.from_file("test.chat")
      local evaluated = processor.evaluate(doc, context)

      -- Should have error diagnostic
      assert.is_true(#evaluated.diagnostics > 0)
      local has_unsupported_error = false
      for _, diag in ipairs(evaluated.diagnostics) do
        if diag.type == "frontmatter" and diag.severity == "error" then
          has_unsupported_error = true
          assert.is_truthy(diag.error:match("Unsupported"))
          assert.is_truthy(diag.error:match("yaml"))
        end
      end
      assert.is_true(has_unsupported_error)
    end)
  end)

  describe("integration with templating via pipeline", function()
    it("should use JSON frontmatter variables in Lua expressions", function()
      local lines = {
        "```json",
        '{"greeting": "Hello", "name": "World"}',
        "```",
        "@You: {{ greeting .. ', ' .. name }}!",
      }

      local context = ctx.from_file("test.chat")
      local prompt = pipeline.run(parser.parse_lines(lines), context)

      -- Check that expression was evaluated
      assert.are.equal(1, #prompt.history)
      local user_msg = prompt.history[1]
      assert.are.equal("user", user_msg.role)

      -- Extract text from parts
      local all_text = {}
      for _, p in ipairs(user_msg.parts) do
        if p.kind == "text" then
          table.insert(all_text, p.text or "")
        end
      end
      local content = table.concat(all_text, "")
      assert.are.equal("Hello, World!", content)
    end)
  end)
end)
