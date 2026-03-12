describe("flemma.usage", function()
  local usage
  local state
  local session_module

  before_each(function()
    package.loaded["flemma.usage"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.tools"] = nil
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

  --- Find an item by key across all segments
  ---@param segments table[]
  ---@param key string
  ---@return table|nil
  local function find_item(segments, key)
    for _, segment in ipairs(segments) do
      for _, item in ipairs(segment.items or {}) do
        if item.key == key then
          return item
        end
      end
    end
    return nil
  end

  describe("cache percentage with min_cache_tokens threshold", function()
    it("should omit cache_percent when 0% and below min_cache_tokens", function()
      -- Anthropic haiku-4-5 has min_cache_tokens = 4096
      -- Total input = 2000 (below 4096), cache = 0%
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-haiku-4-5",
        input_tokens = 2000,
        output_tokens = 500,
        input_price = 1.00,
        output_price = 5.00,
        cache_read_input_tokens = 0,
        cache_creation_input_tokens = 0,
      })
      local segments = usage.build_segments(request, nil)
      local cache_item = find_item(segments, "cache_percent")
      assert.is_nil(cache_item)
    end)

    it("should show cache_percent when 0% but above min_cache_tokens", function()
      -- Total input = 10000 (above 4096), cache = 0%
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-haiku-4-5",
        input_tokens = 10000,
        output_tokens = 500,
        input_price = 1.00,
        output_price = 5.00,
        cache_read_input_tokens = 0,
        cache_creation_input_tokens = 0,
      })
      local segments = usage.build_segments(request, nil)
      local cache_item = find_item(segments, "cache_percent")
      assert.is_not_nil(cache_item)
    end)

    it("should show cache_percent when nonzero regardless of threshold", function()
      -- Total input = 2000 (below 4096), but cache_read > 0
      local request = session_module.Request.new({
        provider = "anthropic",
        model = "claude-haiku-4-5",
        input_tokens = 1000,
        output_tokens = 500,
        input_price = 1.00,
        output_price = 5.00,
        cache_read_input_tokens = 1000,
        cache_creation_input_tokens = 0,
      })
      local segments = usage.build_segments(request, nil)
      local cache_item = find_item(segments, "cache_percent")
      assert.is_not_nil(cache_item)
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
      assert.has_match("100\xE2\x86\x91", result.text)
      assert.has_match("50\xE2\x86\x93", result.text)
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
      assert.has_match("Σ1", result.text)
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

      assert.has_match("80%%", result.text)
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

      assert.has_match("25\xE2\x81\x82", result.text)
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
