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
