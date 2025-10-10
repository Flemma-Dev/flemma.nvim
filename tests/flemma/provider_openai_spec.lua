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
        { model = "o1-mini", max_tokens = 5000 },
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
end)
