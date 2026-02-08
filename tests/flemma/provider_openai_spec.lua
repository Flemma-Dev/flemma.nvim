--- Test file for OpenAI provider functionality
describe("OpenAI Provider", function()
  local openai = require("flemma.provider.providers.openai")

  after_each(function()
    -- Clean up any buffers created during the test
    vim.cmd("silent! %bdelete!")
  end)

  describe("build_request", function()
    it("should use max_completion_tokens for all OpenAI models", function()
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

        -- Verify max_completion_tokens is used (not max_tokens)
        assert.is_not_nil(
          request_body.max_completion_tokens,
          string.format("Model %s should use max_completion_tokens", test_case.model)
        )
        assert.equals(
          test_case.max_tokens,
          request_body.max_completion_tokens,
          string.format("Model %s should have correct max_completion_tokens value", test_case.model)
        )
        assert.is_nil(
          request_body.max_tokens,
          string.format("Model %s should NOT use deprecated max_tokens", test_case.model)
        )
      end
    end)

    it("should set reasoning_effort for o-series models with reasoning parameter", function()
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

      assert.equals(4000, request_body.max_completion_tokens)
      assert.equals("high", request_body.reasoning_effort)
      assert.is_nil(request_body.temperature) -- No temperature with reasoning
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

      assert.equals(1000, request_body.max_completion_tokens)
      assert.equals(0.5, request_body.temperature)
      assert.is_nil(request_body.reasoning_effort)
    end)
  end)

  describe("process_response_line", function()
    it("should parse cached tokens from usage response", function()
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

      -- Simulate a final chunk with usage that includes cached tokens
      local usage_line = 'data: {"id":"chatcmpl-abc","choices":[],"usage":'
        .. '{"prompt_tokens":1500,"completion_tokens":200,'
        .. '"prompt_tokens_details":{"cached_tokens":1024},'
        .. '"completion_tokens_details":{"reasoning_tokens":0}}}'
      provider:process_response_line(usage_line, callbacks)

      -- Should have received input, output, and cache_read usage events
      assert.is_true(#usage_events >= 3, "Expected at least 3 usage events, got " .. #usage_events)

      local found_input = false
      local found_output = false
      local found_cache_read = false
      for _, event in ipairs(usage_events) do
        if event.type == "input" then
          assert.equals(1500, event.tokens)
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

      -- Simulate a final chunk with zero cached tokens
      local usage_line = 'data: {"id":"chatcmpl-abc","choices":[],"usage":'
        .. '{"prompt_tokens":500,"completion_tokens":100,'
        .. '"prompt_tokens_details":{"cached_tokens":0},'
        .. '"completion_tokens_details":{"reasoning_tokens":0}}}'
      provider:process_response_line(usage_line, callbacks)

      -- Should NOT have a cache_read event
      for _, event in ipairs(usage_events) do
        assert.is_not.equals("cache_read", event.type, "Should not emit cache_read for zero cached tokens")
      end
    end)

    it("should handle missing prompt_tokens_details gracefully", function()
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

      -- Simulate a final chunk without prompt_tokens_details
      local usage_line = 'data: {"id":"chatcmpl-abc","choices":[],"usage":'
        .. '{"prompt_tokens":500,"completion_tokens":100}}'
      provider:process_response_line(usage_line, callbacks)

      -- Should have input and output but no cache_read
      local found_cache_read = false
      for _, event in ipairs(usage_events) do
        if event.type == "cache_read" then
          found_cache_read = true
        end
      end
      assert.is_false(found_cache_read, "Should not emit cache_read when prompt_tokens_details is missing")
    end)
  end)
end)
