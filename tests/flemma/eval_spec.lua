describe("flemma.templating.eval", function()
  local eval
  local templating

  -- Before each test, get a fresh instance of the eval module
  before_each(function()
    -- Invalidate the package cache to ensure we get a fresh module
    package.loaded["flemma.templating.eval"] = nil
    package.loaded["flemma.templating"] = nil
    package.loaded["flemma.templating.builtins.stdlib"] = nil
    package.loaded["flemma.templating.builtins.iterators"] = nil
    eval = require("flemma.templating.eval")
    templating = require("flemma.templating")
    templating.clear()
    templating.setup()
  end)

  describe("eval_expression", function()
    it("should evaluate a simple expression correctly", function()
      local env = templating.create_env()
      local result = eval.eval_expression("1 + 1", env)
      assert.are.equal(2, result)
    end)

    it("should evaluate an expression using the provided environment", function()
      local env = templating.create_env()
      env.my_var = 10
      local result = eval.eval_expression("my_var * 2", env)
      assert.are.equal(20, result)
    end)
  end)

  describe("execute_frontmatter", function()
    it("should execute code and return new globals", function()
      local env = templating.create_env()
      local globals = eval.execute_frontmatter("my_var = 'test'", env)
      assert.are.equal("test", globals.my_var)
    end)

    it("should not return pre-existing environment variables as new globals", function()
      local env = templating.create_env()
      env.existing_var = "hello"
      local globals = eval.execute_frontmatter("new_var = 'world'", env)
      assert.are.equal("world", globals.new_var)
      assert.is_nil(globals.existing_var)
    end)
  end)

  describe("include() isolation", function()
    it("should NOT propagate user variables from caller environment to included file", function()
      local emittable = require("flemma.emittable")

      -- Setup: Create test files
      local temp_dir = vim.fn.tempname() .. "_include_isolation_test"
      vim.fn.mkdir(temp_dir, "p")

      -- Create an included file that uses a variable from the parent
      local include_file = temp_dir .. "/child.txt"
      local f = io.open(include_file, "w")
      f:write("Hello {{ name }}!")
      f:close()

      -- Create parent file
      local parent_file = temp_dir .. "/parent.chat"

      -- Create environment with user variable 'name'
      local env = templating.create_env()
      env.__filename = parent_file
      env.__dirname = temp_dir
      env.name = "World" -- User variable defined in frontmatter

      -- Call include() - returns IncludePart now, not a string
      local result = eval.eval_expression("include('child.txt')", env)

      -- Result should be emittable (IncludePart)
      assert.is_true(emittable.is_emittable(result))

      -- Emit it and check the output
      local ctx = emittable.EmitContext.new()
      result:emit(ctx)

      -- Combine all text parts
      local texts = {}
      for _, part in ipairs(ctx.parts) do
        if part.kind == "text" then
          table.insert(texts, part.text)
        end
      end
      local output = table.concat(texts, "")

      -- The variable is not propagated, so the expression evaluates to empty
      assert.are.equal("Hello !", output)

      -- Cleanup
      vim.fn.delete(temp_dir, "rf")
    end)
  end)

  describe("include() binary mode", function()
    it("should return a binary IncludePart for binary includes", function()
      local emittable = require("flemma.emittable")

      local temp_dir = vim.fn.tempname() .. "_include_binary_test"
      vim.fn.mkdir(temp_dir, "p")

      -- Create a test file
      local test_file = temp_dir .. "/test.txt"
      local f = io.open(test_file, "w")
      f:write("file content")
      f:close()

      local parent_file = temp_dir .. "/parent.chat"
      local env = templating.create_env()
      env.__filename = parent_file
      env.__dirname = temp_dir

      local result = eval.eval_expression("include('test.txt', { [symbols.BINARY] = true })", env)
      assert.is_true(emittable.is_emittable(result))

      -- Emit and check it produces a file part
      local ctx = emittable.EmitContext.new()
      result:emit(ctx)
      assert.equals(1, #ctx.parts)
      assert.equals("file", ctx.parts[1].kind)
      assert.equals(temp_dir .. "/test.txt", ctx.parts[1].filename)

      vim.fn.delete(temp_dir, "rf")
    end)
  end)

  describe("include() circular detection", function()
    it("should detect circular includes", function()
      local temp_dir = vim.fn.tempname() .. "_include_circular_test"
      vim.fn.mkdir(temp_dir, "p")

      local f1 = io.open(temp_dir .. "/loop1.txt", "w")
      f1:write("{{ include('loop2.txt') }}")
      f1:close()

      local f2 = io.open(temp_dir .. "/loop2.txt", "w")
      f2:write("{{ include('loop1.txt') }}")
      f2:close()

      local parent_file = temp_dir .. "/parent.chat"
      local env = templating.create_env()
      env.__filename = parent_file
      env.__dirname = temp_dir

      local ok, err = pcall(eval.eval_expression, "include('loop1.txt')", env)
      assert.is_false(ok)
      assert.is_true(tostring(err):match("Circular include") ~= nil)

      vim.fn.delete(temp_dir, "rf")
    end)
  end)

  describe("include() structured errors", function()
    it("should throw structured error for missing files in binary mode", function()
      local temp_dir = vim.fn.tempname() .. "_include_error_test"
      vim.fn.mkdir(temp_dir, "p")

      local parent_file = temp_dir .. "/parent.chat"
      local env = templating.create_env()
      env.__filename = parent_file
      env.__dirname = temp_dir

      local ok, err = pcall(eval.eval_expression, "include('nonexistent.png', { [symbols.BINARY] = true })", env)
      assert.is_false(ok)
      -- Structured error table is preserved through eval_expression
      assert.equals("table", type(err))
      assert.equals("file", err.type)
      assert.is_true(err.error:match("File not found") ~= nil)

      vim.fn.delete(temp_dir, "rf")
    end)

    it("should propagate structured errors through execute_frontmatter (frontmatter)", function()
      local temp_dir = vim.fn.tempname() .. "_include_frontmatter_error_test"
      vim.fn.mkdir(temp_dir, "p")

      local parent_file = temp_dir .. "/parent.chat"
      local env = templating.create_env()
      env.__filename = parent_file
      env.__dirname = temp_dir

      local ok, err = pcall(eval.execute_frontmatter, "include('nonexistent.txt')", env)
      assert.is_false(ok)
      -- Structured error table must survive execute_frontmatter, not become "table: 0x..."
      assert.equals("table", type(err))
      assert.equals("file", err.type)
      assert.is_true(err.error:match("File not found") ~= nil)
      -- Include stack should contain the parent file
      assert.is_table(err.include_stack)
      assert.equals(1, #err.include_stack)
      assert.equals(parent_file, err.include_stack[1])

      vim.fn.delete(temp_dir, "rf")
    end)

    it("should treat @./ in included content as plain text (preprocessor handles document level)", function()
      local temp_dir = vim.fn.tempname() .. "_include_nested_text_test"
      vim.fn.mkdir(temp_dir, "p")

      -- middle.txt contains @./ reference — now treated as plain text inside includes
      local middle_file = temp_dir .. "/middle.txt"
      local f = io.open(middle_file, "w")
      f:write("some text @./nonexistent.png and more")
      f:close()

      local parent_file = temp_dir .. "/parent.chat"
      local env = templating.create_env()
      env.__filename = parent_file
      env.__dirname = temp_dir

      -- Should succeed: @./nonexistent.png is plain text, not an include() call
      local ok, result = pcall(eval.eval_expression, "include('middle.txt')", env)
      assert.is_true(ok)
      -- Result should contain the raw @./ reference as text
      assert.is_not_nil(result)

      vim.fn.delete(temp_dir, "rf")
    end)
  end)

  describe("include() parameterized arguments", function()
    it("should pass arguments to the included template", function()
      local emittable_mod = require("flemma.emittable")

      local temp_dir = vim.fn.tempname() .. "_include_args_test"
      vim.fn.mkdir(temp_dir, "p")

      -- Create a template file that uses a parameter
      local greeting_file = temp_dir .. "/greeting.md"
      local f = io.open(greeting_file, "w")
      f:write("Hello, {{ name }}!")
      f:close()

      -- Create parent environment
      local parent_file = temp_dir .. "/parent.chat"
      local env = templating.create_env()
      env.__filename = parent_file
      env.__dirname = temp_dir

      -- Call include() with arguments
      local result = eval.eval_expression("include('greeting.md', { name = 'Alice' })", env)
      assert.is_true(emittable_mod.is_emittable(result))

      -- Emit and check the output
      local ctx = emittable_mod.EmitContext.new()
      result:emit(ctx)

      local texts = {}
      for _, part in ipairs(ctx.parts) do
        if part.kind == "text" then
          table.insert(texts, part.text)
        end
      end
      local output = table.concat(texts, "")
      assert.are.equal("Hello, Alice!", output)

      vim.fn.delete(temp_dir, "rf")
    end)

    it("should isolate arguments from parent environment", function()
      local emittable_mod = require("flemma.emittable")

      local temp_dir = vim.fn.tempname() .. "_include_isolation_args_test"
      vim.fn.mkdir(temp_dir, "p")

      -- Create a template file that uses 'name'
      local child_file = temp_dir .. "/child.md"
      local f = io.open(child_file, "w")
      f:write("{{ name }}")
      f:close()

      -- Create parent environment with name = "Parent"
      local parent_file = temp_dir .. "/parent.chat"
      local env = templating.create_env()
      env.__filename = parent_file
      env.__dirname = temp_dir
      env.name = "Parent"

      -- Call include() with name = "Child" as argument
      local result = eval.eval_expression("include('child.md', { name = 'Child' })", env)
      assert.is_true(emittable_mod.is_emittable(result))

      -- Emit and check the child got "Child", not "Parent"
      local ctx = emittable_mod.EmitContext.new()
      result:emit(ctx)

      local texts = {}
      for _, part in ipairs(ctx.parts) do
        if part.kind == "text" then
          table.insert(texts, part.text)
        end
      end
      local output = table.concat(texts, "")
      assert.are.equal("Child", output)

      -- Verify parent environment is unchanged
      assert.are.equal("Parent", env.name)

      vim.fn.delete(temp_dir, "rf")
    end)
  end)

  describe("include() with {% %} code blocks", function()
    it("should evaluate code blocks inside included files", function()
      local emittable_mod = require("flemma.emittable")

      local temp_dir = vim.fn.tempname() .. "_include_code_blocks"
      vim.fn.mkdir(temp_dir, "p")

      local template_path = temp_dir .. "/conditional.md"
      local f = io.open(template_path, "w")
      f:write("{% if mode == 'strict' then %}Be strict.{% else %}Be friendly.{% end %}")
      f:close()

      local env = templating.create_env()
      env.__filename = temp_dir .. "/test.chat"
      env.__dirname = temp_dir

      -- Test with mode = "strict"
      local result = eval.eval_expression("include('conditional.md', { mode = 'strict' })", env)
      assert.is_true(emittable_mod.is_emittable(result))

      local ctx = emittable_mod.EmitContext.new()
      result:emit(ctx)

      local texts = {}
      for _, part in ipairs(ctx.parts) do
        if part.kind == "text" then
          table.insert(texts, part.text)
        end
      end
      local output = table.concat(texts, "")
      assert.truthy(output:find("Be strict"))
      assert.is_nil(output:find("Be friendly"))

      vim.fn.delete(temp_dir, "rf")
    end)
  end)

  describe("include() absolute paths", function()
    it("should resolve absolute paths without prepending dirname", function()
      local emittable = require("flemma.emittable")

      local temp_dir = vim.fn.tempname() .. "_include_abspath_test"
      vim.fn.mkdir(temp_dir, "p")

      -- Create target file
      local target_file = temp_dir .. "/target.txt"
      local f = io.open(target_file, "w")
      f:write("absolute content")
      f:close()

      -- Set dirname to a DIFFERENT directory to prove absolute path ignores it
      local other_dir = vim.fn.tempname() .. "_include_abspath_other"
      vim.fn.mkdir(other_dir, "p")

      local env = templating.create_env()
      env.__filename = other_dir .. "/parent.chat"
      env.__dirname = other_dir

      local result = eval.eval_expression("include('" .. target_file .. "')", env)
      assert.is_true(emittable.is_emittable(result))

      local ctx = emittable.EmitContext.new()
      result:emit(ctx)

      local texts = {}
      for _, part in ipairs(ctx.parts) do
        if part.kind == "text" then
          table.insert(texts, part.text)
        end
      end
      assert.are.equal("absolute content", table.concat(texts, ""))

      vim.fn.delete(temp_dir, "rf")
      vim.fn.delete(other_dir, "rf")
    end)
  end)
end)
