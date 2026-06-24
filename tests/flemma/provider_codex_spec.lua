describe("Codex Provider", function()
  local codex
  local make_prompt = require("tests.utilities.prompt").make_prompt
  local registry = require("flemma.provider.registry")

  before_each(function()
    package.loaded["flemma.provider.adapters.experimental.codex"] = nil
    package.loaded["flemma.provider.openai_responses"] = nil
    codex = require("flemma.provider.adapters.experimental.codex")
    -- Register codex models so _apply_reasoning can look up model capabilities.
    -- Codex is experimental (not in BUILTIN_PROVIDER_MODULES), so models aren't
    -- loaded by default.
    if not registry.has("codex") then
      registry.register("flemma.provider.adapters.experimental.codex")
    end
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  describe("metadata", function()
    it("has name 'codex'", function()
      assert.are.equal("codex", codex.metadata.name)
    end)

    it("has display name", function()
      assert.are.equal("Codex (ChatGPT)", codex.metadata.display_name)
    end)
  end)

  describe("new()", function()
    it("sets the Codex endpoint", function()
      local provider = codex.new({ model = "gpt-5.5", max_tokens = 4096 })
      assert.are.equal("https://chatgpt.com/backend-api/codex/responses", provider.endpoint)
    end)
  end)

  describe("get_credential()", function()
    it("returns chatgpt_subscription kind", function()
      local provider = codex.new({ model = "gpt-5.5", max_tokens = 4096 })
      local cred = provider:get_credential()
      assert.are.equal("chatgpt_subscription", cred.kind)
      assert.are.equal("codex", cred.service)
    end)
  end)

  describe("build_request", function()
    it("uses instructions field instead of developer role", function()
      local provider = codex.new({ model = "gpt-5.5", max_tokens = 4096, temperature = 0.7 })
      local prompt = make_prompt({
        { type = "System", content = "You are helpful." },
        { type = "You", content = "Hello" },
      })
      local body = provider:build_request(prompt)

      assert.are.equal("You are helpful.", body.instructions)
      for _, item in ipairs(body.input) do
        assert.is_not_equal("developer", item.role)
      end
    end)

    it("sets store = false", function()
      local provider = codex.new({ model = "gpt-5.5", max_tokens = 4096 })
      local body = provider:build_request(make_prompt({ { type = "You", content = "Hi" } }))
      assert.are.equal(false, body.store)
    end)

    it("includes text verbosity", function()
      local provider = codex.new({ model = "gpt-5.5", max_tokens = 4096 })
      local body = provider:build_request(make_prompt({ { type = "You", content = "Hi" } }))
      assert.are.same({ verbosity = "low" }, body.text)
    end)

    it("uses input field (Responses API format)", function()
      local provider = codex.new({ model = "gpt-5.5", max_tokens = 4096 })
      local body = provider:build_request(make_prompt({ { type = "You", content = "Hi" } }))
      assert.is_not_nil(body.input)
      assert.is_nil(body.messages)
    end)

    it("sets stream = true", function()
      local provider = codex.new({ model = "gpt-5.5", max_tokens = 4096 })
      local body = provider:build_request(make_prompt({ { type = "You", content = "Hi" } }))
      assert.is_true(body.stream)
    end)

    it("does not include prompt caching fields", function()
      local provider = codex.new({ model = "gpt-5.5", max_tokens = 4096 })
      local body = provider:build_request(make_prompt({ { type = "You", content = "Hi" } }))
      assert.is_nil(body.prompt_cache_key)
      assert.is_nil(body.prompt_cache_retention)
    end)

    it("does not send max_output_tokens or temperature", function()
      local provider = codex.new({ model = "gpt-5.5", max_tokens = 4096, temperature = 0.7 })
      local body = provider:build_request(make_prompt({ { type = "You", content = "Hi" } }))
      assert.is_nil(body.max_output_tokens)
      assert.is_nil(body.max_tokens)
      assert.is_nil(body.temperature)
    end)

    it("sets parallel_tool_calls = true", function()
      local provider = codex.new({ model = "gpt-5.5", max_tokens = 4096 })
      local body = provider:build_request(make_prompt({ { type = "You", content = "Hi" } }))
      assert.is_true(body.parallel_tool_calls)
    end)

    it("always includes reasoning.encrypted_content", function()
      local provider = codex.new({ model = "gpt-5.5", max_tokens = 4096 })
      local body = provider:build_request(make_prompt({ { type = "You", content = "Hi" } }))
      assert.are.same({ "reasoning.encrypted_content" }, body.include)
    end)

    it("sends reasoning.summary defaulting to auto", function()
      local provider =
        codex.new({ model = "gpt-5.5", max_tokens = 4096, thinking = { level = "low", foreign = "preserve" } })
      local body = provider:build_request(make_prompt({ { type = "You", content = "Hi" } }))
      assert.is_not_nil(body.reasoning)
      assert.are.equal("auto", body.reasoning.summary)
      assert.are.equal("low", body.reasoning.effort)
    end)

    it("respects reasoning_summary parameter override", function()
      local provider = codex.new({
        model = "gpt-5.5",
        max_tokens = 4096,
        thinking = { level = "high", foreign = "preserve" },
        reasoning_summary = "detailed",
      })
      local body = provider:build_request(make_prompt({ { type = "You", content = "Hi" } }))
      assert.is_not_nil(body.reasoning)
      assert.are.equal("detailed", body.reasoning.summary)
    end)
  end)

  describe("is_auth_error()", function()
    it("detects unauthorized errors", function()
      local provider = codex.new({ model = "gpt-5.5", max_tokens = 4096 })
      assert.is_true(provider:is_auth_error("Unauthorized"))
      assert.is_true(provider:is_auth_error("authentication failed"))
      assert.is_true(provider:is_auth_error("invalid token"))
      assert.is_true(provider:is_auth_error("token expired"))
    end)

    it("returns false for non-auth errors", function()
      local provider = codex.new({ model = "gpt-5.5", max_tokens = 4096 })
      assert.is_false(provider:is_auth_error("rate limit exceeded"))
      assert.is_false(provider:is_auth_error("model not found"))
      assert.is_false(provider:is_auth_error(nil))
    end)
  end)
end)
