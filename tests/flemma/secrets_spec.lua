--- Integration tests for flemma.secrets

local secrets
local registry

--- Create a mock resolver.
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
  }
end

describe("flemma.secrets", function()
  before_each(function()
    package.loaded["flemma.secrets"] = nil
    package.loaded["flemma.secrets.registry"] = nil
    package.loaded["flemma.secrets.cache"] = nil
    secrets = require("flemma.secrets")
    registry = require("flemma.secrets.registry")
    require("flemma.secrets.cache")
  end)

  describe("resolve", function()
    it("returns nil when no resolvers are registered", function()
      local result = secrets.resolve({
        kind = "api_key",
        service = "anthropic",
      })
      assert.is_nil(result)
    end)

    it("resolves using the first matching resolver", function()
      registry.register("env", make_resolver("env", 100, { "api_key" }, "sk-from-env"))
      registry.register("keyring", make_resolver("keyring", 50, { "api_key" }, "sk-from-keyring"))

      local result = secrets.resolve({
        kind = "api_key",
        service = "anthropic",
      })
      assert.is_not_nil(result)
      assert.equals("sk-from-env", result.value)
    end)

    it("falls through to lower priority resolver when higher returns nil", function()
      local failing_resolver = {
        name = "failing",
        priority = 100,
        supports = function(_, _)
          return true
        end,
        resolve = function(_, _)
          return nil
        end,
      }
      registry.register("failing", failing_resolver)
      registry.register("keyring", make_resolver("keyring", 50, { "api_key" }, "sk-from-keyring"))

      local result = secrets.resolve({
        kind = "api_key",
        service = "anthropic",
      })
      assert.is_not_nil(result)
      assert.equals("sk-from-keyring", result.value)
    end)

    it("skips resolvers that do not support the credential kind", function()
      registry.register("gcloud", make_resolver("gcloud", 25, { "access_token" }, "ya29.token"))
      registry.register("env", make_resolver("env", 100, { "api_key" }, "sk-from-env"))

      local result = secrets.resolve({
        kind = "access_token",
        service = "vertex",
      })
      assert.is_not_nil(result)
      assert.equals("ya29.token", result.value)
    end)

    it("caches resolved credentials", function()
      local call_count = 0
      local counting_resolver = {
        name = "counting",
        priority = 100,
        supports = function(_, _)
          return true
        end,
        resolve = function(_, _)
          call_count = call_count + 1
          return { value = "sk-test" }
        end,
      }
      registry.register("counting", counting_resolver)

      secrets.resolve({ kind = "api_key", service = "anthropic" })
      secrets.resolve({ kind = "api_key", service = "anthropic" })

      assert.equals(1, call_count)
    end)

    it("caches different credentials separately", function()
      local call_count = 0
      local counting_resolver = {
        name = "counting",
        priority = 100,
        supports = function(_, _)
          return true
        end,
        resolve = function(_, credential)
          call_count = call_count + 1
          return { value = credential.service .. "-key" }
        end,
      }
      registry.register("counting", counting_resolver)

      local r1 = secrets.resolve({ kind = "api_key", service = "anthropic" })
      local r2 = secrets.resolve({ kind = "api_key", service = "openai" })

      assert.equals(2, call_count)
      assert.equals("anthropic-key", r1.value)
      assert.equals("openai-key", r2.value)
    end)

    it("returns diagnostics as second value when resolution fails", function()
      local resolver_with_diag = {
        name = "mock_diag",
        priority = 100,
        supports = function(_, _, ctx)
          ctx:diagnostic("not available on this platform")
          return false
        end,
        resolve = function(_, _, _)
          return nil
        end,
      }
      registry.register("mock_diag", resolver_with_diag)

      local result, diagnostics = secrets.resolve({
        kind = "api_key",
        service = "test",
      })
      assert.is_nil(result)
      assert.is_not_nil(diagnostics)
      assert.equals(1, #diagnostics)
      assert.equals("mock_diag", diagnostics[1].resolver)
      assert.equals("not available on this platform", diagnostics[1].message)
    end)

    it("collects diagnostics from multiple resolvers", function()
      local resolver_a = {
        name = "resolver_a",
        priority = 100,
        supports = function(_, _, ctx)
          ctx:diagnostic("reason A")
          return false
        end,
        resolve = function(_, _, _)
          return nil
        end,
      }
      local resolver_b = {
        name = "resolver_b",
        priority = 50,
        supports = function(_, _, _)
          return true
        end,
        resolve = function(_, _, ctx)
          ctx:diagnostic("reason B")
          return nil
        end,
      }
      registry.register("resolver_a", resolver_a)
      registry.register("resolver_b", resolver_b)

      local result, diagnostics = secrets.resolve({
        kind = "api_key",
        service = "test",
      })
      assert.is_nil(result)
      assert.equals(2, #diagnostics)
      assert.equals("reason A", diagnostics[1].message)
      assert.equals("reason B", diagnostics[2].message)
    end)

    it("returns no diagnostics on successful resolution", function()
      registry.register("env", make_resolver("env", 100, { "api_key" }, "sk-test"))

      local result, diagnostics = secrets.resolve({
        kind = "api_key",
        service = "test",
      })
      assert.is_not_nil(result)
      assert.is_nil(diagnostics)
    end)
  end)

  describe("invalidate", function()
    it("clears a specific cached credential", function()
      local call_count = 0
      local resolver = {
        name = "env",
        priority = 100,
        supports = function(_, _)
          return true
        end,
        resolve = function(_, _)
          call_count = call_count + 1
          return { value = "sk-test" }
        end,
      }
      registry.register("env", resolver)

      secrets.resolve({ kind = "api_key", service = "anthropic" })
      assert.equals(1, call_count)

      secrets.invalidate("api_key", "anthropic")
      secrets.resolve({ kind = "api_key", service = "anthropic" })
      assert.equals(2, call_count)
    end)
  end)

  describe("invalidate_all", function()
    it("clears all cached credentials", function()
      local call_count = 0
      local resolver = {
        name = "env",
        priority = 100,
        supports = function(_, _)
          return true
        end,
        resolve = function(_, _)
          call_count = call_count + 1
          return { value = "sk-test" }
        end,
      }
      registry.register("env", resolver)

      secrets.resolve({ kind = "api_key", service = "anthropic" })
      secrets.resolve({ kind = "api_key", service = "openai" })
      assert.equals(2, call_count)

      secrets.invalidate_all()
      secrets.resolve({ kind = "api_key", service = "anthropic" })
      secrets.resolve({ kind = "api_key", service = "openai" })
      assert.equals(4, call_count)
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
    local schema = require("flemma.config.schema.definition")
    config.init(schema)
    local materialized = config.materialize()
    assert.is_not_nil(materialized.secrets)
    assert.is_not_nil(materialized.secrets.gcloud)
    assert.equals("gcloud", materialized.secrets.gcloud.path)
  end)

  it("preserves user-supplied gcloud path through config.apply", function()
    local config = require("flemma.config")
    local schema = require("flemma.config.schema.definition")
    config.init(schema)
    config.apply(config.LAYERS.SETUP, { secrets = { gcloud = { path = "/nix/store/xyz/bin/gcloud" } } })
    local materialized = config.materialize()
    assert.equals("/nix/store/xyz/bin/gcloud", materialized.secrets.gcloud.path)
  end)
end)
