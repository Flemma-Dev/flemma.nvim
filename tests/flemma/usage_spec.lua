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
    it("should format request without session data", function()
      local request = session_module.Request.new({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 100,
        output_tokens = 50,
        input_price = 2.50,
        output_price = 10.00,
      })

      local result = usage.format_notification(request, nil)

      assert.has_match("`gpt%-4o` %(openai%)", result.text)
      assert.has_match("Request", result.text)
      assert.has_match("\xE2\x86\x91 100", result.text)
      assert.has_match("\xE2\x86\x93 50 tokens", result.text)
      assert.has_no_match("Session", result.text)
      assert.has_match("Cache .+ 0%%", result.text)
      assert.are.equal(1, #result.highlights)
      assert.are.equal("FlemmaNotifyCacheBad", result.highlights[1].group)
    end)

    it("should format request with thinking tokens (OpenAI)", function()
      local request = session_module.Request.new({
        provider = "openai",
        model = "o1",
        input_tokens = 100,
        output_tokens = 50,
        thoughts_tokens = 25,
        input_price = 15.00,
        output_price = 60.00,
        output_has_thoughts = true,
      })

      local result = usage.format_notification(request, nil)

      -- OpenAI: thoughts already included in output_tokens, so display shows 50
      assert.has_match("\xE2\x86\x93 50", result.text)
      assert.has_match("\xE2\x97\x8B 25 thinking", result.text)
    end)

    it("should format request with thinking tokens (Vertex)", function()
      local request = session_module.Request.new({
        provider = "vertex",
        model = "gemini-2.5-pro",
        input_tokens = 100,
        output_tokens = 50,
        thoughts_tokens = 25,
        input_price = 1.25,
        output_price = 10.00,
        output_has_thoughts = false,
      })

      local result = usage.format_notification(request, nil)

      -- Vertex: thoughts separate, total output = 50 + 25 = 75
      assert.has_match("\xE2\x86\x93 75", result.text)
      assert.has_match("\xE2\x97\x8B 25 thinking", result.text)
    end)

    it("should format request and session", function()
      local request = session_module.Request.new({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 100,
        output_tokens = 50,
        input_price = 2.50,
        output_price = 10.00,
      })

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

      assert.has_match("Request", result.text)
      assert.has_match("Session", result.text)
      assert.has_match("Requests", result.text)

      -- Both request and session detail lines have ↑
      local arrow_up_count = 0
      for _ in result.text:gmatch("\xE2\x86\x91") do
        arrow_up_count = arrow_up_count + 1
      end
      assert.is_true(arrow_up_count >= 2)
    end)

    it("should handle nil request gracefully", function()
      local session = session_module.Session.new()

      local result = usage.format_notification(nil, session)

      assert.are.equal("", result.text)
      assert.are.equal(0, #result.highlights)
    end)

    it("should format session only when no request", function()
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

      assert.has_match("Session", result.text)
      assert.has_no_match("Request .+%$", result.text)
    end)

    it("should include costs when pricing enabled", function()
      local request = session_module.Request.new({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 1000000,
        output_tokens = 500000,
        input_price = 3.00,
        output_price = 15.00,
      })

      local result = usage.format_notification(request, nil)

      assert.has_match("%$", result.text)
      assert.has_match("Request .+ %$", result.text)
    end)

    it("should not include costs when pricing disabled", function()
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
        input_tokens = 1000000,
        output_tokens = 500000,
        input_price = 3.00,
        output_price = 15.00,
      })

      local result = usage.format_notification(request, nil)

      assert.has_no_match("%$", result.text)
      assert.has_match("\xE2\x86\x91", result.text)
      assert.has_match("\xE2\x86\x93", result.text)
      assert.has_match("Cache .+%%", result.text)
    end)

    it("should show model from request not config", function()
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 100,
        output_tokens = 50,
        input_price = 3.00,
        output_price = 15.00,
      })

      local result = usage.format_notification(request, nil)

      assert.has_match("claude%-sonnet%-4%-5", result.text)
      assert.has_no_match("gpt%-4o", result.text)
    end)

    it("should display cache percentage", function()
      -- Total input = 100 + 400 + 0 = 500; cache hit = 400/500 = 80%
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 100,
        output_tokens = 200,
        input_price = 3.00,
        output_price = 15.00,
        cache_read_input_tokens = 400,
        cache_creation_input_tokens = 0,
      })

      local result = usage.format_notification(request, nil)

      assert.has_match("Cache .+ 80%%", result.text)
      local found_good = false
      for _, highlight in ipairs(result.highlights) do
        if highlight.group == "FlemmaNotifyCacheGood" then
          found_good = true
        end
      end
      assert.is_true(found_good)
    end)

    it("should highlight cache warning for low hit rate", function()
      -- Total input = 400 + 100 + 0 = 500; cache hit = 100/500 = 20%
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 400,
        output_tokens = 200,
        input_price = 3.00,
        output_price = 15.00,
        cache_read_input_tokens = 100,
      })

      local result = usage.format_notification(request, nil)

      assert.has_match("20%%", result.text)
      local found_bad = false
      for _, highlight in ipairs(result.highlights) do
        if highlight.group == "FlemmaNotifyCacheBad" then
          found_bad = true
        end
      end
      assert.is_true(found_bad)
    end)

    it("should format numbers with comma separators", function()
      local session = session_module.Session.new()
      session:add_request({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 20449,
        output_tokens = 4271,
        input_price = 2.50,
        output_price = 10.00,
      })

      local result = usage.format_notification(nil, session)

      assert.has_match("20,449", result.text)
    end)
  end)
end)
