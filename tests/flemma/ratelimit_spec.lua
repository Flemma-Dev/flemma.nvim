--- Tests for rate limit header storage and formatting
--- @see flemma.provider.base

describe("Rate limit response headers", function()
  local base

  before_each(function()
    package.loaded["flemma.provider.base"] = nil
    base = require("flemma.provider.base")
  end)

  describe("set_response_headers", function()
    it("stores headers on the provider instance", function()
      local provider = base.new()
      local headers = {
        ["content-type"] = { "application/json" },
        ["retry-after"] = { "30" },
      }
      provider:set_response_headers(headers)
      assert.same(headers, provider._response_headers)
    end)

    it("overwrites previous headers", function()
      local provider = base.new()
      provider:set_response_headers({ ["retry-after"] = { "10" } })
      provider:set_response_headers({ ["retry-after"] = { "60" } })
      assert.same({ ["retry-after"] = { "60" } }, provider._response_headers)
    end)
  end)

  describe("format_rate_limit_details", function()
    it("formats Anthropic rate limit headers", function()
      local provider = base.new()
      provider:set_response_headers({
        ["content-type"] = { "application/json" },
        ["retry-after"] = { "30" },
        ["anthropic-ratelimit-requests-remaining"] = { "0" },
        ["anthropic-ratelimit-requests-reset"] = { "2026-02-24T19:39:00Z" },
      })
      local details = provider:format_rate_limit_details()
      assert.is_not_nil(details)
      -- Should include rate limit headers but not content-type
      assert.truthy(details:match("retry%-after: 30"))
      assert.truthy(details:match("anthropic%-ratelimit%-requests%-remaining: 0"))
      assert.truthy(details:match("anthropic%-ratelimit%-requests%-reset: 2026%-02%-24T19:39:00Z"))
      assert.falsy(details:match("content%-type"))
    end)

    it("formats OpenAI rate limit headers", function()
      local provider = base.new()
      provider:set_response_headers({
        ["x-ratelimit-remaining-requests"] = { "0" },
        ["x-ratelimit-reset-requests"] = { "2026-02-24T19:39:00Z" },
        ["x-ratelimit-limit-requests"] = { "100" },
      })
      local details = provider:format_rate_limit_details()
      assert.is_not_nil(details)
      assert.truthy(details:match("x%-ratelimit%-remaining%-requests: 0"))
      assert.truthy(details:match("x%-ratelimit%-reset%-requests: 2026%-02%-24T19:39:00Z"))
      assert.truthy(details:match("x%-ratelimit%-limit%-requests: 100"))
    end)

    it("returns sorted output", function()
      local provider = base.new()
      provider:set_response_headers({
        ["x-ratelimit-remaining-requests"] = { "0" },
        ["retry-after"] = { "30" },
        ["anthropic-ratelimit-requests-reset"] = { "soon" },
      })
      local details = provider:format_rate_limit_details()
      assert.is_not_nil(details)
      local lines = vim.split(details, "\n")
      assert.equals(3, #lines)
      -- Alphabetical order
      assert.truthy(lines[1]:match("^anthropic"))
      assert.truthy(lines[2]:match("^retry"))
      assert.truthy(lines[3]:match("^x%-ratelimit"))
    end)

    it("returns nil when no rate limit headers present", function()
      local provider = base.new()
      provider:set_response_headers({
        ["content-type"] = { "application/json" },
        ["date"] = { "Mon, 24 Feb 2026 19:00:00 GMT" },
      })
      assert.is_nil(provider:format_rate_limit_details())
    end)

    it("returns nil when no headers stored", function()
      local provider = base.new()
      assert.is_nil(provider:format_rate_limit_details())
    end)

    it("handles multiple values for the same header", function()
      local provider = base.new()
      provider:set_response_headers({
        ["x-ratelimit-remaining-requests"] = { "0", "also-0" },
      })
      local details = provider:format_rate_limit_details()
      assert.is_not_nil(details)
      local lines = vim.split(details, "\n")
      assert.equals(2, #lines)
    end)
  end)

  describe("reset clears headers", function()
    it("clears _response_headers on full reset", function()
      local provider = base.new()
      provider:set_response_headers({ ["retry-after"] = { "30" } })
      provider:reset()
      assert.is_nil(provider._response_headers)
    end)

    it("preserves _response_headers on auth-only reset", function()
      local provider = base.new()
      provider:set_response_headers({ ["retry-after"] = { "30" } })
      provider:reset({ auth = true })
      assert.same({ ["retry-after"] = { "30" } }, provider._response_headers)
    end)
  end)
end)
