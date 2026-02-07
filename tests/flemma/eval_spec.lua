describe("flemma.eval", function()
  local eval

  -- Before each test, get a fresh instance of the eval module
  before_each(function()
    -- Invalidate the package cache to ensure we get a fresh module
    package.loaded["flemma.eval"] = nil
    eval = require("flemma.eval")
  end)

  describe("create_safe_env", function()
    it("should create an environment with safe libraries", function()
      local env = eval.create_safe_env()
      assert.is_table(env.string, "Environment should contain the 'string' library")
      assert.is_table(env.math, "Environment should contain the 'math' library")
    end)

    it("should not include unsafe libraries like 'os'", function()
      local env = eval.create_safe_env()
      assert.is_nil(env.os, "Environment should not contain the 'os' library")
    end)
  end)

  describe("eval_expression", function()
    it("should evaluate a simple expression correctly", function()
      local env = eval.create_safe_env()
      local result = eval.eval_expression("1 + 1", env)
      assert.are.equal(2, result)
    end)

    it("should evaluate an expression using the provided environment", function()
      local env = eval.create_safe_env()
      env.my_var = 10
      local result = eval.eval_expression("my_var * 2", env)
      assert.are.equal(20, result)
    end)
  end)

  describe("execute_safe", function()
    it("should execute code and return new globals", function()
      local env = eval.create_safe_env()
      local globals = eval.execute_safe("my_var = 'test'", env)
      assert.are.equal("test", globals.my_var)
    end)

    it("should not return pre-existing environment variables as new globals", function()
      local env = eval.create_safe_env()
      env.existing_var = "hello"
      local globals = eval.execute_safe("new_var = 'world'", env)
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
      local env = eval.create_safe_env()
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
      local env = eval.create_safe_env()
      env.__filename = parent_file
      env.__dirname = temp_dir

      local result = eval.eval_expression("include('test.txt', { binary = true })", env)
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
      local env = eval.create_safe_env()
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
      local env = eval.create_safe_env()
      env.__filename = parent_file
      env.__dirname = temp_dir

      local ok, err = pcall(eval.eval_expression, "include('nonexistent.png', { binary = true })", env)
      assert.is_false(ok)
      -- Structured error table is preserved through eval_expression
      assert.equals("table", type(err))
      assert.equals("file", err.type)
      assert.is_true(err.error:match("File not found") ~= nil)

      vim.fn.delete(temp_dir, "rf")
    end)
  end)
end)
