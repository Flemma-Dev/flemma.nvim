describe("flemma.usage", function()
  local usage
  local state

  -- Before each test, get a fresh instance of the modules
  before_each(function()
    -- Invalidate the package cache to ensure we get fresh modules
    package.loaded["flemma.usage"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.pricing"] = nil

    usage = require("flemma.usage")
    state = require("flemma.state")

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
      local current_usage = {
        input_tokens = 100,
        output_tokens = 50,
        thoughts_tokens = 0,
      }

      local result = usage.format_notification(current_usage, nil)

      assert.is_string(result)
      assert.has_match("Request:", result)
      assert.has_match("Model:.*gpt%-4o.*openai", result)
      assert.has_match("Input:.*100 tokens", result)
      assert.has_match("Output:.*50 tokens", result)
    end)

    it("should format request usage with thoughts tokens", function()
      local current_usage = {
        input_tokens = 100,
        output_tokens = 50,
        thoughts_tokens = 25,
      }

      local result = usage.format_notification(current_usage, nil)

      assert.is_string(result)
      assert.has_match("Request:", result)
      assert.has_match("Input:.*100 tokens", result)
      assert.has_match("Output:.*75 tokens.*⊂ 25 thoughts", result)
    end)

    it("should format both request and session usage", function()
      local current_usage = {
        input_tokens = 100,
        output_tokens = 50,
        thoughts_tokens = 0,
      }

      local session_usage = {
        input_tokens = 500,
        output_tokens = 300,
        thoughts_tokens = 100,
      }

      local result = usage.format_notification(current_usage, session_usage)

      assert.is_string(result)
      assert.has_match("Request:", result)
      assert.has_match("Session:", result)
      assert.has_match("Input:.*100 tokens", result) -- Request
      assert.has_match("Input:.*500 tokens", result) -- Session
    end)

    it("should handle zero token usage gracefully", function()
      local current_usage = {
        input_tokens = 0,
        output_tokens = 0,
        thoughts_tokens = 0,
      }

      local session_usage = {
        input_tokens = 0,
        output_tokens = 0,
        thoughts_tokens = 0,
      }

      local result = usage.format_notification(current_usage, session_usage)

      -- Should return empty string when no meaningful usage
      assert.are.equal("", result)
    end)

    it("should format session usage only when no current usage", function()
      local session_usage = {
        input_tokens = 200,
        output_tokens = 150,
        thoughts_tokens = 50,
      }

      local result = usage.format_notification(nil, session_usage)

      assert.is_string(result)
      assert.has_match("Session:", result)
      assert.has_match("Input:.*200 tokens", result)
      assert.has_no_match("Request:", result)
    end)

    it("should include cost information when pricing is enabled", function()
      local current_usage = {
        input_tokens = 1000,
        output_tokens = 500,
        thoughts_tokens = 0,
      }

      local result = usage.format_notification(current_usage, nil)

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

      local current_usage = {
        input_tokens = 1000,
        output_tokens = 500,
        thoughts_tokens = 0,
      }

      local result = usage.format_notification(current_usage, nil)

      assert.is_string(result)
      assert.has_match("1000 tokens", result)
      assert.has_match("500 tokens", result)
      -- Should not contain dollar signs
      assert.has_no_match("%$", result)
      assert.has_no_match("Total:", result)
    end)

    it("should handle session usage with thoughts tokens in cost calculation", function()
      local session_usage = {
        input_tokens = 1000,
        output_tokens = 300,
        thoughts_tokens = 200,
      }

      local result = usage.format_notification(nil, session_usage)

      assert.is_string(result)
      assert.has_match("Session:", result)
      assert.has_match("Input:.*1000 tokens", result)
      -- Should show combined output + thoughts tokens for cost (500 total)
      assert.has_match("Output:.*500 tokens", result)
      assert.has_match("%$", result) -- Should include cost
    end)
  end)
end)
