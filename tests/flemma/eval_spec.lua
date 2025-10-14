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
      env.__include_stack = { parent_file }
      env.name = "World" -- User variable defined in frontmatter

      -- Call include() - included files are isolated, should NOT have access to 'name'
      local result = eval.eval_expression("include('child.txt')", env)

      -- The variable is not propagated, so the expression evaluates to empty
      assert.are.equal("Hello !", result)

      -- Cleanup
      vim.fn.delete(temp_dir, "rf")
    end)
  end)
end)
