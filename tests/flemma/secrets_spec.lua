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
