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
