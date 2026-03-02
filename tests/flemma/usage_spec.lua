describe("flemma.usage", function()
  local usage
  local state
  local session_module

  before_each(function()
    package.loaded["flemma.usage"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.pricing"] = nil
    package.loaded["flemma.session"] = nil
    package.loaded["flemma.bar"] = nil

    usage = require("flemma.usage")
    state = require("flemma.state")
    session_module = require("flemma.session")

    state.set_config({
      provider = "openai",
      model = "gpt-4o",
      pricing = { enabled = true },
    })
  end)

  describe("format_number", function()
    it("should add comma separators", function()
      assert.are.equal("20,449", usage.format_number(20449))
      assert.are.equal("1,000,000", usage.format_number(1000000))
      assert.are.equal("100", usage.format_number(100))
      assert.are.equal("0", usage.format_number(0))
    end)
  end)

  describe("calculate_cache_percent", function()
    it("should return nil when total input is 0", function()
      local request = session_module.Request.new({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 0,
        output_tokens = 50,
        input_price = 2.50,
        output_price = 10.00,
      })
      assert.is_nil(usage.calculate_cache_percent(request))
    end)

    it("should calculate percentage correctly", function()
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
      assert.are.equal(80, usage.calculate_cache_percent(request))
    end)
  end)

  describe("format_notification", function()
    it("should render request data as a single line", function()
      local request = session_module.Request.new({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 100,
        output_tokens = 50,
        input_price = 2.50,
        output_price = 10.00,
      })

      local result = usage.format_notification(request, nil, 120)

      -- Single line (no newlines in content portion)
      local content = result.text:match("^(.-)%s*$") -- trim trailing spaces
      assert.has_no_match("\n", content)
      assert.has_match("gpt%-4o", result.text)
      assert.has_match("%(openai%)", result.text)
      assert.has_match("%$", result.text)
      assert.has_match("\xE2\x86\x91 100", result.text)
      assert.has_match("\xE2\x86\x93 50", result.text)
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

      local result = usage.format_notification(request, session, 150)

      assert.has_match("gpt%-4o", result.text)
      assert.has_match("Session", result.text)
      assert.has_match("Requests", result.text)
    end)

    it("should return empty result when both args are nil", function()
      local result = usage.format_notification(nil, nil, 120)
      assert.are.equal("", result.text)
      assert.are.equal(0, #result.highlights)
    end)

    it("should not include costs when pricing disabled", function()
      state.set_config({
        provider = "openai",
        model = "gpt-4o",
        pricing = { enabled = false },
      })

      local request = session_module.Request.new({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 1000000,
        output_tokens = 500000,
        input_price = 3.00,
        output_price = 15.00,
      })

      local result = usage.format_notification(request, nil, 120)

      assert.has_no_match("%$", result.text)
      assert.has_match("\xE2\x86\x91", result.text)
      assert.has_match("\xE2\x86\x93", result.text)
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

      local result = usage.format_notification(request, nil, 120)

      assert.has_match("claude%-sonnet%-4%-5", result.text)
      assert.has_no_match("gpt%-4o", result.text)
    end)

    it("should include cache highlights", function()
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

      local result = usage.format_notification(request, nil, 120)

      assert.has_match("Cache 80%%", result.text)
      local found_good = false
      for _, highlight in ipairs(result.highlights) do
        if highlight.group == "FlemmaNotificationsCacheGood" then
          found_good = true
        end
      end
      assert.is_true(found_good)
    end)

    it("should highlight cache warning for low hit rate", function()
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 400,
        output_tokens = 200,
        input_price = 3.00,
        output_price = 15.00,
        cache_read_input_tokens = 100,
      })

      local result = usage.format_notification(request, nil, 120)

      assert.has_match("20%%", result.text)
      local found_bad = false
      for _, highlight in ipairs(result.highlights) do
        if highlight.group == "FlemmaNotificationsCacheBad" then
          found_bad = true
        end
      end
      assert.is_true(found_bad)
    end)

    it("should include thinking tokens", function()
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

      local result = usage.format_notification(request, nil, 120)

      assert.has_match("\xE2\x97\x8B 25", result.text)
    end)

    it("should format large numbers with commas", function()
      local session = session_module.Session.new()
      session:add_request({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 20449,
        output_tokens = 4271,
        input_price = 2.50,
        output_price = 10.00,
      })

      local result = usage.format_notification(nil, session, 120)

      assert.has_match("20,449", result.text)
    end)
  end)
end)
