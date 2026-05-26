package.loaded["flemma.tools"] = nil
package.loaded["flemma.tools.approval"] = nil
package.loaded["flemma.tools.registry"] = nil

local tools = require("flemma.tools")
local tools_registry = require("flemma.tools.registry")
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

describe("async tool source with module schema", function()
  local s = require("flemma.schema")
  local config_facade = require("flemma.config")
  local schema

  before_each(function()
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.schema"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.tools.registry"] = nil

    config_facade = require("flemma.config")
    schema = require("flemma.config.schema")
    config_facade.init(schema)

    tools = require("flemma.tools")
    tools_registry = require("flemma.tools.registry")
    tools.clear()
    tools.setup()
  end)

  after_each(function()
    package.preload["test.fixture.async_with_schema"] = nil
    package.loaded["test.fixture.async_with_schema"] = nil
  end)

  it("registers module-level config schema for DISCOVER resolution", function()
    package.preload["test.fixture.async_with_schema"] = function()
      return {
        metadata = {
          name = "my_async_source",
          config_schema = s.object({
            enabled = s.boolean(false),
            endpoint = s.optional(s.string()),
          }),
        },
        resolve = function(_register, done)
          done()
        end,
        timeout = 5,
      }
    end

    tools.register("test.fixture.async_with_schema")

    local found = tools.get_config_schema("my_async_source")
    assert.is_not_nil(found, "module schema should be discoverable via get_config_schema")
  end)

  it("module schema is accessible from the registry directly", function()
    package.preload["test.fixture.async_with_schema"] = function()
      return {
        metadata = {
          name = "my_async_source",
          config_schema = s.object({
            enabled = s.boolean(false),
          }),
        },
        resolve = function(_register, done)
          done()
        end,
        timeout = 5,
      }
    end

    tools.register("test.fixture.async_with_schema")

    assert.is_not_nil(tools_registry.get_module_schema("my_async_source"))
    assert.is_nil(tools_registry.get_module_schema("nonexistent"))
  end)

  it("module schema defaults materialize into config store", function()
    package.preload["test.fixture.async_with_schema"] = function()
      return {
        metadata = {
          name = "my_async_source",
          config_schema = s.object({
            enabled = s.boolean(false),
            timeout = s.integer(42),
          }),
        },
        resolve = function(_register, done)
          done()
        end,
        timeout = 5,
      }
    end

    tools.register("test.fixture.async_with_schema")

    local cfg = config_facade.get()
    assert.is_not_nil(cfg.tools.my_async_source)
    assert.equals(false, cfg.tools.my_async_source.enabled)
    assert.equals(42, cfg.tools.my_async_source.timeout)
  end)

  it("clear() removes module schemas", function()
    package.preload["test.fixture.async_with_schema"] = function()
      return {
        metadata = {
          name = "my_async_source",
          config_schema = s.object({
            enabled = s.boolean(false),
          }),
        },
        resolve = function(_register, done)
          done()
        end,
        timeout = 5,
      }
    end

    tools.register("test.fixture.async_with_schema")
    assert.is_not_nil(tools_registry.get_module_schema("my_async_source"))

    tools.clear()
    assert.is_nil(tools_registry.get_module_schema("my_async_source"))
  end)
end)

-- Regression: DISCOVER-backed tool config (e.g., tools.mcporter) is deferred
-- during config.apply(SETUP, ..., {defer_discover=true}). The async resolver
-- must not fire until after finalize() replays the deferred writes, otherwise
-- it sees the schema default (enabled=false) instead of the user's value.
describe("async tool source reads deferred config after finalize", function()
  local s = require("flemma.schema")
  local config_facade = require("flemma.config")
  local schema

  before_each(function()
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.schema"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.tools.registry"] = nil

    config_facade = require("flemma.config")
    schema = require("flemma.config.schema")
    config_facade.init(schema)

    tools = require("flemma.tools")
    tools_registry = require("flemma.tools.registry")
    tools.clear()
  end)

  after_each(function()
    package.preload["test.fixture.gated_async"] = nil
    package.loaded["test.fixture.gated_async"] = nil
  end)

  ---Build a fixture module whose resolver captures the config it sees.
  ---@param capture table Table to write resolve_saw_enabled into
  ---@return table module The preloadable module table
  local function make_gated_fixture(capture)
    return {
      metadata = {
        name = "gated_source",
        config_schema = s.object({
          enabled = s.boolean(false),
          path = s.string("default-path"),
        }),
      },
      resolve = function(register, done)
        local cfg = config_facade.get()
        local source_cfg = cfg.tools and cfg.tools.gated_source or {}
        capture.enabled = source_cfg.enabled
        if not source_cfg.enabled then
          done()
          return
        end
        register("gated_tool", {
          name = "gated_tool",
          description = "Registered because enabled=true",
          input_schema = { type = "object", properties = {} },
        })
        done()
      end,
      timeout = 5,
    }
  end

  -- The core invariant: after the full boot sequence, the resolver must see
  -- the user's DISCOVER-backed config, not the schema default.
  it("resolver sees user-provided enabled=true after deferred replay", function()
    local capture = {}
    package.preload["test.fixture.gated_async"] = function()
      return make_gated_fixture(capture)
    end

    -- 1. Apply user config with defer_discover
    local _, _, deferred = config_facade.apply(
      config_facade.LAYERS.SETUP,
      { tools = { gated_source = { enabled = true, path = "/usr/bin/test" } } },
      { defer_discover = true }
    )

    -- 2. Module registration (registers schema + defers async start)
    tools.setup()
    tools.register("test.fixture.gated_async")

    -- 3. Finalize replays deferred writes (enabled=true lands in L20)
    config_facade.finalize(config_facade.LAYERS.SETUP, deferred)

    -- 4. Start deferred async sources (resolver runs with finalized config)
    tools.start_pending_sources()

    assert.is_true(capture.enabled, "resolver should see enabled=true from deferred config")
    local all = tools.get_all({ include_disabled = true })
    assert.is_not_nil(all.gated_tool, "tool should be registered when enabled=true")
  end)

  it("resolver sees default enabled=false when user does not enable", function()
    local capture = {}
    package.preload["test.fixture.gated_async"] = function()
      return make_gated_fixture(capture)
    end

    local _, _, deferred = config_facade.apply(config_facade.LAYERS.SETUP, {}, { defer_discover = true })

    tools.setup()
    tools.register("test.fixture.gated_async")
    config_facade.finalize(config_facade.LAYERS.SETUP, deferred)
    tools.start_pending_sources()

    assert.is_false(capture.enabled, "resolver should see enabled=false (default)")
  end)

  -- Verify the mechanism: register() defers async sources, not fires them
  -- immediately. Without deferral, the resolver would run before finalize().
  it("register() does not fire async resolver immediately", function()
    local resolve_called = false
    package.preload["test.fixture.gated_async"] = function()
      return {
        metadata = {
          name = "gated_source",
          config_schema = s.object({
            enabled = s.boolean(false),
          }),
        },
        resolve = function(_register, done)
          resolve_called = true
          done()
        end,
        timeout = 5,
      }
    end

    tools.setup()
    tools.register("test.fixture.gated_async")

    -- Resolver should NOT have fired yet — it's deferred
    assert.is_false(resolve_called, "resolver should be deferred, not immediate")

    -- After start_pending_sources, it fires
    tools.start_pending_sources()
    assert.is_true(resolve_called, "resolver should fire after start_pending_sources")
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
      function P.new(params)
        local self = setmetatable({
          parameters = params or {},
          state = {},
        }, { __index = setmetatable(P, { __index = base }) })
        self:_new_response_buffer()
        return self
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

describe("sandbox module resolution", function()
  local sandbox

  before_each(function()
    package.loaded["flemma.sandbox"] = nil
    package.loaded["flemma.tools.approval"] = nil
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

describe("end-to-end integration", function()
  local original_path

  before_each(function()
    original_path = package.path
    -- Add fixtures/modules to package.path so require() can find them
    local fixture_dir = vim.fn.fnamemodify("tests/fixtures/modules", ":p")
    package.path = fixture_dir .. "?.lua;" .. package.path

    tools.clear()
    tools.setup()
  end)

  after_each(function()
    package.path = original_path
    package.loaded["test_tools"] = nil
    package.loaded["bad_contract"] = nil
    tools.clear()
  end)

  it("loads fixture tool module via register_module", function()
    tools.register_module("test_tools")
    local all = tools.get_all()
    assert.is_not_nil(all["fixture_search"])
    assert.equals("Search fixture tool", all["fixture_search"].description)
  end)

  it("handles module with no definitions gracefully", function()
    -- bad_contract has no definitions or resolve, so register() should handle gracefully
    -- The module loads but produces no tools (no crash)
    tools.register("bad_contract")
    -- No tools should be registered from this module
    local tool = tools.get("something_else")
    assert.is_nil(tool)
  end)

  it("name with dot is accepted at define() time", function()
    assert.has_no.errors(function()
      require("flemma.tools.registry").define("dotted.name", {
        name = "dotted.name",
        description = "test",
        input_schema = { type = "object" },
      })
    end)
  end)

  it("missing module fails fast at register_module time", function()
    assert.has_error(function()
      tools.register_module("completely.nonexistent.module")
    end)
  end)
end)
