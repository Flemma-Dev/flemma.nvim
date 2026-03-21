describe("provider.get_trailing_keys", function()
  local base

  before_each(function()
    package.loaded["flemma.provider.base"] = nil
    package.loaded["flemma.provider.providers.anthropic"] = nil
    package.loaded["flemma.provider.providers.openai"] = nil
    package.loaded["flemma.provider.providers.vertex"] = nil
    base = require("flemma.provider.base")
  end)

  describe("base provider", function()
    it("has a get_trailing_keys method", function()
      assert.is_function(base.get_trailing_keys)
    end)

    it("returns an empty table by default", function()
      local provider = setmetatable({
        parameters = {},
        state = {},
      }, { __index = base })
      local keys = provider:get_trailing_keys()
      assert.are.same({}, keys)
    end)
  end)

  describe("Anthropic provider", function()
    it("returns system, tools, messages as trailing keys", function()
      local anthropic = require("flemma.provider.providers.anthropic")
      local provider = anthropic.new({ model = "claude-sonnet-4-20250514" })
      local keys = provider:get_trailing_keys()
      assert.are.same({ "system", "tools", "messages" }, keys)
    end)
  end)

  describe("OpenAI provider", function()
    it("returns tools, input as trailing keys", function()
      local openai = require("flemma.provider.providers.openai")
      local provider = openai.new({ model = "gpt-4o" })
      local keys = provider:get_trailing_keys()
      assert.are.same({ "tools", "input" }, keys)
    end)
  end)

  describe("Vertex provider", function()
    it("returns tools, contents as trailing keys", function()
      local vertex = require("flemma.provider.providers.vertex")
      local provider = vertex.new({ model = "gemini-2.5-pro" })
      local keys = provider:get_trailing_keys()
      assert.are.same({ "tools", "contents" }, keys)
    end)
  end)
end)
