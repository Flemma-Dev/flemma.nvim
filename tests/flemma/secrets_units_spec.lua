--- Merged unit tests for the flemma.secrets submodules:
---   * flemma.secrets.cache
---   * flemma.secrets.context
---   * flemma.secrets.registry
---   * flemma.secrets.resolvers.chatgpt
---
--- Each submodule keeps its own top-level describe block with block-local
--- requires and per-test resets, so the blocks stay isolated from one another.

local json = require("flemma.utilities.json")

describe("flemma.secrets.cache", function()
  local cache

  before_each(function()
    package.loaded["flemma.secrets.cache"] = nil
    cache = require("flemma.secrets.cache")
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

describe("flemma.secrets.context", function()
  local context
  local config_facade

  before_each(function()
    package.loaded["flemma.secrets.context"] = nil
    package.loaded["flemma.secrets"] = nil
    package.loaded["flemma.secrets.registry"] = nil
    package.loaded["flemma.secrets.resolvers.gcloud"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.schema"] = nil
    config_facade = require("flemma.config")
    config_facade.init(require("flemma.config.schema"))
    -- gcloud's default now materializes when its resolver registers (the schema
    -- moved from a static field to a DISCOVER-resolved one owned by the resolver).
    require("flemma.secrets").register("flemma.secrets.resolvers.gcloud")
    context = require("flemma.secrets.context")
  end)

  describe("new", function()
    it("returns an object with get_config method", function()
      local ctx = context.new("gcloud")
      assert.is_not_nil(ctx)
      assert.is_function(ctx.get_config)
    end)

    it("get_config returns nil when resolver subtable is absent", function()
      -- "nonexistent" has no schema entry, so it resolves to nil
      local ctx = context.new("nonexistent")
      assert.is_nil(ctx:get_config())
    end)

    it("get_config returns the resolver subtable", function()
      config_facade.apply(config_facade.LAYERS.SETUP, { secrets = { gcloud = { path = "/nix/store/gcloud" } } })
      local ctx = context.new("gcloud")
      local cfg = ctx:get_config()
      assert.is_not_nil(cfg)
      assert.equals("/nix/store/gcloud", cfg.path)
    end)

    it("get_config returns schema defaults when no user config applied", function()
      local ctx = context.new("gcloud")
      local cfg = ctx:get_config()
      assert.is_not_nil(cfg)
      assert.equals("gcloud", cfg.path)
    end)

    it("get_config returns a deep copy (mutations do not affect state)", function()
      config_facade.apply(config_facade.LAYERS.SETUP, { secrets = { gcloud = { path = "gcloud" } } })
      local ctx = context.new("gcloud")
      local cfg = ctx:get_config()
      cfg.path = "mutated"
      local cfg2 = ctx:get_config()
      assert.equals("gcloud", cfg2.path)
    end)

    it("different resolver names return independent configs", function()
      config_facade.apply(config_facade.LAYERS.SETUP, { secrets = { gcloud = { path = "/path/to/gcloud" } } })
      local gcloud_ctx = context.new("gcloud")
      local nonexistent_ctx = context.new("nonexistent")
      assert.equals("/path/to/gcloud", gcloud_ctx:get_config().path)
      assert.is_nil(nonexistent_ctx:get_config())
    end)

    it("get_diagnostics returns empty table by default", function()
      local ctx = context.new("gcloud")
      assert.same({}, ctx:get_diagnostics())
    end)

    it("diagnostic appends a ResolverDiagnostic entry", function()
      local ctx = context.new("gcloud")
      ctx:diagnostic("executable not found")
      local diags = ctx:get_diagnostics()
      assert.equals(1, #diags)
      assert.equals("gcloud", diags[1].resolver)
      assert.equals("executable not found", diags[1].message)
    end)

    it("multiple diagnostics accumulate in order", function()
      local ctx = context.new("gcloud")
      ctx:diagnostic("first issue")
      ctx:diagnostic("second issue")
      local diags = ctx:get_diagnostics()
      assert.equals(2, #diags)
      assert.equals("first issue", diags[1].message)
      assert.equals("second issue", diags[2].message)
    end)

    it("diagnostics are scoped to the resolver name", function()
      local ctx_a = context.new("environment")
      local ctx_b = context.new("gcloud")
      ctx_a:diagnostic("var not set")
      ctx_b:diagnostic("binary missing")
      assert.equals("environment", ctx_a:get_diagnostics()[1].resolver)
      assert.equals("gcloud", ctx_b:get_diagnostics()[1].resolver)
    end)
  end)
end)

describe("flemma.secrets.registry", function()
  local registry

  --- Create a minimal mock resolver for testing.
  ---@param name string
  ---@param priority integer
  ---@param kinds? string[]
  ---@return flemma.secrets.Resolver
  local function make_resolver(name, priority, kinds)
    local supported = kinds or { "api_key" }
    return {
      name = name,
      priority = priority,
      supports = function(_, credential)
        return vim.tbl_contains(supported, credential.kind)
      end,
      resolve = function(_, _)
        return { value = name .. "-value" }
      end,
    }
  end

  before_each(function()
    package.loaded["flemma.secrets.registry"] = nil
    registry = require("flemma.secrets.registry")
  end)

  describe("register", function()
    it("registers a resolver", function()
      local resolver = make_resolver("env", 100)
      registry.register("env", resolver)

      assert.is_true(registry.has("env"))
      assert.equals(1, registry.count())
    end)

    it("accepts names with dots", function()
      local resolver = make_resolver("my.resolver", 100)
      assert.has_no.errors(function()
        registry.register("my.resolver", resolver)
      end)
    end)

    it("rejects names with colons", function()
      local resolver = make_resolver("bad:name", 100)
      assert.has_error(function()
        registry.register("bad:name", resolver)
      end)
    end)
  end)

  describe("get", function()
    it("returns a registered resolver", function()
      local resolver = make_resolver("env", 100)
      registry.register("env", resolver)

      local got = registry.get("env")
      assert.is_not_nil(got)
      assert.equals("env", got.name)
    end)

    it("returns nil for unknown resolver", function()
      assert.is_nil(registry.get("nonexistent"))
    end)
  end)

  describe("get_all_sorted", function()
    it("returns resolvers sorted by priority descending", function()
      registry.register("low", make_resolver("low", 10))
      registry.register("high", make_resolver("high", 100))
      registry.register("mid", make_resolver("mid", 50))

      local sorted = registry.get_all_sorted()
      assert.equals(3, #sorted)
      assert.equals("high", sorted[1].name)
      assert.equals("mid", sorted[2].name)
      assert.equals("low", sorted[3].name)
    end)

    it("returns empty table when no resolvers registered", function()
      local sorted = registry.get_all_sorted()
      assert.equals(0, #sorted)
    end)
  end)

  describe("unregister", function()
    it("removes a resolver", function()
      registry.register("env", make_resolver("env", 100))
      assert.is_true(registry.unregister("env"))
      assert.is_false(registry.has("env"))
    end)

    it("returns false for unknown resolver", function()
      assert.is_false(registry.unregister("nonexistent"))
    end)
  end)

  describe("clear", function()
    it("removes all resolvers", function()
      registry.register("a", make_resolver("a", 100))
      registry.register("b", make_resolver("b", 50))
      registry.clear()

      assert.equals(0, registry.count())
    end)
  end)
end)

describe("flemma.secrets.resolvers.chatgpt", function()
  local chatgpt

  before_each(function()
    package.loaded["flemma.secrets.resolvers.chatgpt"] = nil
    chatgpt = require("flemma.secrets.resolvers.chatgpt")
  end)

  describe("supports()", function()
    it("returns true for chatgpt_subscription kind", function()
      -- Seed a throwaway auth file and point the resolver at it via config — the
      -- test must never depend on the host's ~/.codex/auth.json (present only
      -- when the developer happens to be logged in to Codex).
      local tmp = vim.fn.tempname() .. ".json"
      local auth_data = {
        auth_mode = "chatgpt",
        tokens = {
          access_token = "test-access-token",
          account_id = "acct_12345",
        },
      }
      local f = io.open(tmp, "w")
      f:write(json.encode(auth_data))
      f:close()

      local ctx = {
        diagnostic = function() end,
        get_config = function()
          return { auth_file = tmp }
        end,
      }
      assert.is_true(chatgpt:supports({ kind = "chatgpt_subscription", service = "codex" }, ctx))

      os.remove(tmp)
    end)

    it("returns false for other credential kinds", function()
      local ctx = {
        diagnostic = function() end,
        get_config = function()
          return nil
        end,
      }
      assert.is_false(chatgpt:supports({ kind = "api_key", service = "openai" }, ctx))
    end)
  end)

  describe("resolve_async()", function()
    it("reads auth file and returns token with metadata", function()
      local tmp = vim.fn.tempname() .. ".json"
      local auth_data = {
        auth_mode = "chatgpt",
        tokens = {
          access_token = "test-access-token",
          refresh_token = "test-refresh-token",
          account_id = "acct_12345",
          expires_at = os.time() + 3600,
        },
      }
      local f = io.open(tmp, "w")
      f:write(json.encode(auth_data))
      f:close()

      local result_captured
      local ctx = {
        diagnostic = function() end,
        get_config = function()
          return { auth_file = tmp }
        end,
      }
      chatgpt:resolve_async({ kind = "chatgpt_subscription", service = "codex" }, ctx, function(result)
        result_captured = result
      end)

      assert.is_not_nil(result_captured)
      assert.are.equal("test-access-token", result_captured.value)
      assert.are.equal("acct_12345", result_captured.metadata.account_id)
      assert.is_number(result_captured.ttl)

      os.remove(tmp)
    end)

    it("returns nil when auth file does not exist", function()
      local diagnostics = {}
      local ctx = {
        diagnostic = function(_, msg)
          table.insert(diagnostics, msg)
        end,
        get_config = function()
          return { auth_file = "/nonexistent/path/auth.json" }
        end,
      }

      local result_captured = "sentinel"
      chatgpt:resolve_async({ kind = "chatgpt_subscription", service = "codex" }, ctx, function(result)
        result_captured = result
      end)

      assert.is_nil(result_captured)
      assert.is_true(#diagnostics > 0)
    end)

    it("returns nil when auth_mode is not chatgpt", function()
      local tmp = vim.fn.tempname() .. ".json"
      local auth_data = {
        auth_mode = "api_key",
        tokens = { access_token = "test" },
      }
      local f = io.open(tmp, "w")
      f:write(json.encode(auth_data))
      f:close()

      local diagnostics = {}
      local ctx = {
        diagnostic = function(_, msg)
          table.insert(diagnostics, msg)
        end,
        get_config = function()
          return { auth_file = tmp }
        end,
      }

      local result_captured = "sentinel"
      chatgpt:resolve_async({ kind = "chatgpt_subscription", service = "codex" }, ctx, function(result)
        result_captured = result
      end)

      assert.is_nil(result_captured)
      assert.is_true(#diagnostics > 0)

      os.remove(tmp)
    end)
  end)
end)
