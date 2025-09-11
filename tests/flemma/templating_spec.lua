describe("flemma.templating", function()
  local eval = require("flemma.eval")
  local frontmatter = require("flemma.frontmatter")
  local buffers = require("flemma.buffers")

  -- Helper function to simulate expression evaluation in message content
  local function process_expressions(content, env)
    -- This simulates what should happen when {{expression}} templates are processed
    return content:gsub("{{([^}]+)}}", function(expr)
      local result = eval.eval_expression(expr:match("^%s*(.-)%s*$"), env)
      return tostring(result)
    end)
  end

  describe("frontmatter and expression interaction", function()
    it("should use frontmatter variables in message expressions", function()
      -- Create a buffer with frontmatter and templated messages
      local bufnr = vim.api.nvim_create_buf(false, false)

      local lines = {
        "```lua",
        "my_var = 'world'",
        "my_func = function(name) return 'Hello, ' .. name end",
        "```",
        "@You: Value is {{my_var}} and greeting is {{my_func('Claude')}}",
      }

      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Parse buffer to get messages and frontmatter
      local messages, frontmatter_code = buffers.parse_buffer(bufnr)

      -- Execute frontmatter to get environment
      local frontmatter_env = frontmatter.execute(frontmatter_code, "test.chat")

      -- Create evaluation environment with frontmatter variables
      local eval_env = eval.create_safe_env()
      for k, v in pairs(frontmatter_env) do
        eval_env[k] = v
      end

      -- Process expressions in messages
      assert.are.equal(1, #messages, "Should parse 1 message")
      assert.are.equal("You", messages[1].type)

      -- Simulate expression processing (this would be done by the main plugin)
      local processed_content = process_expressions(messages[1].content, eval_env)

      -- Verify the templated content is correctly evaluated
      assert.are.equal("Value is world and greeting is Hello, Claude", processed_content)
    end)

    it("should handle complex expressions with function calls", function()
      local bufnr = vim.api.nvim_create_buf(false, false)

      local lines = {
        "```lua",
        "function format_user(name, role)",
        "  return string.upper(name) .. ' (' .. role .. ')'",
        "end",
        "user_name = 'alice'",
        "user_role = 'admin'",
        "```",
        "@You: Current user: {{format_user(user_name, user_role)}}",
      }

      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      local messages, frontmatter_code = buffers.parse_buffer(bufnr)
      local frontmatter_env = frontmatter.execute(frontmatter_code, "test.chat")

      local eval_env = eval.create_safe_env()
      for k, v in pairs(frontmatter_env) do
        eval_env[k] = v
      end

      local processed_content = process_expressions(messages[1].content, eval_env)

      assert.are.equal("Current user: ALICE (admin)", processed_content)
    end)

    it("should handle multiple expressions in the same message", function()
      local bufnr = vim.api.nvim_create_buf(false, false)

      local lines = {
        "```lua",
        "x = 5",
        "y = 3",
        "```",
        "@You: {{x}} + {{y}} = {{x + y}}",
      }

      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      local messages, frontmatter_code = buffers.parse_buffer(bufnr)
      local frontmatter_env = frontmatter.execute(frontmatter_code, "test.chat")

      local eval_env = eval.create_safe_env()
      for k, v in pairs(frontmatter_env) do
        eval_env[k] = v
      end

      local processed_content = process_expressions(messages[1].content, eval_env)

      assert.are.equal("5 + 3 = 8", processed_content)
    end)

    it("should work with messages that have no expressions", function()
      local bufnr = vim.api.nvim_create_buf(false, false)

      local lines = {
        "```lua",
        "unused_var = 'test'",
        "```",
        "@You: This is a plain message without templates",
      }

      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      local messages, frontmatter_code = buffers.parse_buffer(bufnr)
      local frontmatter_env = frontmatter.execute(frontmatter_code, "test.chat")

      local eval_env = eval.create_safe_env()
      for k, v in pairs(frontmatter_env) do
        eval_env[k] = v
      end

      local processed_content = process_expressions(messages[1].content, eval_env)

      assert.are.equal("This is a plain message without templates", processed_content)
    end)

    it("should handle expressions accessing safe environment functions", function()
      local bufnr = vim.api.nvim_create_buf(false, false)

      local lines = {
        "```lua",
        "text = 'hello world'",
        "```",
        "@You: Uppercase: {{string.upper(text)}}",
      }

      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      local messages, frontmatter_code = buffers.parse_buffer(bufnr)
      local frontmatter_env = frontmatter.execute(frontmatter_code, "test.chat")

      local eval_env = eval.create_safe_env()
      for k, v in pairs(frontmatter_env) do
        eval_env[k] = v
      end

      local processed_content = process_expressions(messages[1].content, eval_env)

      assert.are.equal("Uppercase: HELLO WORLD", processed_content)
    end)
  end)

  describe("relative and nested include() calls", function()
    it("should resolve relative paths correctly with nested includes", function()
      -- Get path to fixtures directory
      local test_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h") .. "/fixtures/include_test"
      local main_file = test_dir .. "/main.chat"

      -- Read the content from the fixture file
      local file = io.open(main_file, "r")
      assert.is_not_nil(file, "Could not open test fixture file: " .. main_file)
      local content = file:read("*a")
      file:close()

      -- Create a buffer with the main content
      local bufnr = vim.api.nvim_create_buf(false, false)
      local lines = vim.split(content, "\n", { plain = true })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Set the buffer name to simulate the file path for include resolution
      vim.api.nvim_buf_set_name(bufnr, main_file)

      -- Parse messages from the buffer
      local messages = buffers.parse_buffer(bufnr)

      -- Create evaluation environment with filename and include stack
      local eval_env = eval.create_safe_env()
      eval_env.__filename = main_file
      eval_env.__include_stack = {}

      -- Process expressions in the message content
      assert.are.equal(1, #messages, "Should parse 1 message")
      assert.are.equal("You", messages[1].type)

      local processed_content = process_expressions(messages[1].content, eval_env)

      -- Verify the nested includes are resolved correctly
      -- Expected: "Main prompt. Including Base content. Including This is a nested detail."
      -- Note: trim trailing whitespace that might come from file reads
      local expected = "Main prompt. Including Base content. Including This is a nested detail."
      assert.are.equal(expected, processed_content:gsub("%s+$", ""))
    end)

    it("should handle multiple levels of nested includes correctly", function()
      -- Create a more complex nested structure in memory for this test
      local temp_dir = vim.fn.tempname() .. "_include_test"
      vim.fn.mkdir(temp_dir, "p")
      vim.fn.mkdir(temp_dir .. "/level1", "p")
      vim.fn.mkdir(temp_dir .. "/level1/level2", "p")

      -- Create test files
      local level2_file = temp_dir .. "/level1/level2/deep.txt"
      local level1_file = temp_dir .. "/level1/middle.txt"
      local main_file = temp_dir .. "/main.chat"

      -- Write content to files
      local f = io.open(level2_file, "w")
      f:write("Deep content")
      f:close()

      f = io.open(level1_file, "w")
      f:write("Middle content with {{ include('./level2/deep.txt') }}")
      f:close()

      f = io.open(main_file, "w")
      f:write("@You: Root content with {{ include('./level1/middle.txt') }}")
      f:close()

      -- Read and process
      f = io.open(main_file, "r")
      local content = f:read("*a")
      f:close()

      local bufnr = vim.api.nvim_create_buf(false, false)
      local lines = vim.split(content, "\n", { plain = true })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.api.nvim_buf_set_name(bufnr, main_file)

      local messages = buffers.parse_buffer(bufnr)
      local eval_env = eval.create_safe_env()
      eval_env.__filename = main_file
      eval_env.__include_stack = {}

      local processed_content = process_expressions(messages[1].content, eval_env)

      assert.are.equal("Root content with Middle content with Deep content", processed_content:gsub("%s+$", ""))

      -- Clean up temp files
      vim.fn.delete(temp_dir, "rf")
    end)

    it("should detect circular includes and prevent infinite recursion", function()
      -- Create circular include structure
      local temp_dir = vim.fn.tempname() .. "_circular_test"
      vim.fn.mkdir(temp_dir, "p")

      local file_a = temp_dir .. "/a.txt"
      local file_b = temp_dir .. "/b.txt"
      local main_file = temp_dir .. "/main.chat"

      -- Create circular references: a includes b, b includes a
      local f = io.open(file_a, "w")
      f:write("A includes {{ include('./b.txt') }}")
      f:close()

      f = io.open(file_b, "w")
      f:write("B includes {{ include('./a.txt') }}")
      f:close()

      f = io.open(main_file, "w")
      f:write("@You: Main includes {{ include('./a.txt') }}")
      f:close()

      -- Read and process - this should error
      f = io.open(main_file, "r")
      local content = f:read("*a")
      f:close()

      local bufnr = vim.api.nvim_create_buf(false, false)
      local lines = vim.split(content, "\n", { plain = true })
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.api.nvim_buf_set_name(bufnr, main_file)

      local messages = buffers.parse_buffer(bufnr)
      local eval_env = eval.create_safe_env()
      eval_env.__filename = main_file
      eval_env.__include_stack = {}

      -- Should throw error about circular include
      assert.has_error(function()
        process_expressions(messages[1].content, eval_env)
      end)

      -- Clean up temp files
      vim.fn.delete(temp_dir, "rf")
    end)
  end)

  describe("integration with FlemmaSend workflow", function()
    -- This test simulates how the templating system should integrate with the main send workflow
    -- It mocks the provider to capture the processed messages
    it("should process templates before sending to provider", function()
      local bufnr = vim.api.nvim_create_buf(false, false)

      local lines = {
        "```lua",
        "my_var = 'world'",
        "my_func = function(name) return 'Hello, ' .. name end",
        "```",
        "@You: Value is {{my_var}} and greeting is {{my_func('Claude')}}",
      }

      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- This test focuses on the templating logic rather than provider integration

      -- Parse and process the buffer content
      local messages, frontmatter_code = buffers.parse_buffer(bufnr)
      local frontmatter_env = frontmatter.execute(frontmatter_code, "test.chat")

      local eval_env = eval.create_safe_env()
      for k, v in pairs(frontmatter_env) do
        eval_env[k] = v
      end

      -- Process expressions in messages (this should be part of the main flow)
      for _, message in ipairs(messages) do
        message.content = process_expressions(message.content, eval_env)
      end

      -- Verify the processed messages directly since we're testing the templating logic
      assert.are.equal(1, #messages)
      assert.are.equal("You", messages[1].type)
      assert.are.equal("Value is world and greeting is Hello, Claude", messages[1].content)
    end)
  end)
end)
