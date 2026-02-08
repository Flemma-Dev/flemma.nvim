package.loaded["flemma.tools"] = nil
package.loaded["flemma.tools.registry"] = nil
package.loaded["flemma.tools.definitions.calculator"] = nil
package.loaded["flemma.tools.definitions.bash"] = nil
package.loaded["flemma.tools.definitions.read"] = nil
package.loaded["flemma.tools.definitions.edit"] = nil
package.loaded["flemma.tools.definitions.write"] = nil
package.loaded["flemma.buffer.opt"] = nil

local tools = require("flemma.tools")
local opt = require("flemma.buffer.opt")
local pipeline = require("flemma.pipeline")
local ctx = require("flemma.context")

--- Find a tool by name in an Anthropic-format tools array ({name=...})
local function find_anthropic_tool(tools_array, name)
  for _, t in ipairs(tools_array) do
    if t.name == name then
      return t
    end
  end
end

describe("flemma.opt", function()
  before_each(function()
    tools.clear()
    tools.setup()
  end)

  describe("create()", function()
    it("returns opt_proxy and resolve function", function()
      local opt_proxy, resolve = opt.create()
      assert.is_not_nil(opt_proxy)
      assert.is_function(resolve)
    end)

    it("resolve returns empty table when no options touched", function()
      local _, resolve = opt.create()
      local resolved = resolve()
      assert.is_nil(resolved.tools)
    end)
  end)

  describe("tools default values", function()
    it("default tools match registered enabled tools", function()
      local opt_proxy = opt.create()
      local current = opt_proxy.tools:get()

      local all = tools.get_all()
      local expected = {}
      for name in pairs(all) do
        table.insert(expected, name)
      end
      table.sort(expected)
      table.sort(current)

      assert.are.same(expected, current)
    end)
  end)

  describe("direct assignment", function()
    it("overrides tools list completely", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools = { "bash", "read" }
      local resolved = resolve()
      table.sort(resolved.tools)
      assert.are.same({ "bash", "read" }, resolved.tools)
    end)

    it("errors on non-table value", function()
      local opt_proxy = opt.create()
      assert.has_error(function()
        opt_proxy.tools = "bash"
      end, "flemma.opt.tools: expected table, got string")
    end)
  end)

  describe(":remove()", function()
    it("removes a single tool by name", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools:remove("calculator")
      local resolved = resolve()

      local has_calculator = false
      for _, name in ipairs(resolved.tools) do
        if name == "calculator" then
          has_calculator = true
        end
      end
      assert.is_false(has_calculator)
    end)

    it("removes multiple tools from a table", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools:remove({ "calculator", "bash" })
      local resolved = resolve()

      local found = {}
      for _, name in ipairs(resolved.tools) do
        found[name] = true
      end
      assert.is_nil(found["calculator"])
      assert.is_nil(found["bash"])
    end)

    it("errors on unknown tool name", function()
      local opt_proxy = opt.create()
      assert.has_error(function()
        opt_proxy.tools:remove("nonexistent_tool")
      end, "flemma.opt: unknown value 'nonexistent_tool'")
    end)
  end)

  describe(":append()", function()
    it("adds a tool at the end", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools = { "bash" }
      opt_proxy.tools:append("read")
      local resolved = resolve()
      assert.are.same({ "bash", "read" }, resolved.tools)
    end)

    it("accepts a table of names", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools = { "bash" }
      opt_proxy.tools:append({ "read", "write" })
      local resolved = resolve()
      assert.are.same({ "bash", "read", "write" }, resolved.tools)
    end)
  end)

  describe(":prepend()", function()
    it("adds a tool at the beginning", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools = { "bash" }
      opt_proxy.tools:prepend("read")
      local resolved = resolve()
      assert.are.same({ "read", "bash" }, resolved.tools)
    end)

    it("accepts a table of names preserving order", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools = { "bash" }
      opt_proxy.tools:prepend({ "read", "write" })
      local resolved = resolve()
      assert.are.same({ "read", "write", "bash" }, resolved.tools)
    end)
  end)

  describe(":get()", function()
    it("returns current value", function()
      local opt_proxy = opt.create()
      opt_proxy.tools = { "bash", "read" }
      local current = opt_proxy.tools:get()
      assert.are.same({ "bash", "read" }, current)
    end)

    it("returns a copy, not a reference", function()
      local opt_proxy = opt.create()
      opt_proxy.tools = { "bash", "read" }
      local copy = opt_proxy.tools:get()
      table.insert(copy, "write")
      local current = opt_proxy.tools:get()
      assert.are.equal(2, #current)
    end)
  end)

  describe("chaining", function()
    it("supports chaining remove then append", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools:remove("calculator")
      opt_proxy.tools:append("calculator")
      local resolved = resolve()

      -- calculator should be at the end
      assert.are.equal("calculator", resolved.tools[#resolved.tools])
    end)
  end)

  describe("operator + (append)", function()
    it("appends a single value", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools = { "bash" }
      opt_proxy.tools = opt_proxy.tools + "read"
      local resolved = resolve()
      assert.are.same({ "bash", "read" }, resolved.tools)
    end)

    it("appends multiple values from a table", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools = { "bash" }
      opt_proxy.tools = opt_proxy.tools + { "read", "write" }
      local resolved = resolve()
      assert.are.same({ "bash", "read", "write" }, resolved.tools)
    end)
  end)

  describe("operator - (remove)", function()
    it("removes a single value", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools = { "bash", "read", "write" }
      opt_proxy.tools = opt_proxy.tools - "read"
      local resolved = resolve()
      assert.are.same({ "bash", "write" }, resolved.tools)
    end)

    it("removes multiple values from a table", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools = { "bash", "read", "write" }
      opt_proxy.tools = opt_proxy.tools - { "read", "write" }
      local resolved = resolve()
      assert.are.same({ "bash" }, resolved.tools)
    end)
  end)

  describe("operator ^ (prepend)", function()
    it("prepends a single value", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools = { "bash" }
      opt_proxy.tools = opt_proxy.tools ^ "read"
      local resolved = resolve()
      assert.are.same({ "read", "bash" }, resolved.tools)
    end)

    it("prepends multiple values preserving order", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools = { "bash" }
      opt_proxy.tools = opt_proxy.tools ^ { "read", "write" }
      local resolved = resolve()
      assert.are.same({ "read", "write", "bash" }, resolved.tools)
    end)
  end)

  describe("invalid option name", function()
    it("errors on read of unknown option", function()
      local opt_proxy = opt.create()
      assert.has_error(function()
        local _ = opt_proxy.unknown_option
      end, "flemma.opt: unknown option 'unknown_option'")
    end)

    it("errors on write of unknown option", function()
      local opt_proxy = opt.create()
      assert.has_error(function()
        opt_proxy.unknown_option = { "value" }
      end, "flemma.opt: unknown option 'unknown_option'")
    end)
  end)

  describe("statelessness", function()
    it("each create() starts fresh from defaults", function()
      local opt_proxy1, resolve1 = opt.create()
      opt_proxy1.tools = { "bash" }
      local resolved1 = resolve1()
      assert.are.same({ "bash" }, resolved1.tools)

      -- Second create should have full defaults again
      local opt_proxy2 = opt.create()
      local current = opt_proxy2.tools:get()
      assert.is_true(#current > 1) -- more than just "bash"
    end)
  end)

  describe("unknown tool names", function()
    it("errors on unknown name in assignment", function()
      local opt_proxy = opt.create()
      assert.has_error(function()
        opt_proxy.tools = { "bash", "nonexistent_tool", "read" }
      end, "flemma.opt: unknown value 'nonexistent_tool'")
    end)

    it("errors on unknown name in append", function()
      local opt_proxy = opt.create()
      assert.has_error(function()
        opt_proxy.tools:append("nonexistent_tool")
      end, "flemma.opt: unknown value 'nonexistent_tool'")
    end)

    it("errors on unknown name in prepend", function()
      local opt_proxy = opt.create()
      assert.has_error(function()
        opt_proxy.tools:prepend("nonexistent_tool")
      end, "flemma.opt: unknown value 'nonexistent_tool'")
    end)

    it("suggests close match for typos", function()
      local opt_proxy = opt.create()
      assert.has_error(function()
        opt_proxy.tools:append("calculater")
      end, "flemma.opt: unknown value 'calculater'. Did you mean 'calculator'?")
    end)
  end)

  describe("disabled tools", function()
    it("disabled tools are not in default tools list", function()
      local opt_proxy = opt.create()
      local current = opt_proxy.tools:get()
      local found = {}
      for _, name in ipairs(current) do
        found[name] = true
      end
      assert.is_nil(found["calculator_async"])
    end)

    it("disabled tools can be explicitly appended", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools:append("calculator_async")
      local resolved = resolve()
      local found = {}
      for _, name in ipairs(resolved.tools) do
        found[name] = true
      end
      assert.is_true(found["calculator_async"] == true)
    end)

    it("disabled tools can be set via direct assignment", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools = { "calculator_async" }
      local resolved = resolve()
      assert.are.same({ "calculator_async" }, resolved.tools)
    end)

    it("provider includes disabled tool when explicitly listed in opts", function()
      local provider = require("flemma.provider.providers.anthropic")
      local p = provider.new({ model = "claude-sonnet-4-20250514", max_tokens = 100 })

      local prompt = {
        history = { { role = "user", parts = { { kind = "text", text = "test" } } } },
        system = nil,
        opts = { tools = { "bash", "calculator_async" } },
      }

      local req = p:build_request(prompt)
      assert.is_not_nil(req.tools)
      assert.equals(2, #req.tools)
      assert.is_not_nil(find_anthropic_tool(req.tools, "calculator_async"))
    end)
  end)

  describe("frontmatter pipeline", function()
    it("flemma.opt.tools:remove() filters opts in prompt", function()
      local lines = {
        "```lua",
        'flemma.opt.tools:remove("calculator")',
        "```",
        "@You: test",
      }
      local context = ctx.from_file("test.chat")
      local prompt = pipeline.run(lines, context)

      assert.is_not_nil(prompt.opts)
      assert.is_not_nil(prompt.opts.tools)

      local found = {}
      for _, name in ipairs(prompt.opts.tools) do
        found[name] = true
      end
      assert.is_nil(found["calculator"])
      assert.is_true(found["bash"] == true)
      assert.is_true(found["read"] == true)
    end)

    it("flemma.opt.tools = {...} allows only specified tools", function()
      local lines = {
        "```lua",
        'flemma.opt.tools = {"bash"}',
        "```",
        "@You: test",
      }
      local context = ctx.from_file("test.chat")
      local prompt = pipeline.run(lines, context)

      assert.is_not_nil(prompt.opts)
      assert.are.same({ "bash" }, prompt.opts.tools)
    end)

    it("no frontmatter leaves prompt.opts nil", function()
      local lines = {
        "@You: test",
      }
      local context = ctx.from_file("test.chat")
      local prompt = pipeline.run(lines, context)

      assert.is_nil(prompt.opts)
    end)

    it("frontmatter without flemma.opt usage leaves opts.tools nil", function()
      local lines = {
        "```lua",
        "x = 5",
        "```",
        "@You: test",
      }
      local context = ctx.from_file("test.chat")
      local prompt = pipeline.run(lines, context)

      assert.is_nil(prompt.opts.tools)
    end)

    it("flemma does not leak to {{ }} expressions", function()
      local lines = {
        "```lua",
        'flemma.opt.tools:remove("calculator")',
        "```",
        "@You: type is {{ type(flemma) }}",
      }
      local context = ctx.from_file("test.chat")
      local prompt = pipeline.run(lines, context)

      -- flemma should be nil in expression env, so type(flemma) returns "nil"
      local user_msg = prompt.history[1]
      local all_text = {}
      for _, p in ipairs(user_msg.parts) do
        if p.kind == "text" then
          table.insert(all_text, p.text or "")
        end
      end
      local content = table.concat(all_text, "")
      assert.are.equal("type is nil", content)
    end)
  end)

  describe("provider build_request", function()
    it("anthropic filters tools by opts", function()
      local provider = require("flemma.provider.providers.anthropic")
      local p = provider.new({ model = "claude-sonnet-4-20250514", max_tokens = 100 })

      local prompt = {
        history = { { role = "user", parts = { { kind = "text", text = "test" } } } },
        system = nil,
        opts = { tools = { "bash" } },
      }

      local req = p:build_request(prompt)
      assert.is_not_nil(req.tools)
      assert.equals(1, #req.tools)
      assert.is_not_nil(find_anthropic_tool(req.tools, "bash"))
      assert.is_nil(find_anthropic_tool(req.tools, "calculator"))
    end)

    it("anthropic uses all tools when opts is nil", function()
      local provider = require("flemma.provider.providers.anthropic")
      local p = provider.new({ model = "claude-sonnet-4-20250514", max_tokens = 100 })

      local prompt = {
        history = { { role = "user", parts = { { kind = "text", text = "test" } } } },
        system = nil,
      }

      local req = p:build_request(prompt)
      assert.is_not_nil(req.tools)
      assert.equals(5, #req.tools)
    end)

    it("openai filters tools by opts", function()
      local provider = require("flemma.provider.providers.openai")
      local p = provider.new({ model = "gpt-4o", max_tokens = 100 })

      local prompt = {
        history = { { role = "user", parts = { { kind = "text", text = "test" } } } },
        system = nil,
        opts = { tools = { "bash", "read" } },
      }

      local req = p:build_request(prompt)
      assert.is_not_nil(req.tools)
      assert.equals(2, #req.tools)
    end)

    it("vertex filters tools by opts", function()
      local provider = require("flemma.provider.providers.vertex")
      local p = provider.new({ model = "gemini-2.0-flash", max_tokens = 100, project_id = "test", region = "us" })

      local prompt = {
        history = { { role = "user", parts = { { kind = "text", text = "test" } } } },
        system = nil,
        opts = { tools = { "bash" } },
      }

      local req = p:build_request(prompt)
      assert.is_not_nil(req.tools)
      assert.equals(1, #req.tools)
      assert.equals(1, #req.tools[1].functionDeclarations)
      assert.equals("bash", req.tools[1].functionDeclarations[1].name)
    end)

    it("sends no tools when opts.tools is empty", function()
      local provider = require("flemma.provider.providers.anthropic")
      local p = provider.new({ model = "claude-sonnet-4-20250514", max_tokens = 100 })

      local prompt = {
        history = { { role = "user", parts = { { kind = "text", text = "test" } } } },
        system = nil,
        opts = { tools = {} },
      }

      local req = p:build_request(prompt)
      assert.is_nil(req.tools)
    end)
  end)
end)
