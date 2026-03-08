describe("flemma.usage segment building", function()
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

  describe("build_segments", function()
    it("should build identity segment from request", function()
      local request = session_module.Request.new({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 100,
        output_tokens = 50,
        input_price = 2.50,
        output_price = 10.00,
      })

      local segments = usage.build_segments(request, nil)

      -- Find identity segment
      local identity = nil
      for _, segment in ipairs(segments) do
        if segment.key == "identity" then
          identity = segment
        end
      end

      assert.is_not_nil(identity)

      -- Find model_name item
      local model_item = nil
      for _, item in ipairs(identity.items) do
        if item.key == "model_name" then
          model_item = item
        end
      end

      assert.is_not_nil(model_item)
      assert.are.equal("gpt-4o", model_item.text)
      assert.are.equal(110, model_item.priority)
    end)

    it("should build request segment with cost and cache", function()
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

      local segments = usage.build_segments(request, nil)

      local request_segment = nil
      for _, segment in ipairs(segments) do
        if segment.key == "request" then
          request_segment = segment
        end
      end

      assert.is_not_nil(request_segment)

      -- Should have cost, cache, input tokens, output tokens
      local keys = {}
      for _, item in ipairs(request_segment.items) do
        keys[item.key] = item
      end

      assert.is_not_nil(keys["request_cost"])
      assert.has_match("%$", keys["request_cost"].text)

      assert.is_not_nil(keys["cache_percent"])
      assert.has_match("80%%", keys["cache_percent"].text)
      assert.is_not_nil(keys["cache_percent"].highlight)
      assert.are.equal("FlemmaNotificationsCacheGood", keys["cache_percent"].highlight.group)
    end)

    it("should not include cost items when pricing disabled", function()
      state.set_config({
        provider = "openai",
        model = "gpt-4o",
        pricing = { enabled = false },
      })

      local request = session_module.Request.new({
        provider = "openai",
        model = "gpt-4o",
        input_tokens = 100,
        output_tokens = 50,
        input_price = 2.50,
        output_price = 10.00,
      })

      local segments = usage.build_segments(request, nil)

      local request_segment = nil
      for _, segment in ipairs(segments) do
        if segment.key == "request" then
          request_segment = segment
        end
      end

      -- Should not have cost item
      for _, item in ipairs(request_segment.items) do
        assert.is_not_equal("request_cost", item.key)
      end
    end)

    it("should build session segment with label", function()
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

      local segments = usage.build_segments(request, session)

      local session_segment = nil
      for _, segment in ipairs(segments) do
        if segment.key == "session" then
          session_segment = segment
        end
      end

      assert.is_not_nil(session_segment)
      assert.has_match("^Σ%d+$", session_segment.label)
    end)

    it("should return empty table when both request and session are nil", function()
      local segments = usage.build_segments(nil, nil)
      assert.are.equal(0, #segments)
    end)

    it("should return empty table when session has no requests and request is nil", function()
      local session = session_module.Session.new()
      local segments = usage.build_segments(nil, session)
      assert.are.equal(0, #segments)
    end)

    it("should include thinking tokens item when present", function()
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

      local segments = usage.build_segments(request, nil)

      local request_segment = nil
      for _, segment in ipairs(segments) do
        if segment.key == "request" then
          request_segment = segment
        end
      end

      local thinking_item = nil
      for _, item in ipairs(request_segment.items) do
        if item.key == "thinking_tokens" then
          thinking_item = item
        end
      end

      assert.is_not_nil(thinking_item)
      assert.has_match("\xE2\x97\x8B 25", thinking_item.text)
      assert.are.equal(50, thinking_item.priority)
    end)
  end)
end)
