--- Tests for secrets cache module

package.loaded["flemma.secrets.cache"] = nil

local cache = require("flemma.secrets.cache")

describe("flemma.secrets.cache", function()
  before_each(function()
    cache.invalidate_all()
  end)

  describe("get/set", function()
    it("returns nil for unknown key", function()
      assert.is_nil(cache.get("api_key:anthropic"))
    end)

    it("stores and retrieves a result", function()
      local result = { value = "sk-test-123" }
      local credential = { kind = "api_key", service = "anthropic" }
      cache.set("api_key:anthropic", result, credential)

      local cached = cache.get("api_key:anthropic")
      assert.is_not_nil(cached)
      assert.equals("sk-test-123", cached.value)
    end)

    it("returns result directly from get, not the CachedResult wrapper", function()
      local result = { value = "sk-test-123" }
      local credential = { kind = "api_key", service = "anthropic" }
      cache.set("api_key:anthropic", result, credential)

      local got = cache.get("api_key:anthropic")
      assert.equals("sk-test-123", got.value)
      -- Should NOT have internal fields like resolved_at
      assert.is_nil(got.resolved_at)
    end)
  end)

  describe("TTL", function()
    it("caches indefinitely when no TTL is set", function()
      local result = { value = "sk-test-123" }
      local credential = { kind = "api_key", service = "anthropic" }
      cache.set("api_key:anthropic", result, credential)

      assert.is_not_nil(cache.get("api_key:anthropic"))
    end)

    it("respects result TTL", function()
      local result = { value = "ya29.token", ttl = 1 }
      local credential = { kind = "access_token", service = "vertex" }
      cache.set("access_token:vertex", result, credential)

      assert.is_not_nil(cache.get("access_token:vertex"))
    end)

    it("uses credential TTL as fallback when result has no TTL", function()
      local result = { value = "ya29.token" }
      local credential = { kind = "access_token", service = "vertex", ttl = 1 }
      cache.set("access_token:vertex", result, credential)

      assert.is_not_nil(cache.get("access_token:vertex"))
    end)

    it("applies ttl_scale to effective TTL", function()
      local result = { value = "ya29.token", ttl = 100 }
      local credential = { kind = "access_token", service = "vertex", ttl_scale = 0.5 }
      cache.set("access_token:vertex", result, credential)

      assert.is_not_nil(cache.get("access_token:vertex"))
    end)

    it("result TTL overrides credential TTL", function()
      local result = { value = "ya29.token", ttl = 200 }
      local credential = { kind = "access_token", service = "vertex", ttl = 3600 }
      cache.set("access_token:vertex", result, credential)

      local entry = cache.get_entry("access_token:vertex")
      assert.is_not_nil(entry)
      assert.equals(200, entry.effective_ttl)
    end)

    it("computes effective_ttl with scale", function()
      local result = { value = "ya29.token", ttl = 3600 }
      local credential = { kind = "access_token", service = "vertex", ttl_scale = 0.925 }
      cache.set("access_token:vertex", result, credential)

      local entry = cache.get_entry("access_token:vertex")
      assert.is_not_nil(entry)
      assert.equals(3600 * 0.925, entry.effective_ttl)
    end)
  end)

  describe("invalidate", function()
    it("removes a specific entry", function()
      cache.set("api_key:anthropic", { value = "sk-1" }, { kind = "api_key", service = "anthropic" })
      cache.set("api_key:openai", { value = "sk-2" }, { kind = "api_key", service = "openai" })

      cache.invalidate("api_key:anthropic")

      assert.is_nil(cache.get("api_key:anthropic"))
      assert.is_not_nil(cache.get("api_key:openai"))
    end)

    it("clears all entries with invalidate_all", function()
      cache.set("api_key:anthropic", { value = "sk-1" }, { kind = "api_key", service = "anthropic" })
      cache.set("api_key:openai", { value = "sk-2" }, { kind = "api_key", service = "openai" })

      cache.invalidate_all()

      assert.is_nil(cache.get("api_key:anthropic"))
      assert.is_nil(cache.get("api_key:openai"))
    end)
  end)

  describe("count", function()
    it("returns 0 when empty", function()
      assert.equals(0, cache.count())
    end)

    it("returns the number of cached entries", function()
      cache.set("api_key:anthropic", { value = "sk-1" }, { kind = "api_key", service = "anthropic" })
      cache.set("api_key:openai", { value = "sk-2" }, { kind = "api_key", service = "openai" })
      assert.equals(2, cache.count())
    end)
  end)
end)
