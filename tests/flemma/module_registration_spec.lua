package.loaded["flemma.tools"] = nil
package.loaded["flemma.tools.registry"] = nil

local tools = require("flemma.tools")
local loader = require("flemma.loader")

-- Register a fixture tool module via package.preload
local function register_fixture_tool_module(module_path, tool_defs)
  package.preload[module_path] = function()
    return { definitions = tool_defs }
  end
end

local function cleanup_fixture(module_path)
  package.preload[module_path] = nil
  package.loaded[module_path] = nil
end

describe("tools.modules config", function()
  before_each(function()
    tools.clear()
    tools.setup()
  end)

  it("lazily loads tool definitions from module paths", function()
    register_fixture_tool_module("test.fixture.tools", {
      { name = "fixture_tool", description = "A test tool", input_schema = { type = "object" } },
    })

    tools.register_module("test.fixture.tools")
    local all = tools.get_all({ include_disabled = true })
    assert.is_not_nil(all["fixture_tool"])
    assert.equals("A test tool", all["fixture_tool"].description)

    cleanup_fixture("test.fixture.tools")
  end)

  it("assert_exists catches missing modules at registration time", function()
    assert.has_error(function()
      tools.register_module("nonexistent.tool.module")
    end)
  end)

  it("loaded tools appear in get_for_prompt", function()
    register_fixture_tool_module("test.fixture.tools2", {
      { name = "prompt_tool", description = "For prompt", input_schema = { type = "object" } },
    })

    tools.register_module("test.fixture.tools2")
    local for_prompt = tools.get_for_prompt(nil)
    assert.is_not_nil(for_prompt["prompt_tool"])

    cleanup_fixture("test.fixture.tools2")
  end)

  it("does not double-load already loaded modules", function()
    local load_count = 0
    package.preload["test.fixture.counted"] = function()
      load_count = load_count + 1
      return {
        definitions = {
          { name = "counted_tool", description = "Counted", input_schema = { type = "object" } },
        },
      }
    end

    tools.register_module("test.fixture.counted")
    tools.get_all() -- triggers load
    tools.register_module("test.fixture.counted") -- should be no-op (already loaded)
    tools.get_all() -- should not re-load
    assert.equals(1, load_count)

    cleanup_fixture("test.fixture.counted")
  end)
end)

describe("provider module resolution", function()
  local provider_registry

  before_each(function()
    package.loaded["flemma.provider.registry"] = nil
    provider_registry = require("flemma.provider.registry")
    provider_registry.clear()
    provider_registry.setup()
  end)

  it("registers a provider from a module path", function()
    package.preload["test.fixture.provider"] = function()
      local base = require("flemma.provider.base")
      local P = setmetatable({}, { __index = base })
      P.metadata = {
        name = "test_provider",
        display_name = "Test Provider",
        capabilities = {
          supports_reasoning = false,
          supports_thinking_budget = false,
          outputs_thinking = false,
          output_has_thoughts = false,
        },
      }
      function P.new(opts)
        return base.new(opts)
      end
      function P.build_request()
        return {}
      end
      function P.get_request_headers()
        return {}
      end
      function P.process_response_line() end
      return P
    end

    provider_registry.register("test.fixture.provider")
    assert.is_true(provider_registry.has("test_provider"))
    assert.equals("Test Provider", provider_registry.get_display_name("test_provider"))

    package.preload["test.fixture.provider"] = nil
    package.loaded["test.fixture.provider"] = nil
  end)

  it("is_module_path detects provider module paths in config", function()
    assert.is_true(loader.is_module_path("3rd.provider.deepseek"))
    assert.is_false(loader.is_module_path("anthropic"))
  end)
end)

describe("approval module resolution", function()
  local approval
  local state = require("flemma.state")

  before_each(function()
    package.loaded["flemma.tools.approval"] = nil
    approval = require("flemma.tools.approval")

    package.preload["test.fixture.approval"] = function()
      return {
        resolve = function(tool_name)
          if tool_name == "bash" then
            return "deny"
          end
          return nil
        end,
        priority = 80,
        description = "Test approval resolver",
      }
    end

    state.set_config({
      tools = {
        auto_approve = "test.fixture.approval",
        require_approval = true,
      },
    })
    approval.clear()
    approval.setup()
  end)

  after_each(function()
    approval.clear()
    package.preload["test.fixture.approval"] = nil
    package.loaded["test.fixture.approval"] = nil
  end)

  it("loads resolver from module path on first resolve", function()
    local result = approval.resolve("bash", {}, { bufnr = 0, tool_id = "test" })
    assert.equals("deny", result)
  end)

  it("passes through for tools the module doesn't handle", function()
    local result = approval.resolve("calculator", {}, { bufnr = 0, tool_id = "test" })
    assert.equals("require_approval", result)
  end)
end)

describe("sandbox module resolution", function()
  local sandbox

  before_each(function()
    package.loaded["flemma.sandbox"] = nil
    sandbox = require("flemma.sandbox")
    sandbox.clear()

    package.preload["test.fixture.sandbox"] = function()
      return {
        name = "test_sandbox",
        available = function()
          return true
        end,
        wrap = function(_, _, inner_cmd)
          local wrapped = { "test-sandbox" }
          for _, v in ipairs(inner_cmd) do
            table.insert(wrapped, v)
          end
          return wrapped
        end,
        priority = 90,
        description = "Test sandbox backend",
      }
    end
  end)

  after_each(function()
    sandbox.clear()
    package.preload["test.fixture.sandbox"] = nil
    package.loaded["test.fixture.sandbox"] = nil
  end)

  it("loads and registers backend from module path", function()
    sandbox.register_module("test.fixture.sandbox")
    local entry = sandbox.get("test_sandbox")
    assert.is_not_nil(entry)
    assert.equals("test_sandbox", entry.name)
    assert.is_true(entry.available({}))
  end)

  it("rejects module with missing contract functions", function()
    package.preload["test.fixture.bad_sandbox"] = function()
      return { something = true }
    end
    assert.has_error(function()
      sandbox.register_module("test.fixture.bad_sandbox")
    end)
    package.preload["test.fixture.bad_sandbox"] = nil
    package.loaded["test.fixture.bad_sandbox"] = nil
  end)
end)
