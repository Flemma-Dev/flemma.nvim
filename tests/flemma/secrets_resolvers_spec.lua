--- Tests for builtin secrets resolvers

local environment

describe("flemma.secrets.resolvers.environment", function()
  before_each(function()
    package.loaded["flemma.secrets.resolvers.environment"] = nil
    environment = require("flemma.secrets.resolvers.environment")
  end)

  describe("supports", function()
    it("supports any credential kind", function()
      assert.is_true(environment:supports({ kind = "api_key", service = "test" }))
      assert.is_true(environment:supports({ kind = "access_token", service = "test" }))
      assert.is_true(environment:supports({ kind = "service_account", service = "test" }))
    end)
  end)

  describe("resolve", function()
    it("resolves using SERVICE_KIND convention", function()
      vim.env.ANTHROPIC_API_KEY = "sk-test-123"

      local result = environment:resolve({ kind = "api_key", service = "anthropic" })

      assert.is_not_nil(result)
      assert.equals("sk-test-123", result.value)

      vim.env.ANTHROPIC_API_KEY = nil
    end)

    it("returns nil when env var is not set", function()
      vim.env.NONEXISTENT_API_KEY = nil

      local result = environment:resolve({ kind = "api_key", service = "nonexistent" })

      assert.is_nil(result)
    end)

    it("returns nil for empty env var", function()
      vim.env.EMPTY_API_KEY = ""

      local result = environment:resolve({ kind = "api_key", service = "empty" })

      assert.is_nil(result)

      vim.env.EMPTY_API_KEY = nil
    end)

    it("checks aliases after convention", function()
      vim.env.VERTEX_ACCESS_TOKEN = nil
      vim.env.VERTEX_AI_ACCESS_TOKEN = "ya29.from-alias"

      local result = environment:resolve({
        kind = "access_token",
        service = "vertex",
        aliases = { "VERTEX_AI_ACCESS_TOKEN" },
      })

      assert.is_not_nil(result)
      assert.equals("ya29.from-alias", result.value)

      vim.env.VERTEX_AI_ACCESS_TOKEN = nil
    end)

    it("prefers convention over aliases", function()
      vim.env.VERTEX_ACCESS_TOKEN = "ya29.from-convention"
      vim.env.VERTEX_AI_ACCESS_TOKEN = "ya29.from-alias"

      local result = environment:resolve({
        kind = "access_token",
        service = "vertex",
        aliases = { "VERTEX_AI_ACCESS_TOKEN" },
      })

      assert.is_not_nil(result)
      assert.equals("ya29.from-convention", result.value)

      vim.env.VERTEX_ACCESS_TOKEN = nil
      vim.env.VERTEX_AI_ACCESS_TOKEN = nil
    end)

    it("tries aliases in order", function()
      vim.env.FIRST_ALIAS = nil
      vim.env.SECOND_ALIAS = "from-second"

      local result = environment:resolve({
        kind = "api_key",
        service = "test",
        aliases = { "FIRST_ALIAS", "SECOND_ALIAS" },
      })

      assert.is_not_nil(result)
      assert.equals("from-second", result.value)

      vim.env.SECOND_ALIAS = nil
    end)
  end)
end)
