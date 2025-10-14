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
      local inflight_usage = {
        input_tokens = 100,
        output_tokens = 50,
        thoughts_tokens = 0,
      }

      local result = usage.format_notification(inflight_usage, nil)

      assert.is_string(result)
      assert.has_match("Request:", result)
      assert.has_match("Model:.*gpt%-4o.*openai", result)
      assert.has_match("Input:.*100 tokens", result)
      assert.has_match("Output:.*50 tokens", result)
    end)

    it("should format request usage with thoughts tokens", function()
      local inflight_usage = {
        input_tokens = 100,
        output_tokens = 50,
        thoughts_tokens = 25,
      }

      local result = usage.format_notification(inflight_usage, nil)

      assert.is_string(result)
      assert.has_match("Request:", result)
      assert.has_match("Input:.*100 tokens", result)
      assert.has_match("Output:.*75 tokens.*⊂ 25 thoughts", result)
    end)

    it("should format both request and session usage", function()
      local inflight_usage = {
        input_tokens = 100,
        output_tokens = 50,
        thoughts_tokens = 0,
      }

      -- Create a session with requests
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

      local result = usage.format_notification(inflight_usage, session)

      assert.is_string(result)
      assert.has_match("Request:", result)
      assert.has_match("Session:", result)
      assert.has_match("Input:.*100 tokens", result) -- Request
      assert.has_match("Input:.*500 tokens", result) -- Session
    end)

    it("should handle zero token usage gracefully", function()
      local inflight_usage = {
        input_tokens = 0,
        output_tokens = 0,
        thoughts_tokens = 0,
      }

      -- Create an empty session
      local session = session_module.Session.new()

      local result = usage.format_notification(inflight_usage, session)

      -- Should return empty string when no meaningful usage
      assert.are.equal("", result)
    end)

    it("should format session usage only when no in-flight usage", function()
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
      local inflight_usage = {
        input_tokens = 1000,
        output_tokens = 500,
        thoughts_tokens = 0,
      }

      local result = usage.format_notification(inflight_usage, nil)

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

      local inflight_usage = {
        input_tokens = 1000,
        output_tokens = 500,
        thoughts_tokens = 0,
      }

      local result = usage.format_notification(inflight_usage, nil)

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
  end)
end)
