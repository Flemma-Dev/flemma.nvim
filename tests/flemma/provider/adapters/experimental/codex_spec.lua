describe("flemma.provider.adapters.experimental.codex", function()
  local codex

  before_each(function()
    package.loaded["flemma.provider.adapters.experimental.codex"] = nil
    package.loaded["flemma.provider.base"] = nil
    package.loaded["flemma.provider.openai_responses"] = nil
    package.loaded["flemma.secrets"] = nil

    codex = require("flemma.provider.adapters.experimental.codex")
  end)

  describe("get_rate_limit_snapshot", function()
    it("parses x-codex headers into a rate limit snapshot", function()
      local provider = codex.new({ model = "gpt-5.5" })
      provider:set_response_headers({
        ["x-codex-plan-type"] = { "plus" },
        ["x-codex-primary-used-percent"] = { "2" },
        ["x-codex-primary-window-minutes"] = { "300" },
        ["x-codex-primary-reset-at"] = { "1782333276" },
        ["x-codex-secondary-used-percent"] = { "0" },
        ["x-codex-secondary-window-minutes"] = { "10080" },
        ["x-codex-secondary-reset-at"] = { "1782920076" },
      })

      local snapshot = provider:get_rate_limit_snapshot()
      assert.is_not_nil(snapshot)
      assert.equals("Plus", snapshot.plan_name)
      assert.equals(2, #snapshot.windows)

      local primary = snapshot.windows[1]
      assert.equals(2, primary.used_percent)
      assert.equals(18000, primary.window_seconds)
      assert.equals(1782333276, primary.resets_at)

      local secondary = snapshot.windows[2]
      assert.equals(0, secondary.used_percent)
      assert.equals(604800, secondary.window_seconds)
      assert.equals(1782920076, secondary.resets_at)
    end)

    it("returns nil when no response headers are set", function()
      local provider = codex.new({ model = "gpt-5.5" })
      assert.is_nil(provider:get_rate_limit_snapshot())
    end)

    it("returns nil when no rate limit headers are present", function()
      local provider = codex.new({ model = "gpt-5.5" })
      provider:set_response_headers({
        ["content-type"] = { "text/event-stream" },
      })
      assert.is_nil(provider:get_rate_limit_snapshot())
    end)

    it("handles missing secondary window", function()
      local provider = codex.new({ model = "gpt-5.5" })
      provider:set_response_headers({
        ["x-codex-plan-type"] = { "pro" },
        ["x-codex-primary-used-percent"] = { "50" },
        ["x-codex-primary-window-minutes"] = { "300" },
      })

      local snapshot = provider:get_rate_limit_snapshot()
      assert.is_not_nil(snapshot)
      assert.equals("Pro", snapshot.plan_name)
      assert.equals(1, #snapshot.windows)
      assert.equals(50, snapshot.windows[1].used_percent)
    end)

    it("title-cases known plan types", function()
      local provider = codex.new({ model = "gpt-5.5" })
      provider:set_response_headers({
        ["x-codex-plan-type"] = { "enterprise" },
        ["x-codex-primary-used-percent"] = { "10" },
        ["x-codex-primary-window-minutes"] = { "300" },
      })

      local snapshot = provider:get_rate_limit_snapshot()
      assert.equals("Enterprise", snapshot.plan_name)
    end)
  end)
end)
