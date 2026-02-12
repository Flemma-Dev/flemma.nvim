--- Test file for OpenAI provider functionality
describe("OpenAI Provider", function()
  local openai = require("flemma.provider.providers.openai")

  after_each(function()
    -- Clean up any buffers created during the test
    vim.cmd("silent! %bdelete!")
  end)

  describe("build_request", function()
    it("should use max_output_tokens for all OpenAI models", function()
      local test_cases = {
        { model = "gpt-4o", max_tokens = 1000 },
        { model = "gpt-4o-mini", max_tokens = 2000 },
        { model = "gpt-5-mini", max_tokens = 3000 },
        { model = "o1", max_tokens = 4000 },
        { model = "o4-mini", max_tokens = 5000 },
        { model = "o3", max_tokens = 6000 },
      }

      for _, test_case in ipairs(test_cases) do
        local provider = openai.new({
          model = test_case.model,
          max_tokens = test_case.max_tokens,
          temperature = 0.7,
        })

        local messages = {
          { type = "You", content = "Hello" },
        }

        local prompt = provider:prepare_prompt(messages)
        local request_body = provider:build_request(prompt)

        -- Verify max_output_tokens is used (not max_tokens or max_completion_tokens)
        assert.is_not_nil(
          request_body.max_output_tokens,
          string.format("Model %s should use max_output_tokens", test_case.model)
        )
        assert.equals(
          test_case.max_tokens,
          request_body.max_output_tokens,
          string.format("Model %s should have correct max_output_tokens value", test_case.model)
        )
        assert.is_nil(
          request_body.max_tokens,
          string.format("Model %s should NOT use deprecated max_tokens", test_case.model)
        )
        assert.is_nil(
          request_body.max_completion_tokens,
          string.format("Model %s should NOT use old max_completion_tokens", test_case.model)
        )
      end
    end)

    it("should use input instead of messages", function()
      local provider = openai.new({
        model = "gpt-4o",
        max_tokens = 1000,
        temperature = 0.7,
      })

      local messages = {
        { type = "You", content = "Hello" },
      }

      local prompt = provider:prepare_prompt(messages)
      local request_body = provider:build_request(prompt)

      assert.is_not_nil(request_body.input, "Should use input field")
      assert.is_nil(request_body.messages, "Should NOT use messages field")
    end)

    it("should include store = false", function()
      local provider = openai.new({
        model = "gpt-4o",
        max_tokens = 1000,
        temperature = 0.7,
      })

      local messages = {
        { type = "You", content = "Hello" },
      }

      local prompt = provider:prepare_prompt(messages)
      local request_body = provider:build_request(prompt)

      assert.equals(false, request_body.store, "Should set store = false for privacy")
    end)

    it("should set reasoning.effort for o-series models with reasoning parameter", function()
      local provider = openai.new({
        model = "o3",
        max_tokens = 4000,
        reasoning = "high",
      })

      local messages = {
        { type = "You", content = "Solve this problem" },
      }

      local prompt = provider:prepare_prompt(messages)
      local request_body = provider:build_request(prompt)

      assert.equals(4000, request_body.max_output_tokens)
      assert.is_not_nil(request_body.reasoning)
      assert.equals("high", request_body.reasoning.effort)
      assert.is_nil(request_body.temperature) -- No temperature with reasoning
      assert.is_nil(request_body.reasoning_effort) -- Should NOT use old flat field
    end)

    it("should use developer role for system message when reasoning is active", function()
      local provider = openai.new({
        model = "o3",
        max_tokens = 4000,
        reasoning = "high",
      })

      local messages = {
        { type = "System", content = "You are helpful." },
        { type = "You", content = "Solve this problem" },
      }

      local prompt = provider:prepare_prompt(messages)
      local request_body = provider:build_request(prompt)

      assert.equals("developer", request_body.input[1].role, "Should use developer role for system with reasoning")
    end)

    it("should use system role for system message when reasoning is not active", function()
      local provider = openai.new({
        model = "gpt-4o",
        max_tokens = 1000,
        temperature = 0.5,
      })

      local messages = {
        { type = "System", content = "You are helpful." },
        { type = "You", content = "Hello" },
      }

      local prompt = provider:prepare_prompt(messages)
      local request_body = provider:build_request(prompt)

      assert.equals("system", request_body.input[1].role, "Should use system role without reasoning")
    end)

    it("should set temperature for non-reasoning models", function()
      local provider = openai.new({
        model = "gpt-4o",
        max_tokens = 1000,
        temperature = 0.5,
      })

      local messages = {
        { type = "You", content = "Hello" },
      }

      local prompt = provider:prepare_prompt(messages)
      local request_body = provider:build_request(prompt)

      assert.equals(1000, request_body.max_output_tokens)
      assert.equals(0.5, request_body.temperature)
      assert.is_nil(request_body.reasoning)
    end)
  end)

  describe("prompt caching", function()
    local ctx = require("flemma.context")

    it("should send prompt_cache_key and in_memory retention by default", function()
      local provider = openai.new({
        model = "gpt-5",
        max_tokens = 1000,
        temperature = 0.7,
      })

      local messages = {
        { type = "You", content = "Hello" },
      }

      local context = ctx.from_file("tests/fixtures/doc.chat")
      local prompt = provider:prepare_prompt(messages)
      local request_body = provider:build_request(prompt, context)

      assert.equals("tests/fixtures/doc.chat", request_body.prompt_cache_key)
      assert.equals("in_memory", request_body.prompt_cache_retention)
    end)

    it("should send prompt_cache_key and 24h retention for cache_retention=long", function()
      local provider = openai.new({
        model = "gpt-5",
        max_tokens = 1000,
        temperature = 0.7,
        cache_retention = "long",
      })

      local messages = {
        { type = "You", content = "Hello" },
      }

      local context = ctx.from_file("tests/fixtures/doc.chat")
      local prompt = provider:prepare_prompt(messages)
      local request_body = provider:build_request(prompt, context)

      assert.equals("tests/fixtures/doc.chat", request_body.prompt_cache_key)
      assert.equals("24h", request_body.prompt_cache_retention)
    end)

    it("should send neither caching parameter for cache_retention=none", function()
      local provider = openai.new({
        model = "gpt-5",
        max_tokens = 1000,
        temperature = 0.7,
        cache_retention = "none",
      })

      local messages = {
        { type = "You", content = "Hello" },
      }

      local context = ctx.from_file("tests/fixtures/doc.chat")
      local prompt = provider:prepare_prompt(messages)
      local request_body = provider:build_request(prompt, context)

      assert.is_nil(request_body.prompt_cache_key)
      assert.is_nil(request_body.prompt_cache_retention)
    end)

    it("should omit prompt_cache_key for unsaved buffers", function()
      local provider = openai.new({
        model = "gpt-5",
        max_tokens = 1000,
        temperature = 0.7,
      })

      local messages = {
        { type = "You", content = "Hello" },
      }

      -- Create context with empty filename (simulates unsaved buffer)
      local context = ctx.from_file("")
      local prompt = provider:prepare_prompt(messages)
      local request_body = provider:build_request(prompt, context)

      assert.is_nil(request_body.prompt_cache_key)
      assert.equals("in_memory", request_body.prompt_cache_retention)
    end)
  end)

  describe("process_response_line", function()
    it("should parse text deltas from response.output_text.delta events", function()
      local provider = openai.new({
        model = "gpt-4o",
        max_tokens = 4000,
        temperature = 0.7,
      })

      local accumulated_content = ""
      local callbacks = {
        on_content = function(text)
          accumulated_content = accumulated_content .. text
        end,
        on_usage = function() end,
        on_response_complete = function() end,
        on_error = function() end,
      }

      -- Simulate text delta events
      provider:process_response_line(
        'data: {"type":"response.output_text.delta","output_index":0,"content_index":0,"delta":"Hello"}',
        callbacks
      )
      provider:process_response_line(
        'data: {"type":"response.output_text.delta","output_index":0,"content_index":0,"delta":"! How are you?"}',
        callbacks
      )

      assert.equals("Hello! How are you?", accumulated_content)
    end)

    it("should parse cached tokens from response.completed event", function()
      local provider = openai.new({
        model = "gpt-5",
        max_tokens = 4000,
        temperature = 0.7,
      })

      local usage_events = {}
      local completed = false
      local callbacks = {
        on_content = function() end,
        on_usage = function(data)
          table.insert(usage_events, data)
        end,
        on_response_complete = function()
          completed = true
        end,
        on_error = function() end,
      }

      -- Simulate a response.completed event with usage that includes cached tokens
      local usage_line = 'data: {"type":"response.completed","response":{"id":"resp_abc","status":"completed","usage":'
        .. '{"input_tokens":1500,"output_tokens":200,"total_tokens":1700,'
        .. '"input_tokens_details":{"cached_tokens":1024},'
        .. '"output_tokens_details":{"reasoning_tokens":0}}}}'
      provider:process_response_line(usage_line, callbacks)

      -- Should have received input, output, and cache_read usage events
      assert.is_true(#usage_events >= 3, "Expected at least 3 usage events, got " .. #usage_events)

      local found_input = false
      local found_output = false
      local found_cache_read = false
      for _, event in ipairs(usage_events) do
        if event.type == "input" then
          -- input_tokens = input_tokens - cached_tokens (1500 - 1024 = 476)
          assert.equals(476, event.tokens)
          found_input = true
        elseif event.type == "output" then
          assert.equals(200, event.tokens)
          found_output = true
        elseif event.type == "cache_read" then
          assert.equals(1024, event.tokens)
          found_cache_read = true
        end
      end

      assert.is_true(found_input, "Expected input usage event")
      assert.is_true(found_output, "Expected output usage event")
      assert.is_true(found_cache_read, "Expected cache_read usage event")
      assert.is_true(completed, "Expected on_response_complete to be called")
    end)

    it("should not emit cache_read when cached_tokens is zero", function()
      local provider = openai.new({
        model = "gpt-5",
        max_tokens = 4000,
        temperature = 0.7,
      })

      local usage_events = {}
      local callbacks = {
        on_content = function() end,
        on_usage = function(data)
          table.insert(usage_events, data)
        end,
        on_response_complete = function() end,
        on_error = function() end,
      }

      -- Simulate a response.completed event with zero cached tokens
      local usage_line = 'data: {"type":"response.completed","response":{"id":"resp_abc","status":"completed","usage":'
        .. '{"input_tokens":500,"output_tokens":100,"total_tokens":600,'
        .. '"input_tokens_details":{"cached_tokens":0},'
        .. '"output_tokens_details":{"reasoning_tokens":0}}}}'
      provider:process_response_line(usage_line, callbacks)

      -- Should NOT have a cache_read event
      for _, event in ipairs(usage_events) do
        assert.is_not.equals("cache_read", event.type, "Should not emit cache_read for zero cached tokens")
      end
    end)

    it("should handle missing input_tokens_details gracefully", function()
      local provider = openai.new({
        model = "gpt-5",
        max_tokens = 4000,
        temperature = 0.7,
      })

      local usage_events = {}
      local callbacks = {
        on_content = function() end,
        on_usage = function(data)
          table.insert(usage_events, data)
        end,
        on_response_complete = function() end,
        on_error = function() end,
      }

      -- Simulate a response.completed event without input_tokens_details
      local usage_line = 'data: {"type":"response.completed","response":{"id":"resp_abc","status":"completed","usage":'
        .. '{"input_tokens":500,"output_tokens":100,"total_tokens":600}}}'
      provider:process_response_line(usage_line, callbacks)

      -- Should have input and output but no cache_read
      local found_cache_read = false
      for _, event in ipairs(usage_events) do
        if event.type == "cache_read" then
          found_cache_read = true
        end
      end
      assert.is_false(found_cache_read, "Should not emit cache_read when input_tokens_details is missing")
    end)

    it("should ignore event: lines and process data: lines by type", function()
      local provider = openai.new({
        model = "gpt-4o",
        max_tokens = 4000,
        temperature = 0.7,
      })

      local accumulated_content = ""
      local callbacks = {
        on_content = function(text)
          accumulated_content = accumulated_content .. text
        end,
        on_usage = function() end,
        on_response_complete = function() end,
        on_error = function() end,
      }

      -- Event lines should be silently skipped
      provider:process_response_line("event: response.output_text.delta", callbacks)
      -- Data lines should be processed
      provider:process_response_line(
        'data: {"type":"response.output_text.delta","output_index":0,"content_index":0,"delta":"test"}',
        callbacks
      )

      assert.equals("test", accumulated_content)
    end)

    it("should parse function_call from streaming response", function()
      local provider = openai.new({
        model = "gpt-4o-mini",
        max_tokens = 1024,
        temperature = 0,
      })

      local accumulated_content = ""
      local callbacks = {
        on_content = function(content)
          accumulated_content = accumulated_content .. content
        end,
        on_response_complete = function() end,
        on_error = function() end,
      }

      -- Simulate function_call flow
      provider:process_response_line(
        'data: {"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"fc_123","call_id":"call_abc","name":"calculator","arguments":"","status":"in_progress"}}',
        callbacks
      )
      provider:process_response_line(
        'data: {"type":"response.function_call_arguments.delta","output_index":0,"delta":"{\\"expression"}',
        callbacks
      )
      provider:process_response_line(
        'data: {"type":"response.function_call_arguments.delta","output_index":0,"delta":"\\": \\"2+2\\"}"}',
        callbacks
      )
      provider:process_response_line(
        'data: {"type":"response.output_item.done","output_index":0,"item":{"type":"function_call","id":"fc_123","call_id":"call_abc","name":"calculator","arguments":"{\\"expression\\": \\"2+2\\"}","status":"completed"}}',
        callbacks
      )

      assert.is_true(accumulated_content:match("%*%*Tool Use:%*%*") ~= nil, "Should emit tool_use header")
      assert.is_true(accumulated_content:match("calculator") ~= nil, "Should include tool name")
      assert.is_true(accumulated_content:match("call_abc") ~= nil, "Should include call_id")
    end)
  end)
end)
