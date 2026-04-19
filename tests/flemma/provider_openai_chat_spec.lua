--- Test file for OpenAI Chat Completions base provider functionality
describe("OpenAI Chat Completions Base Provider", function()
  local openai_chat = require("flemma.provider.adapters.openai_chat")
  local json = require("flemma.utilities.json")
  local make_prompt = require("tests.utilities.prompt").make_prompt

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  describe("build_request", function()
    it("should use messages array (not input)", function()
      local provider = openai_chat._new_concrete({ model = "test-model", max_tokens = 1000, temperature = 0.7 })

      local prompt = make_prompt({
        { type = "You", content = "Hello" },
      })
      local request_body = provider:build_request(prompt)

      assert.is_not_nil(request_body.messages, "Should use messages field")
      assert.is_nil(request_body.input, "Should NOT use input field")
    end)

    it("should set stream and stream_options", function()
      local provider = openai_chat._new_concrete({ model = "test-model", max_tokens = 1000 })

      local prompt = make_prompt({ { type = "You", content = "Hello" } })
      local request_body = provider:build_request(prompt)

      assert.equals(true, request_body.stream)
      assert.is_not_nil(request_body.stream_options)
      assert.equals(true, request_body.stream_options.include_usage)
    end)

    it("should use max_tokens key by default", function()
      local provider = openai_chat._new_concrete({ model = "test-model", max_tokens = 2000 })

      local prompt = make_prompt({ { type = "You", content = "Hello" } })
      local request_body = provider:build_request(prompt)

      assert.equals(2000, request_body.max_tokens)
      assert.is_nil(request_body.max_completion_tokens)
    end)

    it("should include model and temperature", function()
      local provider = openai_chat._new_concrete({ model = "custom-model", max_tokens = 1000, temperature = 0.5 })

      local prompt = make_prompt({ { type = "You", content = "Hello" } })
      local request_body = provider:build_request(prompt)

      assert.equals("custom-model", request_body.model)
      assert.equals(0.5, request_body.temperature)
    end)

    it("should add system message with role system", function()
      local provider = openai_chat._new_concrete()

      local prompt = make_prompt({
        { type = "System", content = "You are helpful." },
        { type = "You", content = "Hello" },
      })
      local request_body = provider:build_request(prompt)

      assert.equals("system", request_body.messages[1].role)
      assert.equals("You are helpful.", request_body.messages[1].content)
    end)

    it("should use plain string content for text-only user messages", function()
      local provider = openai_chat._new_concrete()

      local prompt = make_prompt({ { type = "You", content = "Hello world" } })
      local request_body = provider:build_request(prompt)

      -- Find the user message
      local user_msg = nil
      for _, msg in ipairs(request_body.messages) do
        if msg.role == "user" then
          user_msg = msg
          break
        end
      end

      assert.is_not_nil(user_msg)
      assert.equals("string", type(user_msg.content), "Text-only messages should have string content")
      assert.equals("Hello world", user_msg.content)
    end)

    it("should use array content for multimodal user messages", function()
      local provider = openai_chat._new_concrete()

      local prompt = {
        system = nil,
        history = {
          {
            role = "user",
            parts = {
              { kind = "text", text = "What is this?" },
              {
                kind = "image",
                mime_type = "image/png",
                data = "base64data",
                data_url = "data:image/png;base64,base64data",
                filename = "test.png",
              },
            },
          },
        },
      }

      local request_body = provider:build_request(prompt)
      local user_msg = request_body.messages[1]

      assert.equals("table", type(user_msg.content), "Multimodal messages should have array content")
      assert.equals(2, #user_msg.content)
      assert.equals("text", user_msg.content[1].type)
      assert.equals("image_url", user_msg.content[2].type)
      assert.equals("data:image/png;base64,base64data", user_msg.content[2].image_url.url)
    end)

    it("should emit tool results as role=tool messages before user content", function()
      local provider = openai_chat._new_concrete()

      local prompt = {
        system = nil,
        history = {
          { role = "user", parts = { { kind = "text", text = "Calculate 2+2" } } },
          {
            role = "assistant",
            parts = {
              { kind = "tool_use", id = "call_abc", name = "calculator", input = { expression = "2+2" } },
            },
          },
          {
            role = "user",
            parts = {
              {
                kind = "tool_result",
                tool_use_id = "call_abc",
                name = "calculator",
                parts = { { kind = "text", text = "4" } },
                is_error = false,
              },
              { kind = "text", text = "Thanks" },
            },
          },
        },
      }

      local request_body = provider:build_request(prompt)

      -- Find tool and user messages in the tail
      local tool_msg_index = nil
      local user_msg_index = nil
      for i, msg in ipairs(request_body.messages) do
        if msg.role == "tool" and not tool_msg_index then
          tool_msg_index = i
        end
        if msg.role == "user" and msg.content == "Thanks" then
          user_msg_index = i
        end
      end

      assert.is_not_nil(tool_msg_index, "Should have a tool message")
      assert.is_not_nil(user_msg_index, "Should have a user message after tool")
      assert.is_true(tool_msg_index < user_msg_index, "Tool result should come before user content")

      local tool_msg = request_body.messages[tool_msg_index]
      assert.equals("tool", tool_msg.role)
      assert.equals("call_abc", tool_msg.tool_call_id)
      assert.equals("calculator", tool_msg.name)
      assert.equals("4", tool_msg.content)
    end)

    it("should prefix error tool results with Error:", function()
      local provider = openai_chat._new_concrete()

      local prompt = {
        system = nil,
        history = {
          { role = "user", parts = { { kind = "text", text = "Do something" } } },
          {
            role = "assistant",
            parts = {
              { kind = "tool_use", id = "call_err", name = "broken_tool", input = {} },
            },
          },
          {
            role = "user",
            parts = {
              {
                kind = "tool_result",
                tool_use_id = "call_err",
                parts = { { kind = "text", text = "Something went wrong" } },
                is_error = true,
              },
            },
          },
        },
      }

      local request_body = provider:build_request(prompt)

      local tool_msg = nil
      for _, msg in ipairs(request_body.messages) do
        if msg.role == "tool" then
          tool_msg = msg
          break
        end
      end

      assert.is_not_nil(tool_msg)
      assert.equals("Error: Something went wrong", tool_msg.content)
    end)

    it("should build assistant messages with tool_calls array", function()
      local provider = openai_chat._new_concrete()

      local prompt = {
        system = nil,
        history = {
          { role = "user", parts = { { kind = "text", text = "Hello" } } },
          {
            role = "assistant",
            parts = {
              { kind = "text", text = "Let me check." },
              { kind = "tool_use", id = "call_xyz", name = "search", input = { query = "test" } },
            },
          },
          {
            role = "user",
            parts = {
              {
                kind = "tool_result",
                tool_use_id = "call_xyz",
                parts = { { kind = "text", text = "Found it" } },
                is_error = false,
              },
            },
          },
        },
      }

      local request_body = provider:build_request(prompt)

      -- Find the assistant message
      local assistant_msg = nil
      for _, msg in ipairs(request_body.messages) do
        if msg.role == "assistant" then
          assistant_msg = msg
          break
        end
      end

      assert.is_not_nil(assistant_msg)
      assert.equals("Let me check.", assistant_msg.content)
      assert.is_not_nil(assistant_msg.tool_calls)
      assert.equals(1, #assistant_msg.tool_calls)
      assert.equals("call_xyz", assistant_msg.tool_calls[1].id)
      assert.equals("function", assistant_msg.tool_calls[1].type)
      assert.equals("search", assistant_msg.tool_calls[1]["function"].name)

      -- Arguments should be a JSON string
      local args = json.decode(assistant_msg.tool_calls[1]["function"].arguments)
      assert.equals("test", args.query)
    end)

    it("should preserve reasoning_content from thinking parts", function()
      local provider = openai_chat._new_concrete()

      local prompt = {
        system = nil,
        history = {
          { role = "user", parts = { { kind = "text", text = "Hello" } } },
          {
            role = "assistant",
            parts = {
              { kind = "thinking", content = "Let me reason about this." },
              { kind = "text", text = "The answer is 42." },
            },
          },
          { role = "user", parts = { { kind = "text", text = "Thanks" } } },
        },
      }

      local request_body = provider:build_request(prompt)

      local assistant_msg = nil
      for _, msg in ipairs(request_body.messages) do
        if msg.role == "assistant" then
          assistant_msg = msg
          break
        end
      end

      assert.is_not_nil(assistant_msg)
      assert.equals("Let me reason about this.", assistant_msg.reasoning_content)
      assert.equals("The answer is 42.", assistant_msg.content)
    end)

    it("should inject synthetic tool results for orphaned tool calls", function()
      local provider = openai_chat._new_concrete()

      local prompt = {
        system = nil,
        history = {
          { role = "user", parts = { { kind = "text", text = "Hello" } } },
        },
        pending_tool_calls = {
          { id = "orphan_1", name = "missing_tool" },
        },
      }

      local request_body = provider:build_request(prompt)

      -- Find the synthetic tool message
      local tool_msg = nil
      for _, msg in ipairs(request_body.messages) do
        if msg.role == "tool" then
          tool_msg = msg
          break
        end
      end

      assert.is_not_nil(tool_msg, "Should inject synthetic tool result")
      assert.equals("orphan_1", tool_msg.tool_call_id)
      assert.equals("missing_tool", tool_msg.name)
      assert.truthy(tool_msg.content:match("Error"))
    end)

    it("should build tools in Chat Completions format when tools are registered", function()
      -- Tools are registered globally by Flemma's built-in tool definitions.
      -- Verify the format of whatever tools happen to be registered.
      local tools = require("flemma.tools")
      local all_tools = tools.get_all()
      if vim.tbl_isempty(all_tools) then
        -- Register a temporary tool so the test is not vacuous
        tools.register("test_tool_chat", {
          name = "test_tool_chat",
          description = "A test tool for Chat Completions format",
          input_schema = { type = "object", properties = { q = { type = "string" } } },
        })
      end

      local provider = openai_chat._new_concrete()
      local prompt = {
        system = nil,
        history = {
          { role = "user", parts = { { kind = "text", text = "Hello" } } },
        },
      }

      local request_body = provider:build_request(prompt)

      assert.is_not_nil(request_body.tools, "Should include tools array when tools are registered")
      assert.is_true(#request_body.tools > 0, "Tools array should not be empty")
      local tool = request_body.tools[1]
      assert.equals("function", tool.type, "Tool type should be 'function'")
      assert.is_not_nil(tool["function"], "Should have function field")
      assert.is_not_nil(tool["function"].name, "Function should have name")
      assert.is_not_nil(tool["function"].description, "Function should have description")
      assert.is_not_nil(tool["function"].parameters, "Function should have parameters")
    end)

    it("should set tool_choice auto when tools are present", function()
      local provider = openai_chat._new_concrete()
      local prompt = {
        system = nil,
        history = {
          { role = "user", parts = { { kind = "text", text = "Hello" } } },
        },
      }

      local request_body = provider:build_request(prompt)

      -- Built-in tools should be registered; if not, this test is skipped gracefully
      if request_body.tools and #request_body.tools > 0 then
        assert.equals("auto", request_body.tool_choice, "Should set tool_choice to auto")
      else
        -- No tools registered — tool_choice should not be set
        assert.is_nil(request_body.tool_choice, "Should not set tool_choice without tools")
      end
    end)

    it("should skip empty user messages", function()
      local provider = openai_chat._new_concrete()

      local prompt = {
        system = nil,
        history = {
          {
            role = "user",
            parts = {
              {
                kind = "tool_result",
                tool_use_id = "call_1",
                parts = { { kind = "text", text = "result" } },
                is_error = false,
              },
            },
          },
        },
      }

      local request_body = provider:build_request(prompt)

      -- Should have tool message but no empty user message
      local user_count = 0
      for _, msg in ipairs(request_body.messages) do
        if msg.role == "user" then
          user_count = user_count + 1
        end
      end
      assert.equals(0, user_count, "Should not add empty user message when only tool results exist")
    end)

    it("should handle text_file parts as text", function()
      local provider = openai_chat._new_concrete()

      local prompt = {
        system = nil,
        history = {
          {
            role = "user",
            parts = {
              { kind = "text_file", text = "file content here", mime_type = "text/plain", filename = "test.txt" },
            },
          },
        },
      }

      local request_body = provider:build_request(prompt)

      local user_msg = nil
      for _, msg in ipairs(request_body.messages) do
        if msg.role == "user" then
          user_msg = msg
          break
        end
      end

      assert.is_not_nil(user_msg)
      assert.equals("file content here", user_msg.content)
    end)

    it("should handle unsupported_file parts", function()
      local provider = openai_chat._new_concrete()

      local prompt = {
        system = nil,
        history = {
          {
            role = "user",
            parts = {
              { kind = "unsupported_file", filename = "data.bin" },
            },
          },
        },
      }

      local request_body = provider:build_request(prompt)

      local user_msg = nil
      for _, msg in ipairs(request_body.messages) do
        if msg.role == "user" then
          user_msg = msg
          break
        end
      end

      assert.is_not_nil(user_msg)
      assert.equals("@data.bin", user_msg.content)
    end)
  end)

  describe("get_trailing_keys", function()
    it("should return tools and messages", function()
      local provider = openai_chat._new_concrete()
      local keys = provider:get_trailing_keys()
      assert.same({ "tools", "messages" }, keys)
    end)
  end)

  describe("extension points", function()
    it("_max_tokens_key should return max_tokens by default", function()
      local provider = openai_chat._new_concrete()
      assert.equals("max_tokens", provider:_max_tokens_key())
    end)

    it("_thinking_provider_prefix should return nil by default", function()
      local provider = openai_chat._new_concrete()
      assert.is_nil(provider:_thinking_provider_prefix())
    end)

    it("_build_image_part should return standard image_url format", function()
      local provider = openai_chat._new_concrete()
      local part = {
        kind = "image",
        mime_type = "image/jpeg",
        data = "abc123",
        data_url = "data:image/jpeg;base64,abc123",
        filename = "photo.jpg",
      }
      local result = provider:_build_image_part(part)
      assert.equals("image_url", result.type)
      assert.equals("data:image/jpeg;base64,abc123", result.image_url.url)
    end)
  end)

  describe("process_response_line", function()
    describe("text streaming", function()
      it("should accumulate text content from hello fixture", function()
        local provider = openai_chat._new_concrete()
        local lines = vim.fn.readfile("tests/fixtures/chat_completions_hello_stream.txt")

        local accumulated_content = ""
        local completed = false
        local usage_events = {}

        local callbacks = {
          on_content = function(text)
            accumulated_content = accumulated_content .. text
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

        assert.is_true(#accumulated_content > 0, "Should accumulate content")
        assert.is_true(completed, "Should call on_response_complete")

        -- Verify usage
        local found_input = false
        local found_output = false
        for _, event in ipairs(usage_events) do
          if event.type == "input" then
            assert.is_true(event.tokens > 0, "Input tokens should be positive")
            found_input = true
          elseif event.type == "output" then
            assert.is_true(event.tokens > 0, "Output tokens should be positive")
            found_output = true
          end
        end
        assert.is_true(found_input, "Should emit input usage")
        assert.is_true(found_output, "Should emit output usage")
      end)

      it("should skip role-only delta markers", function()
        local provider = openai_chat._new_concrete()

        local accumulated_content = ""
        local callbacks = {
          on_content = function(text)
            accumulated_content = accumulated_content .. text
          end,
          on_usage = function() end,
          on_response_complete = function() end,
          on_error = function() end,
        }

        -- Role-only delta should be skipped
        provider:process_response_line(
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}',
          callbacks
        )

        assert.equals("", accumulated_content, "Role-only delta should not produce content")
      end)

      it("should handle empty content deltas", function()
        local provider = openai_chat._new_concrete()

        local accumulated_content = ""
        local callbacks = {
          on_content = function(text)
            accumulated_content = accumulated_content .. text
          end,
          on_usage = function() end,
          on_response_complete = function() end,
          on_error = function() end,
        }

        -- Empty content delta (common initial chunk)
        provider:process_response_line(
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}',
          callbacks
        )

        assert.equals("", accumulated_content, "Empty content delta should not produce content")
      end)
    end)

    describe("tool call streaming", function()
      it("should accumulate and emit tool calls from fixture", function()
        local provider = openai_chat._new_concrete()
        local lines = vim.fn.readfile("tests/fixtures/chat_completions_tool_call_stream.txt")

        local accumulated_content = ""
        local completed = false
        local tool_input_deltas = {}

        local callbacks = {
          on_content = function(text)
            accumulated_content = accumulated_content .. text
          end,
          on_usage = function() end,
          on_response_complete = function()
            completed = true
          end,
          on_error = function() end,
          on_tool_input = function(delta)
            table.insert(tool_input_deltas, delta)
          end,
        }

        for _, line in ipairs(lines) do
          provider:process_response_line(line, callbacks)
        end

        -- Should emit tool_use block
        assert.is_true(accumulated_content:find("%*%*Tool Use:%*%*") ~= nil, "Should emit tool_use header")
        assert.is_true(accumulated_content:find("search") ~= nil, "Should include tool name")
        assert.is_true(accumulated_content:find("search:0") ~= nil, "Should include tool call ID")

        -- Should have called on_tool_input for progress tracking
        assert.is_true(#tool_input_deltas > 0, "Should call on_tool_input for progress tracking")

        assert.is_true(completed, "Should call on_response_complete")
      end)

      it("should accumulate tool call arguments across chunks", function()
        local provider = openai_chat._new_concrete()

        local accumulated_content = ""
        local callbacks = {
          on_content = function(text)
            accumulated_content = accumulated_content .. text
          end,
          on_usage = function() end,
          on_response_complete = function() end,
          on_error = function() end,
        }

        -- First chunk: start tool call
        provider:process_response_line(
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"tc_1","type":"function","function":{"name":"calc","arguments":""}}]},"finish_reason":null}]}',
          callbacks
        )

        -- Second chunk: partial arguments
        provider:process_response_line(
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"x\\""}}]},"finish_reason":null}]}',
          callbacks
        )

        -- Third chunk: rest of arguments
        provider:process_response_line(
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":": 1}"}}]},"finish_reason":null}]}',
          callbacks
        )

        -- Finish with tool_calls
        provider:process_response_line(
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',
          callbacks
        )

        assert.is_true(accumulated_content:find("calc") ~= nil, "Should include tool name")
        assert.is_true(accumulated_content:find("tc_1") ~= nil, "Should include tool call ID")
      end)

      it("should handle parallel tool calls with different indices", function()
        local provider = openai_chat._new_concrete()

        local accumulated_content = ""
        local callbacks = {
          on_content = function(text)
            accumulated_content = accumulated_content .. text
          end,
          on_usage = function() end,
          on_response_complete = function() end,
          on_error = function() end,
        }

        -- First chunk: start two tool calls at different indices
        provider:process_response_line(
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"search:0","type":"function","function":{"name":"search","arguments":""}},{"index":1,"id":"read:1","type":"function","function":{"name":"read","arguments":""}}]},"finish_reason":null}]}',
          callbacks
        )

        -- Second chunk: arguments for index 0
        provider:process_response_line(
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"query\\": \\"test\\"}"}}]},"finish_reason":null}]}',
          callbacks
        )

        -- Third chunk: arguments for index 1
        provider:process_response_line(
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{"tool_calls":[{"index":1,"function":{"arguments":"{\\"path\\": \\"./file.txt\\"}"}}]},"finish_reason":null}]}',
          callbacks
        )

        -- Finish with tool_calls
        provider:process_response_line(
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',
          callbacks
        )

        -- Both tool calls should be emitted
        assert.is_true(accumulated_content:find("search") ~= nil, "Should include first tool name")
        assert.is_true(accumulated_content:find("search:0") ~= nil, "Should include first tool ID")
        assert.is_true(accumulated_content:find("read") ~= nil, "Should include second tool name")
        assert.is_true(accumulated_content:find("read:1") ~= nil, "Should include second tool ID")
        assert.is_true(accumulated_content:find("query") ~= nil, "Should include first tool arguments")
        assert.is_true(accumulated_content:find("path") ~= nil, "Should include second tool arguments")
      end)
    end)

    describe("thinking/reasoning streaming", function()
      it("should accumulate reasoning_content and emit thinking block from fixture", function()
        local provider = openai_chat._new_concrete()
        local lines = vim.fn.readfile("tests/fixtures/chat_completions_thinking_stream.txt")

        local accumulated_content = ""
        local thinking_deltas = {}
        local completed = false

        local callbacks = {
          on_content = function(text)
            accumulated_content = accumulated_content .. text
          end,
          on_thinking = function(text)
            table.insert(thinking_deltas, text)
          end,
          on_usage = function() end,
          on_response_complete = function()
            completed = true
          end,
          on_error = function() end,
        }

        for _, line in ipairs(lines) do
          provider:process_response_line(line, callbacks)
        end

        -- Should have received thinking deltas
        assert.is_true(#thinking_deltas > 0, "Should receive on_thinking callbacks")
        local thinking_text = table.concat(thinking_deltas, "")
        assert.is_true(#thinking_text > 0, "Should accumulate reasoning content")

        -- Should contain text response with the actual answer (17 * 23 = 391)
        assert.is_true(#accumulated_content > 0, "Should contain text response")
        assert.is_true(accumulated_content:find("391") ~= nil, "Should contain the answer 391")

        -- Should contain a thinking block in the emitted content
        assert.is_true(
          accumulated_content:find("<thinking>") ~= nil,
          "Should contain thinking block in emitted content"
        )

        assert.is_true(completed, "Should call on_response_complete")
      end)

      it("should not emit thinking block when no reasoning_content received", function()
        local provider = openai_chat._new_concrete()

        local accumulated_content = ""
        local callbacks = {
          on_content = function(text)
            accumulated_content = accumulated_content .. text
          end,
          on_usage = function() end,
          on_response_complete = function() end,
          on_error = function() end,
        }

        -- Simple text response without reasoning
        provider:process_response_line(
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}',
          callbacks
        )
        provider:process_response_line(
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}',
          callbacks
        )

        assert.is_nil(accumulated_content:find("<thinking>"), "Should NOT contain thinking block")
      end)
    end)

    describe("usage extraction", function()
      it("should extract usage from finish_reason chunk", function()
        local provider = openai_chat._new_concrete()

        local usage_events = {}
        local callbacks = {
          on_content = function() end,
          on_usage = function(data)
            table.insert(usage_events, data)
          end,
          on_response_complete = function() end,
          on_error = function() end,
        }

        provider:process_response_line(
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{},"finish_reason":"stop","usage":{"prompt_tokens":50,"completion_tokens":20,"total_tokens":70}}]}',
          callbacks
        )

        local found_input = false
        local found_output = false
        for _, event in ipairs(usage_events) do
          if event.type == "input" then
            assert.equals(50, event.tokens)
            found_input = true
          elseif event.type == "output" then
            assert.equals(20, event.tokens)
            found_output = true
          end
        end
        assert.is_true(found_input, "Should emit input usage")
        assert.is_true(found_output, "Should emit output usage")
      end)

      it("should extract usage from final empty-choices chunk", function()
        local provider = openai_chat._new_concrete()

        local usage_events = {}
        local callbacks = {
          on_content = function() end,
          on_usage = function(data)
            table.insert(usage_events, data)
          end,
          on_response_complete = function() end,
          on_error = function() end,
        }

        -- Final chunk with empty choices and top-level usage
        provider:process_response_line(
          'data: {"id":"cmpl-1","choices":[],"usage":{"prompt_tokens":100,"completion_tokens":50,"total_tokens":150}}',
          callbacks
        )

        local found_input = false
        local found_output = false
        for _, event in ipairs(usage_events) do
          if event.type == "input" then
            assert.equals(100, event.tokens)
            found_input = true
          elseif event.type == "output" then
            assert.equals(50, event.tokens)
            found_output = true
          end
        end
        assert.is_true(found_input, "Should emit input usage from final chunk")
        assert.is_true(found_output, "Should emit output usage from final chunk")
      end)

      it("should extract cached_tokens and subtract from input", function()
        local provider = openai_chat._new_concrete()

        local usage_events = {}
        local callbacks = {
          on_content = function() end,
          on_usage = function(data)
            table.insert(usage_events, data)
          end,
          on_response_complete = function() end,
          on_error = function() end,
        }

        provider:process_response_line(
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{},"finish_reason":"stop","usage":{"prompt_tokens":200,"completion_tokens":30,"total_tokens":230,"cached_tokens":150}}]}',
          callbacks
        )

        local found_input = false
        local found_cache_read = false
        for _, event in ipairs(usage_events) do
          if event.type == "input" then
            assert.equals(50, event.tokens, "Input should be prompt_tokens minus cached_tokens")
            found_input = true
          elseif event.type == "cache_read" then
            assert.equals(150, event.tokens)
            found_cache_read = true
          end
        end
        assert.is_true(found_input, "Should emit input usage")
        assert.is_true(found_cache_read, "Should emit cache_read usage")
      end)

      it("should not emit cache_read when cached_tokens is zero", function()
        local provider = openai_chat._new_concrete()

        local usage_events = {}
        local callbacks = {
          on_content = function() end,
          on_usage = function(data)
            table.insert(usage_events, data)
          end,
          on_response_complete = function() end,
          on_error = function() end,
        }

        provider:process_response_line(
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{},"finish_reason":"stop","usage":{"prompt_tokens":50,"completion_tokens":10,"total_tokens":60,"cached_tokens":0}}]}',
          callbacks
        )

        for _, event in ipairs(usage_events) do
          assert.is_not.equals("cache_read", event.type, "Should not emit cache_read for zero cached tokens")
        end
      end)

      it("should not emit thoughts usage (no reasoning_tokens field)", function()
        local provider = openai_chat._new_concrete()

        local usage_events = {}
        local callbacks = {
          on_content = function() end,
          on_usage = function(data)
            table.insert(usage_events, data)
          end,
          on_response_complete = function() end,
          on_error = function() end,
        }

        provider:process_response_line(
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{},"finish_reason":"stop","usage":{"prompt_tokens":50,"completion_tokens":10,"total_tokens":60}}]}',
          callbacks
        )

        for _, event in ipairs(usage_events) do
          assert.is_not.equals("thoughts", event.type, "Should NOT emit thoughts usage")
        end
      end)

      it("should not emit usage twice when both finish_reason chunk and final chunk have usage", function()
        local provider = openai_chat._new_concrete()

        local usage_events = {}
        local callbacks = {
          on_content = function() end,
          on_usage = function(data)
            table.insert(usage_events, data)
          end,
          on_response_complete = function() end,
          on_error = function() end,
        }

        -- Finish chunk with usage (location 1)
        provider:process_response_line(
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{},"finish_reason":"stop","usage":{"prompt_tokens":50,"completion_tokens":10,"total_tokens":60}}]}',
          callbacks
        )

        -- Final empty-choices chunk with same usage (location 2)
        provider:process_response_line(
          'data: {"id":"cmpl-1","choices":[],"usage":{"prompt_tokens":50,"completion_tokens":10,"total_tokens":60}}',
          callbacks
        )

        -- Should emit exactly one input and one output event, not two of each
        local input_count = 0
        local output_count = 0
        for _, event in ipairs(usage_events) do
          if event.type == "input" then
            input_count = input_count + 1
          elseif event.type == "output" then
            output_count = output_count + 1
          end
        end
        assert.equals(1, input_count, "Should emit input usage exactly once")
        assert.equals(1, output_count, "Should emit output usage exactly once")
      end)
    end)

    describe("finish_reason handling", function()
      it("should call on_response_complete for stop", function()
        local provider = openai_chat._new_concrete()

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
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}',
          callbacks
        )

        assert.is_true(completed)
      end)

      it("should call on_response_complete for tool_calls", function()
        local provider = openai_chat._new_concrete()

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
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}',
          callbacks
        )

        assert.is_true(completed)
      end)

      it("should warn on length finish_reason", function()
        local provider = openai_chat._new_concrete()

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
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{},"finish_reason":"length"}]}',
          callbacks
        )

        -- _warn_truncated calls on_response_complete
        assert.is_true(completed, "Should call on_response_complete via _warn_truncated")
      end)

      it("should signal blocked for content_filter finish_reason", function()
        local provider = openai_chat._new_concrete()

        local errors = {}
        local callbacks = {
          on_content = function() end,
          on_usage = function() end,
          on_response_complete = function() end,
          on_error = function(msg)
            table.insert(errors, msg)
          end,
        }

        provider:process_response_line(
          'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{},"finish_reason":"content_filter"}]}',
          callbacks
        )

        assert.equals(1, #errors)
        assert.truthy(errors[1]:match("content_filter"))
      end)
    end)

    describe("SSE edge cases", function()
      it("should handle [DONE] message", function()
        local provider = openai_chat._new_concrete()

        local callbacks = {
          on_content = function() end,
          on_usage = function() end,
          on_response_complete = function() end,
          on_error = function() end,
        }

        -- Should not error
        provider:process_response_line("data: [DONE]", callbacks)
      end)

      it("should handle empty lines", function()
        local provider = openai_chat._new_concrete()

        local callbacks = {
          on_content = function() end,
          on_usage = function() end,
          on_response_complete = function() end,
          on_error = function() end,
        }

        -- Should not error
        provider:process_response_line("", callbacks)
      end)

      it("should handle event: lines", function()
        local provider = openai_chat._new_concrete()

        local callbacks = {
          on_content = function() end,
          on_usage = function() end,
          on_response_complete = function() end,
          on_error = function() end,
        }

        -- Should not error or produce output
        provider:process_response_line("event: some_event", callbacks)
      end)

      it("should detect error responses via base _is_error_response", function()
        local provider = openai_chat._new_concrete()

        local errors = {}
        local callbacks = {
          on_content = function() end,
          on_usage = function() end,
          on_response_complete = function() end,
          on_error = function(msg)
            table.insert(errors, msg)
          end,
        }

        provider:process_response_line(
          'data: {"error":{"message":"Rate limit exceeded","type":"rate_limit_error"}}',
          callbacks
        )

        assert.equals(1, #errors)
        assert.truthy(errors[1]:match("Rate limit exceeded"))
      end)
    end)
  end)
end)
