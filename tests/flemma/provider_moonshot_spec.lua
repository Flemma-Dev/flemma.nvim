--- Test file for Moonshot AI provider functionality
describe("Moonshot Provider", function()
  local moonshot = require("flemma.provider.adapters.moonshot")
  local make_prompt = require("tests.utilities.prompt").make_prompt

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  describe("metadata", function()
    it("should have correct name", function()
      assert.equals("moonshot", moonshot.metadata.name)
    end)

    it("should have correct display name", function()
      assert.equals("Moonshot AI", moonshot.metadata.display_name)
    end)

    it("should support thinking budget but not reasoning", function()
      assert.is_false(moonshot.metadata.capabilities.supports_reasoning)
      assert.is_true(moonshot.metadata.capabilities.supports_thinking_budget)
    end)

    it("should output thinking but not include thoughts in output tokens", function()
      assert.is_true(moonshot.metadata.capabilities.outputs_thinking)
      assert.is_false(moonshot.metadata.capabilities.output_has_thoughts)
    end)

    it("should not have a thinking field in config_schema (uses global parameters.thinking)", function()
      -- Regression: a moonshot-specific thinking default of "enabled" caused
      -- resolve_thinking to produce level="enabled" which is not a canonical level.
      -- Moonshot relies on the global parameters.thinking for thinking control.
      local schema = moonshot.metadata.config_schema
      assert.is_not_nil(schema)
      -- The schema should have prompt_cache_key but NOT thinking
      -- Schema objects store fields in _fields (internal representation)
      local child = schema:get_child_schema("thinking")
      assert.is_nil(child, "config_schema must not override the global thinking parameter")
    end)
  end)

  describe("new", function()
    it("should set the correct endpoint", function()
      local provider = moonshot.new({ model = "kimi-k2.5", max_tokens = 4096 })
      assert.equals("https://api.moonshot.ai/v1/chat/completions", provider.endpoint)
    end)

    it("should initialize response buffer with tool_calls and thinking_sink", function()
      local provider = moonshot.new({ model = "kimi-k2.5", max_tokens = 4096 })
      assert.is_not_nil(provider._response_buffer)
      assert.is_not_nil(provider._response_buffer.extra.tool_calls)
      assert.is_not_nil(provider._response_buffer.extra.thinking_sink)
    end)

    it("should store parameters", function()
      local provider = moonshot.new({ model = "kimi-k2.5", max_tokens = 8192, temperature = 0.7 })
      assert.equals("kimi-k2.5", provider.parameters.model)
      assert.equals(8192, provider.parameters.max_tokens)
      assert.equals(0.7, provider.parameters.temperature)
    end)
  end)

  describe("get_credential", function()
    it("should return moonshot API key credential", function()
      local provider = moonshot.new({ model = "kimi-k2.5", max_tokens = 4096 })
      local credential = provider:get_credential()
      assert.equals("api_key", credential.kind)
      assert.equals("moonshot", credential.service)
      assert.equals("Moonshot API key", credential.description)
    end)
  end)

  describe("extension points", function()
    it("_max_tokens_key should inherit max_tokens default from openai_chat", function()
      local provider = moonshot.new({ model = "kimi-k2.5", max_tokens = 4096 })
      assert.equals("max_tokens", provider:_max_tokens_key())
    end)
  end)

  describe("build_request", function()
    it("should use max_tokens key", function()
      local provider = moonshot.new({ model = "kimi-k2.5", max_tokens = 4096 })
      local prompt = make_prompt({ { type = "You", content = "Hello" } })
      local request_body = provider:build_request(prompt)

      assert.equals(4096, request_body.max_tokens)
      assert.is_nil(request_body.max_output_tokens)
      assert.is_nil(request_body.max_completion_tokens)
    end)

    it("should include model and stream settings", function()
      local provider = moonshot.new({ model = "kimi-k2.5", max_tokens = 4096 })
      local prompt = make_prompt({ { type = "You", content = "Hello" } })
      local request_body = provider:build_request(prompt)

      assert.equals("kimi-k2.5", request_body.model)
      assert.equals(true, request_body.stream)
      assert.is_not_nil(request_body.stream_options)
    end)

    it("should add prompt_cache_key when present in parameters", function()
      local provider = moonshot.new({
        model = "kimi-k2.5",
        max_tokens = 4096,
        prompt_cache_key = "my-cache-key",
      })
      local prompt = make_prompt({ { type = "You", content = "Hello" } })
      local request_body = provider:build_request(prompt)

      assert.equals("my-cache-key", request_body.prompt_cache_key)
    end)

    it("should not add prompt_cache_key when absent from parameters", function()
      local provider = moonshot.new({ model = "kimi-k2.5", max_tokens = 4096 })
      local prompt = make_prompt({ { type = "You", content = "Hello" } })
      local request_body = provider:build_request(prompt)

      assert.is_nil(request_body.prompt_cache_key)
    end)

    describe("thinking for kimi-k2.5", function()
      it("should enable thinking when thinking param is set", function()
        local provider = moonshot.new({
          model = "kimi-k2.5",
          max_tokens = 4096,
          thinking = { level = "enabled", foreign = "preserve" },
        })
        local prompt = make_prompt({ { type = "You", content = "Think about this" } })
        local request_body = provider:build_request(prompt)

        assert.is_not_nil(request_body.thinking)
        assert.equals("enabled", request_body.thinking.type)
        assert.equals(1.0, request_body.temperature)
      end)

      it("should disable thinking and set temperature 0.6 when thinking not configured", function()
        local provider = moonshot.new({
          model = "kimi-k2.5",
          max_tokens = 4096,
        })
        local prompt = make_prompt({ { type = "You", content = "Hello" } })
        local request_body = provider:build_request(prompt)

        assert.is_not_nil(request_body.thinking)
        assert.equals("disabled", request_body.thinking.type)
        assert.equals(0.6, request_body.temperature)
      end)

      it("should lock temperature to 1.0 when thinking is on", function()
        local provider = moonshot.new({
          model = "kimi-k2.5",
          max_tokens = 4096,
          temperature = 0.3,
          thinking = { level = "high", foreign = "preserve" },
        })
        local prompt = make_prompt({ { type = "You", content = "Hello" } })
        local request_body = provider:build_request(prompt)

        assert.equals(1.0, request_body.temperature, "Temperature should be locked to 1.0 with thinking")
      end)

      it("should lock temperature to 0.6 when thinking is off", function()
        local provider = moonshot.new({
          model = "kimi-k2.5",
          max_tokens = 4096,
          temperature = 0.3,
        })
        local prompt = make_prompt({ { type = "You", content = "Hello" } })
        local request_body = provider:build_request(prompt)

        assert.equals(0.6, request_body.temperature, "Temperature should be locked to 0.6 without thinking")
      end)
    end)

    describe("reasoning_effort for kimi-k3", function()
      --- Build a kimi-k3 request body with the given unified thinking value.
      ---@param thinking? table The `thinking` parameter table (nil = not configured)
      ---@return table<string, any> request_body
      local function build_k3(thinking)
        local provider = moonshot.new({
          model = "kimi-k3",
          max_tokens = 16000,
          thinking = thinking,
        })
        return provider:build_request(make_prompt({ { type = "You", content = "Hello" } }))
      end

      it("should map every canonical thinking level to an API reasoning_effort", function()
        -- K3 accepts only low/high/max — "minimal" and "medium" clamp to a real value.
        local expected = {
          minimal = "low",
          low = "low",
          medium = "high",
          high = "high",
          max = "max",
        }
        for level, effort in pairs(expected) do
          local request_body = build_k3({ level = level, foreign = "preserve" })
          assert.equals(effort, request_body.reasoning_effort, "thinking=" .. level .. " should send " .. effort)
        end
      end)

      it("should never send a thinking object for kimi-k3", function()
        -- K3 rejects the K2-family `thinking` parameter.
        for _, level in ipairs({ "minimal", "low", "medium", "high", "max" }) do
          local request_body = build_k3({ level = level, foreign = "preserve" })
          assert.is_nil(request_body.thinking, "thinking=" .. level .. " must not send a thinking object")
        end
        assert.is_nil(build_k3(nil).thinking)
        assert.is_nil(build_k3({ level = false, foreign = "preserve" }).thinking)
      end)

      it("should send the floor effort when thinking is explicitly disabled", function()
        -- K3 cannot stop reasoning; "low" is the closest honest reading of
        -- "as little thinking as possible".
        local request_body = build_k3({ level = false, foreign = "preserve" })
        assert.equals("low", request_body.reasoning_effort)
      end)

      it("should send the floor effort when the resolution carries no thinking table", function()
        -- The budget branch of resolve_thinking cannot distinguish "explicitly
        -- disabled" from "absent" — both produce the same request. Note this is the
        -- provider-level contract, not the end-user default: the config schema
        -- defaults `thinking.level` to "high", so a user who never configures
        -- thinking sends `reasoning_effort = "high"`, not the floor.
        local request_body = build_k3(nil)
        assert.equals("low", request_body.reasoning_effort)
      end)

      it("should map a numeric thinking budget through the effort map", function()
        -- Numeric budgets resolve to a canonical level first, then through the map.
        local request_body = build_k3({ level = 20000, foreign = "preserve" })
        assert.equals("high", request_body.reasoning_effort)
      end)

      it("should lock temperature to 1.0 regardless of what the user set", function()
        -- Moonshot fixes K3's temperature at 1.0; any other value returns an error.
        local provider = moonshot.new({
          model = "kimi-k3",
          max_tokens = 16000,
          temperature = 0.3,
          thinking = { level = "high", foreign = "preserve" },
        })
        local request_body = provider:build_request(make_prompt({ { type = "You", content = "Hello" } }))

        assert.equals(1.0, request_body.temperature)
        assert.equals(1.0, build_k3(nil).temperature, "the lock applies even when the user sets nothing")
      end)

      it("should not send reasoning_effort for thinking-toggle models", function()
        local provider = moonshot.new({
          model = "kimi-k2.5",
          max_tokens = 4096,
          thinking = { level = "high", foreign = "preserve" },
        })
        local request_body = provider:build_request(make_prompt({ { type = "You", content = "Hello" } }))

        assert.is_nil(request_body.reasoning_effort)
        assert.equals("enabled", request_body.thinking.type)
      end)
    end)

    describe("forced thinking for the kimi-k2.7-code family", function()
      --- Build a k2.7-code request body with the given unified thinking value.
      ---@param model string The k2.7-code variant to build for
      ---@param thinking? table The `thinking` parameter table (nil = not configured)
      ---@return table<string, any> request_body
      local function build_k27(model, thinking)
        local provider = moonshot.new({ model = model, max_tokens = 16000, thinking = thinking })
        return provider:build_request(make_prompt({ { type = "You", content = "Hello" } }))
      end

      for _, model in ipairs({ "kimi-k2.7-code", "kimi-k2.7-code-highspeed" }) do
        it("should never send a thinking object for " .. model, function()
          -- Thinking is always on server-side. `{"type":"disabled"}` errors outright,
          -- and the only explicitly accepted form is `{"type":"enabled","keep":"all"}`,
          -- so omitting the object is the one form the docs agree on.
          assert.is_nil(build_k27(model, nil).thinking)
          assert.is_nil(build_k27(model, { level = "high", foreign = "preserve" }).thinking)
          assert.is_nil(build_k27(model, { level = false, foreign = "preserve" }).thinking)
        end)

        it("should lock temperature to 1.0 for " .. model, function()
          assert.equals(1.0, build_k27(model, { level = false, foreign = "preserve" }).temperature)
          assert.equals(1.0, build_k27(model, { level = "high", foreign = "preserve" }).temperature)
        end)

        it("should not send reasoning_effort for " .. model, function()
          -- reasoning_effort is K3-only; K2.x rejects it.
          assert.is_nil(build_k27(model, { level = "max", foreign = "preserve" }).reasoning_effort)
        end)
      end
    end)

    describe("no thinking for moonshot-v1 models", function()
      it("should not set thinking for moonshot-v1-128k", function()
        local provider = moonshot.new({
          model = "moonshot-v1-128k",
          max_tokens = 4096,
        })
        local prompt = make_prompt({ { type = "You", content = "Hello" } })
        local request_body = provider:build_request(prompt)

        assert.is_nil(request_body.thinking, "moonshot-v1 models should not have thinking parameter")
      end)

      it("should not set thinking for moonshot-v1-8k", function()
        local provider = moonshot.new({
          model = "moonshot-v1-8k",
          max_tokens = 4096,
        })
        local prompt = make_prompt({ { type = "You", content = "Hello" } })
        local request_body = provider:build_request(prompt)

        assert.is_nil(request_body.thinking, "moonshot-v1 models should not have thinking parameter")
      end)
    end)
  end)

  describe("is_context_overflow", function()
    it("should detect moonshot-specific overflow patterns", function()
      local provider = moonshot.new({ model = "kimi-k2.5", max_tokens = 4096 })

      assert.is_true(provider:is_context_overflow("input token length too long"))
      assert.is_true(provider:is_context_overflow("Your request exceeded model token limit"))
    end)

    it("should detect base overflow patterns", function()
      local provider = moonshot.new({ model = "kimi-k2.5", max_tokens = 4096 })

      assert.is_true(provider:is_context_overflow("prompt is too long: 100000 tokens > 65536 maximum"))
      assert.is_true(provider:is_context_overflow("exceeds the context window"))
      assert.is_true(provider:is_context_overflow("maximum context length"))
    end)

    it("should return false for non-overflow errors", function()
      local provider = moonshot.new({ model = "kimi-k2.5", max_tokens = 4096 })

      assert.is_false(provider:is_context_overflow("rate limit exceeded"))
      assert.is_false(provider:is_context_overflow("invalid API key"))
      assert.is_false(provider:is_context_overflow(nil))
    end)
  end)

  describe("validate_parameters", function()
    it("should return no warnings for non-kimi-k2.5 models", function()
      local ok, warnings = moonshot.validate_parameters("moonshot-v1-128k", { temperature = 0.3 })
      assert.is_true(ok)
      assert.is_nil(warnings)
    end)

    it("should warn about fixed sampling parameters on kimi-k3", function()
      -- Moonshot fixes temperature (1.0), top_p (0.95), n and both penalties on K3
      -- exactly as it does on the K2 line; passing anything else returns an error.
      local ok, warnings = moonshot.validate_parameters("kimi-k3", { temperature = 0.3, top_p = 0.5 })
      assert.is_true(ok)
      assert.is_not_nil(warnings)
      assert.equals(2, #warnings)
      assert.matches("temperature will be locked to 1.0", warnings[1])
      assert.matches("top_p will be fixed to 0.95", warnings[2])
    end)

    it("should warn about fixed sampling parameters on kimi-k2.7-code", function()
      local ok, warnings = moonshot.validate_parameters("kimi-k2.7-code", { temperature = 0.3 })
      assert.is_true(ok)
      assert.is_not_nil(warnings)
      assert.matches("temperature will be locked to 1.0", warnings[1])
    end)

    it("should return warnings for explicitly conflicting kimi-k2.5 parameters", function()
      local ok, warnings = moonshot.validate_parameters("kimi-k2.5", {
        temperature = 0.3,
        top_p = 0.5,
        n = 2,
        presence_penalty = 0.1,
        frequency_penalty = 0.1,
      })
      assert.is_true(ok)
      assert.is_not_nil(warnings)
      assert.equals(5, #warnings)
    end)

    it("should not warn when parameters match kimi-k2.5 fixed values", function()
      local ok, warnings = moonshot.validate_parameters("kimi-k2.5", {
        temperature = 0.6,
        top_p = 0.95,
        n = 1,
        presence_penalty = 0.0,
        frequency_penalty = 0.0,
      })
      assert.is_true(ok)
      assert.is_nil(warnings)
    end)

    it("should not warn when parameters are at Flemma defaults", function()
      -- temperature=nil (no default) is not user-intentional
      local ok, warnings = moonshot.validate_parameters("kimi-k2.5", {})
      assert.is_true(ok)
      assert.is_nil(warnings)
    end)
  end)

  describe("streaming (metatable chain)", function()
    it("should process SSE lines through the full moonshot->openai_chat->base chain", function()
      -- Regression: verify the three-level metatable chain resolves process_response_line
      -- and _process_data correctly when invoked on a moonshot-created instance.
      local provider = moonshot.new({ model = "kimi-k2.5", max_tokens = 4096 })

      local accumulated_content = ""
      local completed = false
      local callbacks = {
        on_content = function(text)
          accumulated_content = accumulated_content .. text
        end,
        on_usage = function() end,
        on_response_complete = function()
          completed = true
        end,
        on_error = function() end,
      }

      provider:process_response_line(
        'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}',
        callbacks
      )
      provider:process_response_line(
        'data: {"id":"cmpl-1","choices":[{"index":0,"delta":{},"finish_reason":"stop","usage":{"prompt_tokens":10,"completion_tokens":1,"total_tokens":11}}]}',
        callbacks
      )

      assert.equals("Hello", accumulated_content)
      assert.is_true(completed)
    end)
  end)

  describe("multi-turn thinking persistence (E2E)", function()
    local parser = require("flemma.parser")
    local pipeline = require("flemma.pipeline")
    local ctx = require("flemma.context")

    it("should preserve reasoning_content from buffer <thinking> blocks in multi-turn", function()
      -- E2E: parse real buffer text through AST → pipeline → build_request and verify
      -- reasoning_content survives the full chain. Unlike Anthropic/OpenAI which strip
      -- thinking without provider-specific signatures, Moonshot REQUIRES the full text.
      local provider =
        moonshot.new({ model = "kimi-k2.5", max_tokens = 32768, thinking = { level = "high", foreign = "preserve" } })

      local lines = {
        "@You:",
        "What is 17 * 23?",
        "",
        "@Assistant:",
        "The answer is 391.",
        "",
        "<thinking>",
        "Let me calculate step by step.",
        "17 * 23 = 17 * 20 + 17 * 3 = 340 + 51 = 391",
        "</thinking>",
        "",
        "@You:",
        "Now multiply that by 2.",
        "",
      }

      local doc = parser.parse_lines(lines)
      local prompt = pipeline.run(doc, ctx.from_file("test.chat"), { bufnr = 0 })
      local body = provider:build_request(prompt)

      -- Find the assistant message in the request
      local assistant_msg = nil
      for _, msg in ipairs(body.messages) do
        if msg.role == "assistant" then
          assistant_msg = msg
          break
        end
      end

      assert.is_not_nil(assistant_msg, "Request should contain the assistant message")
      assert.equals("The answer is 391.", vim.trim(assistant_msg.content))

      -- THE CRITICAL ASSERTION: reasoning_content MUST be present from <thinking> block
      assert.is_not_nil(
        assistant_msg.reasoning_content,
        "Moonshot requires reasoning_content from <thinking> blocks for multi-turn"
      )
      assert.is_true(
        assistant_msg.reasoning_content:find("391") ~= nil,
        "reasoning_content should contain the full thinking text"
      )
    end)

    it("should preserve reasoning_content alongside tool_calls from buffer", function()
      -- E2E: multi-step tool calling with thinking — parse from buffer format
      local provider =
        moonshot.new({ model = "kimi-k2.5", max_tokens = 32768, thinking = { level = "high", foreign = "preserve" } })

      local lines = {
        "@You:",
        "Search for the weather in Tokyo.",
        "",
        "@Assistant:",
        "",
        "<thinking>",
        "I need to search for current weather data.",
        "</thinking>",
        "",
        "**Tool Use:** `search` (`search:0`)",
        "",
        "```json",
        '{"query": "weather Tokyo"}',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `search:0`",
        "",
        "```",
        "Sunny, 25°C",
        "```",
        "",
        "What did you find?",
        "",
      }

      local doc = parser.parse_lines(lines)
      local prompt = pipeline.run(doc, ctx.from_file("test.chat"), { bufnr = 0 })
      local body = provider:build_request(prompt)

      -- Find the assistant message
      local assistant_msg = nil
      for _, msg in ipairs(body.messages) do
        if msg.role == "assistant" then
          assistant_msg = msg
          break
        end
      end

      assert.is_not_nil(assistant_msg, "Request should contain assistant message")
      assert.is_not_nil(assistant_msg.tool_calls, "Should have tool_calls")
      assert.equals(1, #assistant_msg.tool_calls)
      assert.equals("search", assistant_msg.tool_calls[1]["function"].name)

      -- Tool result should have the name resolved by the pipeline
      local tool_result_msg = nil
      for _, msg in ipairs(body.messages) do
        if msg.role == "tool" then
          tool_result_msg = msg
          break
        end
      end
      assert.is_not_nil(tool_result_msg, "Should have a tool result message")
      assert.equals("search", tool_result_msg.name, "Tool result name should be resolved from matching tool_use")
      assert.equals("search:0", tool_result_msg.tool_call_id)

      -- reasoning_content MUST coexist with tool_calls
      assert.is_not_nil(
        assistant_msg.reasoning_content,
        "reasoning_content must be preserved alongside tool_calls from buffer <thinking> blocks"
      )
      assert.equals(
        "I need to search for current weather data.",
        vim.trim(assistant_msg.reasoning_content),
        "reasoning_content should contain the exact thinking block text"
      )
    end)

    it("should NOT have reasoning_content when buffer has no <thinking> blocks", function()
      local provider = moonshot.new({ model = "kimi-k2.5", max_tokens = 4096 })

      local lines = {
        "@You:",
        "Hello",
        "",
        "@Assistant:",
        "Hi there!",
        "",
        "@You:",
        "How are you?",
        "",
      }

      local doc = parser.parse_lines(lines)
      local prompt = pipeline.run(doc, ctx.from_file("test.chat"), { bufnr = 0 })
      local body = provider:build_request(prompt)

      local assistant_msg = nil
      for _, msg in ipairs(body.messages) do
        if msg.role == "assistant" then
          assistant_msg = msg
          break
        end
      end

      assert.is_not_nil(assistant_msg)
      assert.is_nil(assistant_msg.reasoning_content, "Should not add reasoning_content without <thinking> blocks")
    end)
  end)
end)
