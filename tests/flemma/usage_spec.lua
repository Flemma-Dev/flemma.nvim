describe("flemma.usage", function()
  local usage
  local state
  local session_module

  -- Before each test, get a fresh instance of the modules
  before_each(function()
    -- Invalidate the package cache to ensure we get fresh modules
    package.loaded["flemma.usage"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.pricing"] = nil
    package.loaded["flemma.session"] = nil

    usage = require("flemma.usage")
    state = require("flemma.state")
    session_module = require("flemma.session")

    -- Set up a basic config with pricing enabled
    state.set_config({
      provider = "openai",
      model = "gpt-4o",
      pricing = {
        enabled = true,
      },
    })
  end)

  describe("format_notification", function()
    it("should format request usage without session data", function()
      local request = session_module.Request.new({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 100,
        output_tokens = 50,
        thoughts_tokens = 0,
        input_price = 2.50,
        output_price = 10.00,
      })

      local result = usage.format_notification(request, nil)

      assert.is_string(result)
      assert.has_match("Request:", result)
      assert.has_match("Model:.*gpt%-4o.*openai", result)
      assert.has_match("Input:.*100 tokens", result)
      assert.has_match("Output:.*50 tokens", result)
    end)

    it("should format request usage with thoughts tokens (OpenAI - thoughts included in output)", function()
      -- OpenAI: completion_tokens already includes reasoning_tokens
      local request = session_module.Request.new({
        provider = "openai",
        model = "o1",
        input_tokens = 100,
        output_tokens = 50, -- completion_tokens (includes reasoning)
        thoughts_tokens = 25, -- reasoning_tokens (subset, for display)
        input_price = 15.00,
        output_price = 60.00,
        output_has_thoughts = true, -- OpenAI behavior
      })

      local result = usage.format_notification(request, nil)

      assert.is_string(result)
      assert.has_match("Request:", result)
      assert.has_match("Input:.*100 tokens", result)
      -- Should show 50 tokens (not 75), since thoughts are already included
      assert.has_match("Output:.*50 tokens.*⊂ 25 thoughts", result)
    end)

    it("should format request usage with thoughts tokens (Vertex - thoughts separate)", function()
      -- Vertex: candidatesTokenCount and thoughtsTokenCount are separate
      local request = session_module.Request.new({
        provider = "vertex",
        model = "gemini-2.5-pro",
        input_tokens = 100,
        output_tokens = 50, -- candidatesTokenCount
        thoughts_tokens = 25, -- thoughtsTokenCount
        input_price = 1.25,
        output_price = 10.00,
        output_has_thoughts = false, -- Vertex behavior
      })

      local result = usage.format_notification(request, nil)

      assert.is_string(result)
      assert.has_match("Request:", result)
      assert.has_match("Input:.*100 tokens", result)
      -- Should show 75 tokens (50 + 25), since thoughts are separate
      assert.has_match("Output:.*75 tokens.*⊂ 25 thoughts", result)
    end)

    it("should format both request and session usage", function()
      local request = session_module.Request.new({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 100,
        output_tokens = 50,
        thoughts_tokens = 0,
        input_price = 2.50,
        output_price = 10.00,
      })

      -- Create a session with the same request
      local session = session_module.Session.new()
      session:add_request({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 500,
        output_tokens = 300,
        thoughts_tokens = 100,
        input_price = 2.50,
        output_price = 10.00,
      })

      local result = usage.format_notification(request, session)

      assert.is_string(result)
      assert.has_match("Request:", result)
      assert.has_match("Session:", result)
      assert.has_match("Input:.*100 tokens", result) -- Request
      assert.has_match("Input:.*500 tokens", result) -- Session
    end)

    it("should handle nil request gracefully", function()
      -- Create an empty session
      local session = session_module.Session.new()

      local result = usage.format_notification(nil, session)

      -- Should return empty string when no request and empty session
      assert.are.equal("", result)
    end)

    it("should format session usage only when no request", function()
      -- Create a session with requests
      local session = session_module.Session.new()
      session:add_request({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 200,
        output_tokens = 150,
        thoughts_tokens = 50,
        input_price = 2.50,
        output_price = 10.00,
      })

      local result = usage.format_notification(nil, session)

      assert.is_string(result)
      assert.has_match("Session:", result)
      assert.has_match("Input:.*200 tokens", result)
      assert.has_no_match("Request:", result)
    end)

    it("should include cost information when pricing is enabled", function()
      local request = session_module.Request.new({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 1000,
        output_tokens = 500,
        thoughts_tokens = 0,
        input_price = 2.50,
        output_price = 10.00,
      })

      local result = usage.format_notification(request, nil)

      assert.is_string(result)
      -- Should contain dollar signs indicating cost calculation
      assert.has_match("%$", result)
      assert.has_match("Total:.*%$", result)
    end)

    it("should not include cost information when pricing is disabled", function()
      -- Disable pricing
      state.set_config({
        provider = "openai",
        model = "gpt-4o",
        pricing = {
          enabled = false,
        },
      })

      local request = session_module.Request.new({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 1000,
        output_tokens = 500,
        thoughts_tokens = 0,
        input_price = 2.50,
        output_price = 10.00,
      })

      local result = usage.format_notification(request, nil)

      assert.is_string(result)
      assert.has_match("1000 tokens", result)
      assert.has_match("500 tokens", result)
      -- Should not contain dollar signs
      assert.has_no_match("%$", result)
      assert.has_no_match("Total:", result)
    end)

    it("should handle session usage with thoughts tokens in cost calculation", function()
      -- Create a session with requests
      local session = session_module.Session.new()
      session:add_request({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 1000,
        output_tokens = 300,
        thoughts_tokens = 200,
        input_price = 2.50,
        output_price = 10.00,
      })

      local result = usage.format_notification(nil, session)

      assert.is_string(result)
      assert.has_match("Session:", result)
      assert.has_match("Input:.*1000 tokens", result)
      -- Should show combined output + thoughts tokens for cost (500 total)
      assert.has_match("Output:.*500 tokens", result)
      assert.has_match("%$", result) -- Should include cost
    end)

    it("should display cost from request's pre-computed fields", function()
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 1000000,
        output_tokens = 500000,
        thoughts_tokens = 0,
        input_price = 3.00,
        output_price = 15.00,
      })

      local result = usage.format_notification(request, nil)

      -- Input cost: 1000000 / 1000000 * 3.00 = $3.00
      assert.has_match("Input:.*1000000 tokens.*%$3%.00", result)
      -- Output cost: 500000 / 1000000 * 15.00 = $7.50
      assert.has_match("Output:.*500000 tokens.*%$7%.50", result)
      -- Total cost: $10.50
      assert.has_match("Total:.*%$10%.50", result)
    end)

    it("should show model and provider from request, not config", function()
      -- Config says openai/gpt-4o, but request was made with anthropic/claude-sonnet-4-5
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 100,
        output_tokens = 50,
        thoughts_tokens = 0,
        input_price = 3.00,
        output_price = 15.00,
      })

      local result = usage.format_notification(request, nil)

      -- Should show the request's model/provider, not config's
      assert.has_match("Model:.*claude%-sonnet%-4%-5.*anthropic", result)
      assert.has_no_match("gpt%-4o", result)
    end)

    it("should display cache line from request fields", function()
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 500,
        output_tokens = 200,
        thoughts_tokens = 0,
        input_price = 3.00,
        output_price = 15.00,
        cache_read_input_tokens = 1000,
        cache_creation_input_tokens = 300,
        cache_read_multiplier = 0.1,
        cache_write_multiplier = 1.25,
      })

      local result = usage.format_notification(request, nil)

      assert.has_match("Cache:.*1000 read.*300 write", result)
    end)
  end)
end)
