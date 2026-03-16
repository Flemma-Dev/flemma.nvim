--- Tests for secrets resolver registry

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

describe("flemma.secrets.registry", function()
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

    it("rejects names containing dots", function()
      local resolver = make_resolver("bad.name", 100)
      assert.has_error(function()
        registry.register("bad.name", resolver)
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
