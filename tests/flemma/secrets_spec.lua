--- Integration tests for flemma.secrets

local secrets
local registry
local cache

--- Create a mock resolver with async support.
local function make_resolver(name, priority, supported_kinds, value, ttl)
  return {
    name = name,
    priority = priority,
    supports = function(_, credential)
      return vim.tbl_contains(supported_kinds, credential.kind)
    end,
    resolve = function(_, _)
      return { value = value, ttl = ttl }
    end,
    resolve_async = function(_, credential, _ctx, callback)
      if vim.tbl_contains(supported_kinds, credential.kind) then
        callback({ value = value, ttl = ttl })
      else
        callback(nil)
      end
    end,
  }
end

describe("flemma.secrets", function()
  before_each(function()
    package.loaded["flemma.secrets"] = nil
    package.loaded["flemma.secrets.registry"] = nil
    package.loaded["flemma.secrets.cache"] = nil
    package.loaded["flemma.readiness"] = nil
    secrets = require("flemma.secrets")
    registry = require("flemma.secrets.registry")
    cache = require("flemma.secrets.cache")
    require("flemma.readiness")._reset_for_tests()
  end)

  describe("resolve (sync cache hit)", function()
    it("returns cached value sync without suspense", function()
      cache.set("api_key:anthropic", { value = "sk-cached" }, { kind = "api_key", service = "anthropic" })
      local result = secrets.resolve({ kind = "api_key", service = "anthropic" })
      assert.equals("sk-cached", result.value)
    end)

    it("raises suspense on cache miss", function()
      local readiness = require("flemma.readiness")
      local ok, err = pcall(secrets.resolve, { kind = "api_key", service = "missing_svc" })
      assert.is_false(ok)
      assert.is_true(readiness.is_suspense(err))
      assert.is_not_nil(err.boundary)
      assert.matches("missing_svc", err.message)
    end)
  end)

  describe("resolve_async", function()
    it("resolves using the first matching resolver", function()
      registry.register("env", make_resolver("env", 100, { "api_key" }, "sk-from-env"))
      registry.register("keyring", make_resolver("keyring", 50, { "api_key" }, "sk-from-keyring"))

      local result
      secrets.resolve_async({ kind = "api_key", service = "anthropic" }, function(r)
        result = r
      end)
      vim.wait(100, function() return result ~= nil end)
      assert.equals("sk-from-env", result.value)
    end)

    it("falls through to lower priority resolver when higher returns nil", function()
      local failing_resolver = {
        name = "failing",
        priority = 100,
        supports = function(_, _) return true end,
        resolve = function(_, _) return nil end,
        resolve_async = function(_, _credential, _ctx, callback) callback(nil) end,
      }
      registry.register("failing", failing_resolver)
      registry.register("keyring", make_resolver("keyring", 50, { "api_key" }, "sk-from-keyring"))

      local result
      secrets.resolve_async({ kind = "api_key", service = "anthropic" }, function(r)
        result = r
      end)
      vim.wait(100, function() return result ~= nil end)
      assert.equals("sk-from-keyring", result.value)
    end)

    it("skips resolvers that do not support the credential kind", function()
      registry.register("gcloud", make_resolver("gcloud", 25, { "access_token" }, "ya29.token"))
      registry.register("env", make_resolver("env", 100, { "api_key" }, "sk-from-env"))

      local result
      secrets.resolve_async({ kind = "access_token", service = "vertex" }, function(r)
        result = r
      end)
      vim.wait(100, function() return result ~= nil end)
      assert.equals("ya29.token", result.value)
    end)

    it("caches resolved credentials", function()
      local call_count = 0
      local counting_resolver = {
        name = "counting",
        priority = 100,
        supports = function(_, _) return true end,
        resolve = function(_, _) call_count = call_count + 1; return { value = "sk-test" } end,
        resolve_async = function(_, _cred, _ctx, callback) call_count = call_count + 1; callback({ value = "sk-test" }) end,
      }
      registry.register("counting", counting_resolver)

      local done1, done2 = false, false
      secrets.resolve_async({ kind = "api_key", service = "anthropic" }, function() done1 = true end)
      vim.wait(100, function() return done1 end)
      secrets.resolve_async({ kind = "api_key", service = "anthropic" }, function() done2 = true end)
      vim.wait(100, function() return done2 end)
      assert.equals(1, call_count)
    end)

    it("caches different credentials separately", function()
      local call_count = 0
      local counting_resolver = {
        name = "counting",
        priority = 100,
        supports = function(_, _) return true end,
        resolve = function(_, credential) call_count = call_count + 1; return { value = credential.service .. "-key" } end,
        resolve_async = function(_, credential, _ctx, callback) call_count = call_count + 1; callback({ value = credential.service .. "-key" }) end,
      }
      registry.register("counting", counting_resolver)

      local r1, r2
      secrets.resolve_async({ kind = "api_key", service = "anthropic" }, function(r) r1 = r end)
      vim.wait(100, function() return r1 ~= nil end)
      secrets.resolve_async({ kind = "api_key", service = "openai" }, function(r) r2 = r end)
      vim.wait(100, function() return r2 ~= nil end)
      assert.equals(2, call_count)
      assert.equals("anthropic-key", r1.value)
      assert.equals("openai-key", r2.value)
    end)

    it("collects diagnostics when no resolver succeeds", function()
      local resolver_with_diag = {
        name = "mock_diag",
        priority = 100,
        supports = function(_, _, ctx) ctx:diagnostic("not available on this platform"); return false end,
        resolve = function(_, _, _) return nil end,
      }
      registry.register("mock_diag", resolver_with_diag)

      local result, diagnostics
      secrets.resolve_async({ kind = "api_key", service = "test" }, function(r, d)
        result, diagnostics = r, d
      end)
      vim.wait(100, function() return diagnostics ~= nil or result ~= nil end)
      assert.is_nil(result)
      assert.equals(1, #diagnostics)
      assert.equals("mock_diag", diagnostics[1].resolver)
      assert.equals("not available on this platform", diagnostics[1].message)
    end)

    it("collects diagnostics from multiple resolvers", function()
      local resolver_a = {
        name = "resolver_a",
        priority = 100,
        supports = function(_, _, ctx) ctx:diagnostic("reason A"); return false end,
        resolve = function(_, _, _) return nil end,
      }
      local resolver_b = {
        name = "resolver_b",
        priority = 50,
        supports = function(_, _, _) return true end,
        resolve = function(_, _, ctx) ctx:diagnostic("reason B"); return nil end,
        resolve_async = function(_, _cred, ctx, callback) ctx:diagnostic("reason B"); callback(nil) end,
      }
      registry.register("resolver_a", resolver_a)
      registry.register("resolver_b", resolver_b)

      local result, diagnostics
      secrets.resolve_async({ kind = "api_key", service = "test" }, function(r, d)
        result, diagnostics = r, d
      end)
      vim.wait(100, function() return diagnostics ~= nil or result ~= nil end)
      assert.is_nil(result)
      assert.equals(2, #diagnostics)
      assert.equals("reason A", diagnostics[1].message)
      assert.equals("reason B", diagnostics[2].message)
    end)

    it("returns nil diagnostics on successful resolution", function()
      registry.register("env", make_resolver("env", 100, { "api_key" }, "sk-test"))

      local result, diagnostics
      secrets.resolve_async({ kind = "api_key", service = "test" }, function(r, d)
        result, diagnostics = r, d
      end)
      vim.wait(100, function() return result ~= nil end)
      assert.is_not_nil(result)
      assert.is_nil(diagnostics)
    end)

    it("returns nil when no resolvers are registered", function()
      local done = false
      local result
      secrets.resolve_async({ kind = "api_key", service = "anthropic" }, function(r)
        result = r
        done = true
      end)
      vim.wait(100, function() return done end)
      assert.is_nil(result)
    end)
  end)

  describe("suspense + boundary retry", function()
    it("boundary runner walks resolvers and populates cache on success", function()
      registry.register("env", make_resolver("env", 100, { "api_key" }, "from-env"))

      local readiness = require("flemma.readiness")
      local ok, err = pcall(secrets.resolve, { kind = "api_key", service = "mock_svc" })
      assert.is_false(ok)
      assert.is_true(readiness.is_suspense(err))

      local sub_result
      err.boundary:subscribe(function(r) sub_result = r end)
      vim.wait(200, function() return sub_result ~= nil end)
      assert.is_true(sub_result.ok)

      local cached = secrets.resolve({ kind = "api_key", service = "mock_svc" })
      assert.equals("from-env", cached.value)
    end)
  end)

  describe("invalidate", function()
    it("clears a specific cached credential", function()
      cache.set("api_key:anthropic", { value = "sk-test" }, { kind = "api_key", service = "anthropic" })
      local result = secrets.resolve({ kind = "api_key", service = "anthropic" })
      assert.equals("sk-test", result.value)
      secrets.invalidate("api_key", "anthropic")
      local readiness = require("flemma.readiness")
      local ok, err = pcall(secrets.resolve, { kind = "api_key", service = "anthropic" })
      assert.is_false(ok)
      assert.is_true(readiness.is_suspense(err))
    end)
  end)

  describe("invalidate_all", function()
    it("clears all cached credentials", function()
      cache.set("api_key:anthropic", { value = "sk-a" }, { kind = "api_key", service = "anthropic" })
      cache.set("api_key:openai", { value = "sk-o" }, { kind = "api_key", service = "openai" })
      assert.equals("sk-a", secrets.resolve({ kind = "api_key", service = "anthropic" }).value)
      assert.equals("sk-o", secrets.resolve({ kind = "api_key", service = "openai" }).value)
      secrets.invalidate_all()
      local readiness = require("flemma.readiness")
      local ok = pcall(secrets.resolve, { kind = "api_key", service = "anthropic" })
      assert.is_false(ok)
      ok = pcall(secrets.resolve, { kind = "api_key", service = "openai" })
      assert.is_false(ok)
      -- Verify they raise suspense, not just error
      local _, err = pcall(secrets.resolve, { kind = "api_key", service = "anthropic" })
      assert.is_true(readiness.is_suspense(err))
    end)
  end)

  describe("register", function()
    it("registers a resolver via two-arg form", function()
      local resolver = make_resolver("custom", 75, { "api_key" }, "custom-key")
      secrets.register("custom", resolver)

      assert.is_true(registry.has("custom"))
    end)

    it("registers a resolver via single-arg module path", function()
      secrets.setup()
      assert.is_true(registry.has("environment"))
    end)
  end)
end)

describe("secrets config defaults", function()
  it("provides gcloud.path = 'gcloud' after bare setup", function()
    local config = require("flemma.config")
    local schema = require("flemma.config.schema")
    config.init(schema)
    local materialized = config.materialize()
    assert.is_not_nil(materialized.secrets)
    assert.is_not_nil(materialized.secrets.gcloud)
    assert.equals("gcloud", materialized.secrets.gcloud.path)
  end)

  it("preserves user-supplied gcloud path through config.apply", function()
    local config = require("flemma.config")
    local schema = require("flemma.config.schema")
    config.init(schema)
    config.apply(config.LAYERS.SETUP, { secrets = { gcloud = { path = "/nix/store/xyz/bin/gcloud" } } })
    local materialized = config.materialize()
    assert.equals("/nix/store/xyz/bin/gcloud", materialized.secrets.gcloud.path)
  end)
end)
