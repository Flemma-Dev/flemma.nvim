package.loaded["flemma.tools"] = nil
package.loaded["flemma.tools.registry"] = nil
package.loaded["flemma.tools.presets"] = nil
package.loaded["flemma.tools.definitions.calculator"] = nil
package.loaded["flemma.tools.definitions.bash"] = nil
package.loaded["flemma.tools.definitions.read"] = nil
package.loaded["flemma.tools.definitions.edit"] = nil
package.loaded["flemma.tools.definitions.write"] = nil
package.loaded["flemma.buffer.opt"] = nil

local tools = require("flemma.tools")
local opt = require("flemma.buffer.opt")
local parser = require("flemma.parser")
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

local presets = require("flemma.tools.presets")

describe("flemma.opt", function()
  before_each(function()
    tools.clear()
    tools.setup()
    presets.setup(nil)
  end)

  after_each(function()
    presets.clear()
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
      local prompt = pipeline.run(parser.parse_lines(lines), context)

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
      local prompt = pipeline.run(parser.parse_lines(lines), context)

      assert.is_not_nil(prompt.opts)
      assert.are.same({ "bash" }, prompt.opts.tools)
    end)

    it("no frontmatter leaves prompt.opts nil", function()
      local lines = {
        "@You: test",
      }
      local context = ctx.from_file("test.chat")
      local prompt = pipeline.run(parser.parse_lines(lines), context)

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
      local prompt = pipeline.run(parser.parse_lines(lines), context)

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
      local prompt = pipeline.run(parser.parse_lines(lines), context)

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

  describe("provider parameter overrides", function()
    it("flemma.opt.anthropic.cache_retention resolves correctly", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.anthropic.cache_retention = "long"
      local resolved = resolve()
      assert.are.same({ cache_retention = "long" }, resolved.anthropic)
    end)

    it("flemma.opt.anthropic.thinking_budget resolves correctly", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.anthropic.thinking_budget = 20000
      local resolved = resolve()
      assert.are.same({ thinking_budget = 20000 }, resolved.anthropic)
    end)

    it("table assignment works for provider params", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.anthropic = { thinking_budget = 5000 }
      local resolved = resolve()
      assert.are.same({ thinking_budget = 5000 }, resolved.anthropic)
    end)

    it("provider params don't leak across create() calls", function()
      local opt_proxy1, resolve1 = opt.create()
      opt_proxy1.anthropic.cache_retention = "long"
      local resolved1 = resolve1()
      assert.are.same({ cache_retention = "long" }, resolved1.anthropic)

      local _, resolve2 = opt.create()
      local resolved2 = resolve2()
      assert.is_nil(resolved2.anthropic)
    end)

    it("errors on non-table assignment to provider key", function()
      local opt_proxy = opt.create()
      assert.has_error(function()
        opt_proxy.anthropic = "bad"
      end, "flemma.opt.anthropic: expected table, got string")
    end)

    it("provider params flow through frontmatter pipeline", function()
      local lines = {
        "```lua",
        'flemma.opt.anthropic.cache_retention = "long"',
        "```",
        "@You: test",
      }
      local context = ctx.from_file("test.chat")
      local prompt = pipeline.run(parser.parse_lines(lines), context)

      assert.is_not_nil(prompt.opts)
      assert.is_not_nil(prompt.opts.anthropic)
      assert.are.same({ cache_retention = "long" }, prompt.opts.anthropic)
    end)

    it("empty provider params are not included in resolve", function()
      local opt_proxy, resolve = opt.create()
      local _ = opt_proxy.anthropic -- just access, no assignment
      local resolved = resolve()
      assert.is_nil(resolved.anthropic)
    end)
  end)

  describe("auto_approve", function()
    it("setting string list resolves correctly", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools.auto_approve = { "calculator", "read" }
      local resolved = resolve()
      assert.are.same({ "calculator", "read" }, resolved.auto_approve)
    end)

    it("setting function resolves correctly", function()
      local opt_proxy, resolve = opt.create()
      local fn = function()
        return true
      end
      opt_proxy.tools.auto_approve = fn
      local resolved = resolve()
      assert.equals(fn, resolved.auto_approve)
    end)

    it("reading auto_approve back returns a ListOption with the set value", function()
      local opt_proxy = opt.create()
      opt_proxy.tools.auto_approve = { "calculator" }
      local auto_approve = opt_proxy.tools.auto_approve
      assert.is_not_nil(auto_approve)
      assert.are.same({ "calculator" }, auto_approve:get())
    end)

    it("not touching auto_approve results in nil in frontmatter opts", function()
      local _, resolve = opt.create()
      local resolved = resolve()
      assert.is_nil(resolved.auto_approve)
    end)

    it("reading unset auto_approve returns nil", function()
      local opt_proxy = opt.create()
      assert.is_nil(opt_proxy.tools.auto_approve)
    end)

    it("errors on number value", function()
      local opt_proxy = opt.create()
      assert.has_error(function()
        opt_proxy.tools.auto_approve = 42
      end, "flemma.opt.tools.auto_approve: expected table or function, got number")
    end)

    it("errors on string value", function()
      local opt_proxy = opt.create()
      assert.has_error(function()
        opt_proxy.tools.auto_approve = "calculator"
      end, "flemma.opt.tools.auto_approve: expected table or function, got string")
    end)

    it("does not leak across create() calls", function()
      local opt_proxy1, resolve1 = opt.create()
      opt_proxy1.tools.auto_approve = { "calculator" }
      local resolved1 = resolve1()
      assert.are.same({ "calculator" }, resolved1.auto_approve)

      local _, resolve2 = opt.create()
      local resolved2 = resolve2()
      assert.is_nil(resolved2.auto_approve)
    end)

    it("flows through frontmatter pipeline", function()
      local lines = {
        "```lua",
        'flemma.opt.tools.auto_approve = { "calculator" }',
        "```",
        "@You: test",
      }
      local context = ctx.from_file("test.chat")
      local prompt = pipeline.run(parser.parse_lines(lines), context)

      assert.is_not_nil(prompt.opts)
      assert.are.same({ "calculator" }, prompt.opts.auto_approve)
    end)

    it("function flows through frontmatter pipeline", function()
      local lines = {
        "```lua",
        "flemma.opt.tools.auto_approve = function(tool_name)",
        '  if tool_name == "calculator" then return true end',
        "end",
        "```",
        "@You: test",
      }
      local context = ctx.from_file("test.chat")
      local prompt = pipeline.run(parser.parse_lines(lines), context)

      assert.is_not_nil(prompt.opts)
      assert.is_not_nil(prompt.opts.auto_approve)
      assert.equals("function", type(prompt.opts.auto_approve))
    end)
  end)

  describe("general parameter overrides", function()
    it("flemma.opt.cache_retention resolves correctly", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.cache_retention = "long"
      local resolved = resolve()
      assert.are.same({ cache_retention = "long" }, resolved.parameters)
    end)

    it("flemma.opt.max_tokens resolves correctly", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.max_tokens = 8000
      local resolved = resolve()
      assert.are.same({ max_tokens = 8000 }, resolved.parameters)
    end)

    it("reading general param returns set value", function()
      local opt_proxy = opt.create()
      opt_proxy.temperature = 1.5
      assert.are.equal(1.5, opt_proxy.temperature)
    end)

    it("reading unset general param returns nil", function()
      local opt_proxy = opt.create()
      assert.is_nil(opt_proxy.cache_retention)
    end)

    it("general params don't leak across create() calls", function()
      local opt_proxy1, resolve1 = opt.create()
      opt_proxy1.cache_retention = "long"
      local resolved1 = resolve1()
      assert.are.same({ cache_retention = "long" }, resolved1.parameters)

      local _, resolve2 = opt.create()
      local resolved2 = resolve2()
      assert.is_nil(resolved2.parameters)
    end)

    it("general params flow through frontmatter pipeline", function()
      local lines = {
        "```lua",
        'flemma.opt.cache_retention = "long"',
        "```",
        "@You: test",
      }
      local context = ctx.from_file("test.chat")
      local prompt = pipeline.run(parser.parse_lines(lines), context)

      assert.is_not_nil(prompt.opts)
      assert.is_not_nil(prompt.opts.parameters)
      assert.are.equal("long", prompt.opts.parameters.cache_retention)
    end)

    it("provider-specific and general params coexist independently", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.cache_retention = "long"
      opt_proxy.anthropic.thinking_budget = 4096
      local resolved = resolve()
      assert.are.same({ cache_retention = "long" }, resolved.parameters)
      assert.are.same({ thinking_budget = 4096 }, resolved.anthropic)
    end)

    it("errors on unknown option name", function()
      local opt_proxy = opt.create()
      assert.has_error(function()
        opt_proxy.unknown_thing = "value"
      end, "flemma.opt: unknown option 'unknown_thing'")
    end)
  end)

  describe("sandbox", function()
    it("boolean true sets { enabled = true }", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.sandbox = true
      local resolved = resolve()
      assert.are.same({ enabled = true }, resolved.sandbox)
    end)

    it("boolean false sets { enabled = false }", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.sandbox = false
      local resolved = resolve()
      assert.are.same({ enabled = false }, resolved.sandbox)
    end)

    it("table value works as before", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.sandbox = { enabled = true, policy = { network = false } }
      local resolved = resolve()
      assert.are.same({ enabled = true, policy = { network = false } }, resolved.sandbox)
    end)

    it("boolean after table deep-merges", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.sandbox = { policy = { network = false } }
      opt_proxy.sandbox = false
      local resolved = resolve()
      assert.are.same({ enabled = false, policy = { network = false } }, resolved.sandbox)
    end)

    it("not touching sandbox results in nil in frontmatter opts", function()
      local _, resolve = opt.create()
      local resolved = resolve()
      assert.is_nil(resolved.sandbox)
    end)

    it("reading unset sandbox returns nil", function()
      local opt_proxy = opt.create()
      assert.is_nil(opt_proxy.sandbox)
    end)

    it("errors on number value", function()
      local opt_proxy = opt.create()
      assert.has_error(function()
        opt_proxy.sandbox = 42
      end, "flemma.opt.sandbox: expected boolean or table, got number")
    end)

    it("errors on string value", function()
      local opt_proxy = opt.create()
      assert.has_error(function()
        opt_proxy.sandbox = "yes"
      end, "flemma.opt.sandbox: expected boolean or table, got string")
    end)

    it("flows through frontmatter pipeline", function()
      local lines = {
        "```lua",
        "flemma.opt.sandbox = true",
        "```",
        "@You: test",
      }
      local context = ctx.from_file("test.chat")
      local prompt = pipeline.run(parser.parse_lines(lines), context)

      assert.is_not_nil(prompt.opts)
      assert.are.same({ enabled = true }, prompt.opts.sandbox)
    end)

    it("table flows through frontmatter pipeline", function()
      local lines = {
        "```lua",
        'flemma.opt.sandbox = { enabled = true, policy = { rw_paths = { "$CWD" } } }',
        "```",
        "@You: test",
      }
      local context = ctx.from_file("test.chat")
      local prompt = pipeline.run(parser.parse_lines(lines), context)

      assert.is_not_nil(prompt.opts)
      assert.is_not_nil(prompt.opts.sandbox)
      assert.is_true(prompt.opts.sandbox.enabled)
      assert.are.same({ "$CWD" }, prompt.opts.sandbox.policy.rw_paths)
    end)
  end)

  describe("module path support", function()
    before_each(function()
      tools.clear()
      tools.setup()

      package.preload["test.opt.tools"] = function()
        return {
          definitions = {
            {
              name = "opt_test_tool",
              description = "Tool from module",
              input_schema = { type = "object" },
            },
          },
        }
      end
    end)

    after_each(function()
      package.preload["test.opt.tools"] = nil
      package.loaded["test.opt.tools"] = nil
    end)

    it("append accepts a module path", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools:append("test.opt.tools")
      local resolved = resolve()
      assert.is_not_nil(resolved.tools)
      local found = false
      for _, name in ipairs(resolved.tools) do
        if name == "test.opt.tools" then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("remove accepts a module path that was appended", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools:append("test.opt.tools")
      opt_proxy.tools:remove("test.opt.tools")
      local resolved = resolve()
      local found = false
      if resolved.tools then
        for _, name in ipairs(resolved.tools) do
          if name == "test.opt.tools" then
            found = true
          end
        end
      end
      assert.is_false(found)
    end)

    it("errors on nonexistent module path", function()
      local opt_proxy = opt.create()
      assert.has_error(function()
        opt_proxy.tools:append("nonexistent.module.path")
      end)
    end)

    it("plain names still use Levenshtein validation", function()
      local opt_proxy = opt.create()
      assert.has_error(function()
        opt_proxy.tools:append("calculater")
      end, "flemma.opt: unknown value 'calculater'. Did you mean 'calculator'?")
    end)
  end)

  describe("auto_approve as ListOption", function()
    it("supports :remove() on a preset entry", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools.auto_approve = { "$default" }
      opt_proxy.tools.auto_approve:remove("$default")
      local resolved = resolve()
      assert.are.same({}, resolved.auto_approve)
    end)

    it("supports :remove() on a tool inside a preset (exclusion)", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools.auto_approve = { "$default" }
      opt_proxy.tools.auto_approve:remove("read")
      local resolved = resolve()
      assert.are.same({ "$default" }, resolved.auto_approve)
      assert.are.same({ read = true }, resolved.auto_approve_exclusions)
    end)

    it("supports :append() to add a preset", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools.auto_approve = { "$readonly" }
      opt_proxy.tools.auto_approve:append("$default")
      local resolved = resolve()
      assert.are.same({ "$readonly", "$default" }, resolved.auto_approve)
    end)

    it("supports :append() to add a plain tool name", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools.auto_approve = { "$readonly" }
      opt_proxy.tools.auto_approve:append("bash")
      local resolved = resolve()
      assert.are.same({ "$readonly", "bash" }, resolved.auto_approve)
    end)

    it("supports chained :remove() and :append()", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools.auto_approve = { "$default" }
      opt_proxy.tools.auto_approve:remove("$default"):append("$readonly"):remove("read")
      local resolved = resolve()
      assert.are.same({ "$readonly" }, resolved.auto_approve)
      assert.are.same({ read = true }, resolved.auto_approve_exclusions)
    end)

    it("supports direct table assignment", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools.auto_approve = { "$readonly", "bash" }
      local resolved = resolve()
      assert.are.same({ "$readonly", "bash" }, resolved.auto_approve)
    end)

    it("function assignment still works", function()
      local opt_proxy, resolve = opt.create()
      local fn = function()
        return true
      end
      opt_proxy.tools.auto_approve = fn
      local resolved = resolve()
      assert.equals(fn, resolved.auto_approve)
    end)

    it("not touching auto_approve results in nil", function()
      local _, resolve = opt.create()
      local resolved = resolve()
      assert.is_nil(resolved.auto_approve)
      assert.is_nil(resolved.auto_approve_exclusions)
    end)

    it("exclusions are nil when none set", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools.auto_approve = { "$default" }
      local resolved = resolve()
      assert.is_nil(resolved.auto_approve_exclusions)
    end)

    it("function assignment clears prior ListOption", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools.auto_approve = { "$default" }
      opt_proxy.tools.auto_approve = function()
        return true
      end
      local resolved = resolve()
      assert.equals("function", type(resolved.auto_approve))
      assert.is_nil(resolved.auto_approve_exclusions)
    end)

    it("table assignment clears prior function", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools.auto_approve = function()
        return true
      end
      opt_proxy.tools.auto_approve = { "$readonly" }
      local resolved = resolve()
      assert.are.same({ "$readonly" }, resolved.auto_approve)
    end)

    it("operator - (remove) works on auto_approve", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools.auto_approve = { "$default", "$readonly" }
      opt_proxy.tools.auto_approve = opt_proxy.tools.auto_approve - "$readonly"
      local resolved = resolve()
      assert.are.same({ "$default" }, resolved.auto_approve)
    end)

    it("operator + (append) works on auto_approve", function()
      local opt_proxy, resolve = opt.create()
      opt_proxy.tools.auto_approve = { "$readonly" }
      opt_proxy.tools.auto_approve = opt_proxy.tools.auto_approve + "bash"
      local resolved = resolve()
      assert.are.same({ "$readonly", "bash" }, resolved.auto_approve)
    end)
  end)
end)
