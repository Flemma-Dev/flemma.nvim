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

    it("should set reasoning.effort and reasoning.summary for reasoning models", function()
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
      assert.equals("auto", request_body.reasoning.summary)
      assert.is_nil(request_body.temperature) -- No temperature with reasoning
      assert.is_nil(request_body.reasoning_effort) -- Should NOT use old flat field
      -- Should request encrypted content for signature round-tripping
      assert.is_not_nil(request_body.include)
      assert.same({ "reasoning.encrypted_content" }, request_body.include)
    end)

    it("should use custom reasoning_summary when configured", function()
      local provider = openai.new({
        model = "o3",
        max_tokens = 4000,
        reasoning = "medium",
        reasoning_summary = "detailed",
      })

      local messages = {
        { type = "You", content = "Hello" },
      }

      local prompt = provider:prepare_prompt(messages)
      local request_body = provider:build_request(prompt)

      assert.equals("detailed", request_body.reasoning.summary)
    end)

    it("should always use developer role for system messages", function()
      -- With reasoning
      local provider_reasoning = openai.new({
        model = "o3",
        max_tokens = 4000,
        reasoning = "high",
      })

      local messages = {
        { type = "System", content = "You are helpful." },
        { type = "You", content = "Solve this problem" },
      }

      local prompt = provider_reasoning:prepare_prompt(messages)
      local request_body = provider_reasoning:build_request(prompt)
      assert.equals("developer", request_body.input[1].role, "Should use developer role with reasoning")

      -- Without reasoning
      local provider_no_reasoning = openai.new({
        model = "gpt-4o",
        max_tokens = 1000,
        temperature = 0.5,
      })

      prompt = provider_no_reasoning:prepare_prompt(messages)
      request_body = provider_no_reasoning:build_request(prompt)
      assert.equals("developer", request_body.input[1].role, "Should use developer role without reasoning")
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

    it("should use consistent ResponseOutputMessage format for assistant text", function()
      local provider = openai.new({
        model = "gpt-4o",
        max_tokens = 1000,
        temperature = 0.7,
      })

      -- Simulate a conversation with assistant response text before a tool call
      local prompt = {
        system = nil,
        history = {
          { role = "user", parts = { { kind = "text", text = "Hello" } } },
          {
            role = "assistant",
            parts = {
              { kind = "text", text = "Let me check that." },
              { kind = "tool_use", id = "call_abc", name = "calculator", input = { expression = "2+2" } },
            },
          },
          {
            role = "user",
            parts = {
              { kind = "tool_result", tool_use_id = "call_abc", content = "4" },
            },
          },
        },
      }

      local request_body = provider:build_request(prompt)

      -- Find the assistant message item (text before tool call)
      local assistant_msg = nil
      for _, item in ipairs(request_body.input) do
        if item.type == "message" and item.role == "assistant" then
          assistant_msg = item
          break
        end
      end

      assert.is_not_nil(assistant_msg, "Should have assistant message item")
      assert.equals("message", assistant_msg.type)
      assert.equals("assistant", assistant_msg.role)
      assert.is_not_nil(assistant_msg.id, "Should have synthetic id")
      assert.equals("completed", assistant_msg.status)
      assert.equals(1, #assistant_msg.content)
      assert.equals("output_text", assistant_msg.content[1].type)
      assert.equals("Let me check that.", assistant_msg.content[1].text)
    end)

    it("should add status=completed on function_call items", function()
      local provider = openai.new({
        model = "gpt-4o",
        max_tokens = 1000,
        temperature = 0.7,
      })

      local prompt = {
        system = nil,
        history = {
          { role = "user", parts = { { kind = "text", text = "Calculate 2+2" } } },
          {
            role = "assistant",
            parts = {
              { kind = "tool_use", id = "call_xyz", name = "calculator", input = { expression = "2+2" } },
            },
          },
          {
            role = "user",
            parts = {
              { kind = "tool_result", tool_use_id = "call_xyz", content = "4" },
            },
          },
        },
      }

      local request_body = provider:build_request(prompt)

      -- Find the function_call item
      local function_call = nil
      for _, item in ipairs(request_body.input) do
        if item.type == "function_call" then
          function_call = item
          break
        end
      end

      assert.is_not_nil(function_call, "Should have function_call item")
      assert.equals("completed", function_call.status)
      assert.equals("call_xyz", function_call.call_id)
      assert.equals("calculator", function_call.name)
    end)

    it("should sort tools array by name for deterministic ordering", function()
      local provider = openai.new({
        model = "gpt-4o",
        max_tokens = 1000,
        temperature = 0.7,
      })

      local prompt = {
        system = nil,
        history = {
          { role = "user", parts = { { kind = "text", text = "Hello" } } },
        },
      }

      local request_body = provider:build_request(prompt)

      if request_body.tools and #request_body.tools > 1 then
        for i = 1, #request_body.tools - 1 do
          assert.is_true(
            request_body.tools[i].name <= request_body.tools[i + 1].name,
            "Tools should be sorted by name: " .. request_body.tools[i].name .. " <= " .. request_body.tools[i + 1].name
          )
        end
      end
    end)

    it("should replay reasoning items from thinking blocks with signature", function()
      local provider = openai.new({
        model = "o3",
        max_tokens = 4000,
        reasoning = "high",
      })

      -- Create a reasoning item and encode it as base64
      local reasoning_item = {
        id = "rs_test_001",
        type = "reasoning",
        summary = { { type = "summary_text", text = "I thought about this." } },
        encrypted_content = "encrypted_data_here",
      }
      local signature = vim.base64.encode(vim.fn.json_encode(reasoning_item))

      local prompt = {
        system = nil,
        history = {
          { role = "user", parts = { { kind = "text", text = "Hello" } } },
          {
            role = "assistant",
            parts = {
              { kind = "thinking", content = "I thought about this.", signature = signature },
              { kind = "text", text = "The answer is 42." },
            },
          },
          { role = "user", parts = { { kind = "text", text = "Thanks" } } },
        },
      }

      local request_body = provider:build_request(prompt)

      -- Find the reasoning item in input — it should be before the assistant message
      local reasoning_index = nil
      local message_index = nil
      for i, item in ipairs(request_body.input) do
        if item.type == "reasoning" then
          reasoning_index = i
        end
        if item.type == "message" and item.role == "assistant" then
          message_index = i
        end
      end

      assert.is_not_nil(reasoning_index, "Should have a reasoning item in input")
      assert.is_not_nil(message_index, "Should have an assistant message in input")
      assert.is_true(reasoning_index < message_index, "Reasoning should come before message")

      -- Verify the decoded reasoning item matches
      local replayed = request_body.input[reasoning_index]
      assert.equals("reasoning", replayed.type)
      assert.equals("rs_test_001", replayed.id)
      assert.equals("encrypted_data_here", replayed.encrypted_content)
    end)

    it("should skip thinking blocks without signature in build_request", function()
      local provider = openai.new({
        model = "gpt-4o",
        max_tokens = 1000,
        temperature = 0.7,
      })

      local prompt = {
        system = nil,
        history = {
          { role = "user", parts = { { kind = "text", text = "Hello" } } },
          {
            role = "assistant",
            parts = {
              { kind = "thinking", content = "some old thinking", signature = "" },
              { kind = "text", text = "Response" },
            },
          },
          { role = "user", parts = { { kind = "text", text = "Thanks" } } },
        },
      }

      local request_body = provider:build_request(prompt)

      -- Should NOT have any reasoning items
      for _, item in ipairs(request_body.input) do
        assert.is_not.equals("reasoning", item.type, "Should not include reasoning without signature")
      end
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

  describe("reasoning/thinking support", function()
    it("should accumulate reasoning summary and emit thinking block from fixture", function()
      local provider = openai.new({
        model = "o3",
        max_tokens = 4000,
        reasoning = "high",
      })

      local lines = vim.fn.readfile("tests/fixtures/tool_calling/openai_reasoning_stream.txt")
      local accumulated_content = ""
      local usage_events = {}
      local completed = false

      local callbacks = {
        on_content = function(content)
          accumulated_content = accumulated_content .. content
        end,
        on_usage = function(data)
          table.insert(usage_events, data)
        end,
        on_response_complete = function()
          completed = true
        end,
        on_error = function() end,
      }

      for _, line in ipairs(lines) do
        provider:process_response_line(line, callbacks)
      end

      -- Should contain some text response (structural check — content varies)
      assert.is_true(#accumulated_content > 0, "Should have accumulated content")

      -- Should contain a thinking block with openai:signature (may be self-closing if no summary)
      assert.is_true(
        accumulated_content:find('<thinking openai:signature="') ~= nil,
        "Should contain thinking block with openai:signature"
      )

      -- Verify usage events include reasoning_tokens > 0
      local found_thoughts = false
      for _, event in ipairs(usage_events) do
        if event.type == "thoughts" then
          assert.is_true(event.tokens > 0, "reasoning_tokens should be > 0")
          found_thoughts = true
        end
      end
      assert.is_true(found_thoughts, "Should report reasoning_tokens as thoughts usage")

      assert.is_true(completed, "Should call on_response_complete")
    end)

    it("should emit thinking block with reasoning + tool call from fixture", function()
      local provider = openai.new({
        model = "o3",
        max_tokens = 4000,
        reasoning = "medium",
      })

      local lines = vim.fn.readfile("tests/fixtures/tool_calling/openai_reasoning_tool_call_stream.txt")
      local accumulated_content = ""
      local usage_events = {}
      local completed = false

      local callbacks = {
        on_content = function(content)
          accumulated_content = accumulated_content .. content
        end,
        on_usage = function(data)
          table.insert(usage_events, data)
        end,
        on_response_complete = function()
          completed = true
        end,
        on_error = function() end,
      }

      for _, line in ipairs(lines) do
        provider:process_response_line(line, callbacks)
      end

      -- Should contain the tool use block (structural checks)
      assert.is_true(accumulated_content:find("%*%*Tool Use:%*%*") ~= nil, "Should contain tool use header")
      assert.is_true(accumulated_content:find("calculator") ~= nil, "Should contain tool name")
      assert.is_true(accumulated_content:find("call_") ~= nil, "Should contain a call_id")

      -- Should contain a thinking block with openai:signature
      assert.is_true(accumulated_content:find('<thinking openai:signature="') ~= nil, "Should contain thinking block")

      -- Verify usage events are present
      local found_input = false
      local found_output = false
      for _, event in ipairs(usage_events) do
        if event.type == "input" then
          assert.is_true(event.tokens > 0, "input tokens should be > 0")
          found_input = true
        elseif event.type == "output" then
          assert.is_true(event.tokens > 0, "output tokens should be > 0")
          found_output = true
        end
      end
      assert.is_true(found_input, "Should have input usage event")
      assert.is_true(found_output, "Should have output usage event")

      assert.is_true(completed, "Should call on_response_complete")
    end)

    it("should round-trip reasoning item via base64 signature", function()
      local reasoning_item = {
        id = "rs_roundtrip",
        type = "reasoning",
        summary = { { type = "summary_text", text = "Thinking..." } },
        encrypted_content = "encrypted_data_roundtrip_test",
      }

      -- Encode
      local json_str = vim.fn.json_encode(reasoning_item)
      local signature = vim.base64.encode(json_str)

      -- Decode
      local decoded_json = vim.base64.decode(signature)
      local ok, decoded = pcall(vim.fn.json_decode, decoded_json)

      assert.is_true(ok, "Should decode successfully")
      assert.equals("reasoning", decoded.type)
      assert.equals("rs_roundtrip", decoded.id)
      assert.equals("encrypted_data_roundtrip_test", decoded.encrypted_content)
    end)

    it("should emit self-closing thinking tag when reasoning has no summary", function()
      local provider = openai.new({
        model = "o3",
        max_tokens = 4000,
        reasoning = "high",
      })

      local accumulated_content = ""
      local callbacks = {
        on_content = function(content)
          accumulated_content = accumulated_content .. content
        end,
        on_usage = function() end,
        on_response_complete = function() end,
        on_error = function() end,
      }

      -- Emit some text first
      provider:process_response_line(
        'data: {"type":"response.output_text.delta","output_index":1,"content_index":0,"delta":"Hello"}',
        callbacks
      )

      -- Start reasoning item
      provider:process_response_line(
        'data: {"type":"response.output_item.added","output_index":0,"item":{"type":"reasoning","id":"rs_empty","summary":[],"encrypted_content":"enc_data"}}',
        callbacks
      )

      -- Complete reasoning with no summary deltas
      provider:process_response_line(
        'data: {"type":"response.output_item.done","output_index":0,"item":{"type":"reasoning","id":"rs_empty","summary":[],"encrypted_content":"enc_data"}}',
        callbacks
      )

      -- Complete response
      provider:process_response_line(
        'data: {"type":"response.completed","response":{"id":"resp_test","status":"completed","usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15}}}',
        callbacks
      )

      -- Should contain self-closing thinking tag
      assert.is_true(
        accumulated_content:find('<thinking openai:signature="[^"]+"/>') ~= nil,
        "Should emit self-closing thinking tag"
      )
    end)
  end)

  describe("response.incomplete handling", function()
    it("should handle response.incomplete from fixture", function()
      local provider = openai.new({
        model = "gpt-4o",
        max_tokens = 100,
        temperature = 0.7,
      })

      local lines = vim.fn.readfile("tests/fixtures/tool_calling/openai_incomplete_stream.txt")
      local accumulated_content = ""
      local usage_events = {}
      local completed = false

      local callbacks = {
        on_content = function(content)
          accumulated_content = accumulated_content .. content
        end,
        on_usage = function(data)
          table.insert(usage_events, data)
        end,
        on_response_complete = function()
          completed = true
        end,
        on_error = function() end,
      }

      for _, line in ipairs(lines) do
        provider:process_response_line(line, callbacks)
      end

      -- Should contain some partial text (structural check — content varies)
      assert.is_true(#accumulated_content > 0, "Should contain partial text")

      -- Should still complete (not error)
      assert.is_true(completed, "Should call on_response_complete even on incomplete")

      -- Should extract usage with input_tokens > 0
      local found_input = false
      for _, event in ipairs(usage_events) do
        if event.type == "input" then
          assert.is_true(event.tokens > 0, "input tokens should be > 0")
          found_input = true
        end
      end
      assert.is_true(found_input, "Should extract usage from incomplete response")
    end)

    it("should call on_response_complete for response.incomplete event", function()
      local provider = openai.new({
        model = "gpt-4o",
        max_tokens = 100,
        temperature = 0.7,
      })

      local completed = false
      local callbacks = {
        on_content = function() end,
        on_usage = function() end,
        on_response_complete = function()
          completed = true
        end,
        on_error = function() end,
      }

      provider:process_response_line(
        'data: {"type":"response.incomplete","response":{"id":"resp_inc","status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"usage":{"input_tokens":50,"output_tokens":100,"total_tokens":150}}}',
        callbacks
      )

      assert.is_true(completed, "Should call on_response_complete")
    end)
  end)

  describe("metadata", function()
    it("should report outputs_thinking as true", function()
      assert.is_true(openai.metadata.capabilities.outputs_thinking)
    end)

    it("should include reasoning_summary in default parameters", function()
      assert.equals("auto", openai.metadata.default_parameters.reasoning_summary)
    end)
  end)
end)
