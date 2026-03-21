local status

describe("flemma.status", function()
  before_each(function()
    package.loaded["flemma.status"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.tools.approval"] = nil
    package.loaded["flemma.tools.executor"] = nil
    package.loaded["flemma.autopilot"] = nil
    package.loaded["flemma.tools.registry"] = nil
    package.loaded["flemma.sandbox"] = nil
    package.loaded["flemma.sandbox.backends.bwrap"] = nil
    package.loaded["flemma.provider.normalize"] = nil
    package.loaded["flemma.tools.presets"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.schema.definition"] = nil
    -- Initialize config facade with schema defaults so sandbox/autopilot
    -- modules get a valid facade reference when re-required by status.lua
    local config_facade = require("flemma.config")
    config_facade.init(require("flemma.config.schema.definition"))
    status = require("flemma.status")
  end)

  ---Apply config through the config facade.
  ---Resets the store and applies opts to SETUP.
  ---@param opts table
  local function apply_test_config(opts)
    local config_facade = require("flemma.config")
    config_facade.init(require("flemma.config.schema.definition"))
    if opts and next(opts) then
      config_facade.apply(config_facade.LAYERS.SETUP, opts)
    end
  end

  describe("collect", function()
    it("returns a table with all expected sections", function()
      apply_test_config({
        provider = "anthropic",
        model = "claude-sonnet-4-5-20250929",
        parameters = { max_tokens = 8192, temperature = 0.7 },
        tools = { autopilot = { enabled = true, max_turns = 50 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect(0)
      assert.is_table(data)
      assert.is_table(data.provider)
      assert.equals("anthropic", data.provider.name)
      assert.equals("claude-sonnet-4-5-20250929", data.provider.model)
      assert.is_table(data.parameters)
      assert.is_table(data.autopilot)
      assert.is_table(data.sandbox)
      assert.is_table(data.tools)
    end)

    it("reports provider as initialized when config has a provider set", function()
      apply_test_config({
        provider = "anthropic",
        model = "claude-sonnet-4-5-20250929",
        parameters = {},
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect(0)
      assert.is_true(data.provider.initialized)
    end)

    it("resolves model preset reference to actual provider and model", function()
      local presets_mod = require("flemma.presets")
      presets_mod.refresh({
        ["$haiku"] = { provider = "anthropic", model = "claude-haiku-4-5-20250514" },
      })
      apply_test_config({
        provider = "anthropic",
        model = "$haiku",
        sandbox = { enabled = false },
      })

      local data = status.collect(0)
      assert.equals("anthropic", data.provider.name)
      assert.equals("claude-haiku-4-5-20250514", data.provider.model)
    end)

    it("separates tools into enabled and disabled lists", function()
      apply_test_config({
        provider = "anthropic",
        parameters = {},
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local registry = require("flemma.tools.registry")
      registry.clear()
      registry.register("alpha_tool", {
        name = "alpha_tool",
        description = "An enabled tool",
        input_schema = { type = "object" },
        enabled = true,
      })
      registry.register("beta_tool", {
        name = "beta_tool",
        description = "A disabled tool",
        input_schema = { type = "object" },
        enabled = false,
      })
      registry.register("gamma_tool", {
        name = "gamma_tool",
        description = "Another enabled tool",
        input_schema = { type = "object" },
      })

      local data = status.collect(0)
      assert.are.same({ "alpha_tool", "gamma_tool" }, data.tools.enabled)
      assert.are.same({ "beta_tool" }, data.tools.disabled)
    end)

    it("includes buffer info", function()
      apply_test_config({
        provider = "anthropic",
        parameters = {},
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect(0)
      assert.is_table(data.buffer)
      assert.equals(0, data.buffer.bufnr)
      assert.is_false(data.buffer.is_chat)
    end)

    it("includes booting state when async tool sources are pending", function()
      apply_test_config({
        provider = "anthropic",
        parameters = {},
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local tools = require("flemma.tools")
      tools.clear()
      local captured_done
      tools.register_async(function(_register, done)
        captured_done = done
      end)

      local data = status.collect(0)
      assert.is_true(data.tools.booting)

      -- Cleanup
      captured_done()
    end)

    it("reports booting as false when all tool sources are ready", function()
      apply_test_config({
        provider = "anthropic",
        parameters = {},
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect(0)
      assert.is_false(data.tools.booting)
    end)

    it("reports autopilot state", function()
      apply_test_config({
        provider = "anthropic",
        parameters = {},
        tools = { autopilot = { enabled = true, max_turns = 75 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect(0)
      assert.is_table(data.autopilot)
      assert.equals(75, data.autopilot.max_turns)
    end)

    it("reports sandbox info from config", function()
      apply_test_config({
        provider = "anthropic",
        parameters = {},
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect(0)
      assert.is_table(data.sandbox)
      assert.is_false(data.sandbox.enabled)
      assert.is_false(data.sandbox.config_enabled)
    end)

    it("detects sandbox runtime override", function()
      apply_test_config({
        provider = "anthropic",
        parameters = {},
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local sandbox = require("flemma.sandbox")
      sandbox.set_enabled(true)

      local data = status.collect(0)
      assert.is_true(data.sandbox.enabled)
      assert.is_true(data.sandbox.runtime_override)

      -- Clean up
      sandbox.reset_enabled()
    end)

    it("returns merged parameters", function()
      apply_test_config({
        provider = "anthropic",
        parameters = { max_tokens = 4000, temperature = 0.5 },
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect(0)
      assert.is_table(data.parameters.merged)
      assert.equals(4000, data.parameters.merged.max_tokens)
      assert.equals(0.5, data.parameters.merged.temperature)
    end)

    it("includes layer sources for provider and model", function()
      apply_test_config({
        provider = "anthropic",
        model = "claude-sonnet-4-5-20250929",
        parameters = {},
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect(0)
      assert.equals("S", data.provider.source)
      assert.equals("S", data.provider.model_source)
    end)

    it("includes layer sources for parameters", function()
      apply_test_config({
        provider = "anthropic",
        parameters = { max_tokens = 4000 },
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect(0)
      assert.is_table(data.parameters.sources)
      assert.equals("S", data.parameters.sources.max_tokens)
    end)

    it("reports parameter source as D for schema defaults", function()
      -- Don't set provider explicitly — let it fall through to schema default
      apply_test_config({
        parameters = {},
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect(0)
      -- provider has a schema default ("anthropic") → source is D
      assert.equals("D", data.provider.source)
    end)

    it("reports tools source from config store when tools are registered", function()
      apply_test_config({
        provider = "anthropic",
        parameters = {},
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      -- Register a tool so the tools list has ops in the store
      local tools_registry = require("flemma.tools.registry")
      tools_registry.clear()
      tools_registry.register("read", {
        name = "read",
        description = "Read tool",
        input_schema = { type = "object" },
      })
      -- Record a default so the tools list has an op in the store
      local config_facade = require("flemma.config")
      config_facade.record_default("append", "tools", "read")

      local data = status.collect(0)
      assert.is_string(data.tools.source)
    end)

    it("includes tools from lazily-loaded modules", function()
      apply_test_config({
        provider = "anthropic",
        parameters = {},
        sandbox = { enabled = false, backend = "auto" },
      })

      -- Register a tool module lazily (adds to pending_modules, not loaded yet).
      -- collect_tools must trigger ensure_modules_loaded() to pick them up.
      local tools_mod = require("flemma.tools")
      tools_mod.register_module("extras.flemma.tools.calculator")

      local data = status.collect(0)

      local found_calculator = false
      local found_calculator_async = false
      for _, name in ipairs(data.tools.enabled) do
        if name == "calculator" then
          found_calculator = true
        end
      end
      for _, name in ipairs(data.tools.disabled) do
        if name == "calculator_async" then
          found_calculator_async = true
        end
      end
      assert.is_true(found_calculator, "calculator should appear after lazy module loading")
      assert.is_true(found_calculator_async, "calculator_async (enabled=false) should appear in disabled")
    end)

    it("reports nil tools source when no tools list ops exist", function()
      apply_test_config({
        provider = "anthropic",
        parameters = {},
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect(0)
      -- No tools registered → no list ops on "tools" path → source is nil
      assert.is_nil(data.tools.source)
    end)
  end)

  describe("collect — model_info", function()
    it("includes model_info for known models", function()
      apply_test_config({
        provider = "anthropic",
        model = "claude-sonnet-4-6",
        parameters = {},
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect(0)
      assert.is_table(data.provider.model_info)
      assert.is_table(data.provider.model_info.pricing)
      assert.are.equal(3.0, data.provider.model_info.pricing.input)
      assert.are.equal(200000, data.provider.model_info.max_input_tokens)
    end)

    it("returns nil model_info for unknown models", function()
      apply_test_config({
        provider = "anthropic",
        model = "claude-unknown-99",
        parameters = {},
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect(0)
      assert.is_nil(data.provider.model_info)
    end)
  end)

  describe("collect_verbose", function()
    it("includes introspection data", function()
      apply_test_config({
        provider = "anthropic",
        model = "claude-sonnet-4-5-20250929",
        parameters = { max_tokens = 8192 },
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect_verbose(0)
      assert.is_table(data.introspection)
      assert.is_table(data.introspection.layer_ops)
      assert.is_table(data.introspection.resolved)
    end)

    it("layer_ops contains all four layers", function()
      apply_test_config({
        provider = "anthropic",
        parameters = {},
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect_verbose(0)
      local labels = {}
      for _, layer in ipairs(data.introspection.layer_ops) do
        labels[layer.label] = true
      end
      assert.is_true(labels["D"])
      assert.is_true(labels["S"])
      assert.is_true(labels["R"])
      assert.is_true(labels["F"])
    end)

    it("setup layer ops reflect applied config", function()
      apply_test_config({
        provider = "anthropic",
        parameters = { max_tokens = 8192 },
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect_verbose(0)
      local setup_layer
      for _, layer in ipairs(data.introspection.layer_ops) do
        if layer.label == "S" then
          setup_layer = layer
          break
        end
      end
      assert.is_not_nil(setup_layer)
      assert.is_true(#setup_layer.ops > 0)

      -- Find the max_tokens op
      local found = false
      for _, op_entry in ipairs(setup_layer.ops) do
        if op_entry.path == "parameters.max_tokens" and op_entry.value == 8192 then
          found = true
          break
        end
      end
      assert.is_true(found, "expected max_tokens set op in setup layer")
    end)

    it("resolved tree contains entries with source annotations", function()
      apply_test_config({
        provider = "anthropic",
        parameters = { max_tokens = 8192 },
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect_verbose(0)
      assert.is_true(#data.introspection.resolved > 0)

      -- Find the provider entry
      local found = false
      for _, entry in ipairs(data.introspection.resolved) do
        if entry.path == "provider" then
          assert.equals("anthropic", entry.value)
          assert.equals("S", entry.source)
          found = true
          break
        end
      end
      assert.is_true(found, "expected provider in resolved tree")
    end)
  end)

  describe("format", function()
    it("returns lines with section headers", function()
      ---@type flemma.status.Data
      local data = {
        provider = { name = "anthropic", model = "claude-sonnet-4-5-20250929", initialized = true },
        parameters = { merged = { max_tokens = 8192, temperature = 0.7 }, sources = {} },
        autopilot = { enabled = false, buffer_state = "idle", max_turns = 100 },
        sandbox = {
          enabled = false,
          config_enabled = false,
          backend = "bwrap",
          backend_mode = "auto",
          backend_available = true,
          policy = { rw_paths = {}, network = true, allow_privileged = false },
        },
        tools = { enabled = { "bash", "read_file" }, disabled = {} },
        approval = {
          approved = { "read_file" },
          denied = {},
          pending = { "bash" },
          require_approval_disabled = false,
        },
        buffer = { is_chat = false, bufnr = 0 },
      }

      local lines = status.format(data, false)
      assert.is_table(lines)

      local text = table.concat(lines, "\n")
      assert.truthy(text:find("Provider"), "expected Provider header")
      assert.truthy(text:find("Parameters"), "expected Parameters header")
      assert.truthy(text:find("Autopilot"), "expected Autopilot header")
      assert.truthy(text:find("Sandbox"), "expected Sandbox header")
      assert.truthy(text:find("Tools"), "expected Tools header")
      assert.truthy(text:find("Approval"), "expected Approval header")
    end)

    it("shows layer source indicators on parameter values", function()
      ---@type flemma.status.Data
      local data = {
        provider = { name = "anthropic", model = "claude-sonnet-4-5-20250929", initialized = true, source = "S" },
        parameters = {
          merged = { max_tokens = 8192, thinking = "high" },
          sources = { max_tokens = "D", thinking = "F" },
        },
        autopilot = { enabled = false, buffer_state = "idle", max_turns = 100 },
        sandbox = {
          enabled = false,
          config_enabled = false,
          backend = "bwrap",
          backend_mode = "auto",
          backend_available = true,
          policy = { rw_paths = {}, network = true, allow_privileged = false },
        },
        tools = { enabled = {}, disabled = {} },
        approval = { approved = {}, denied = {}, pending = {}, require_approval_disabled = false },
        buffer = { is_chat = false, bufnr = 0 },
      }

      local lines = status.format(data, false)
      local text = table.concat(lines, "\n")
      -- Parameters should show layer indicators
      assert.truthy(text:find("max_tokens.*D"), "expected D source on max_tokens")
      assert.truthy(text:find("thinking.*F"), "expected F source on thinking")
    end)

    it("shows layer source indicator on provider", function()
      ---@type flemma.status.Data
      local data = {
        provider = { name = "anthropic", model = "claude-haiku", initialized = true, source = "R", model_source = "R" },
        parameters = { merged = {}, sources = {} },
        autopilot = { enabled = false, buffer_state = "idle", max_turns = 100 },
        sandbox = {
          enabled = false,
          config_enabled = false,
          backend = "bwrap",
          backend_mode = "auto",
          backend_available = true,
          policy = { rw_paths = {}, network = true, allow_privileged = false },
        },
        tools = { enabled = {}, disabled = {} },
        approval = { approved = {}, denied = {}, pending = {}, require_approval_disabled = false },
        buffer = { is_chat = false, bufnr = 0 },
      }

      local lines = status.format(data, false)
      local text = table.concat(lines, "\n")
      assert.truthy(text:find("name:.*anthropic.*R"), "expected R source on provider name")
      assert.truthy(text:find("model:.*claude%-haiku.*R"), "expected R source on model")
    end)

    it("includes verbose layer ops and resolved tree", function()
      apply_test_config({
        provider = "anthropic",
        model = "claude-sonnet-4-5-20250929",
        parameters = { max_tokens = 8192 },
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect_verbose(0)
      local lines = status.format(data, true)
      local text = table.concat(lines, "\n")
      assert.truthy(text:find("Layer Ops"), "expected Layer Ops header")
      assert.truthy(text:find("%[D%].*defaults"), "expected defaults layer")
      assert.truthy(text:find("%[S%].*setup"), "expected setup layer")
      assert.truthy(text:find("Resolved Config Tree"), "expected Resolved Config Tree header")
    end)

    it("shows compact model metadata when model_info is present", function()
      ---@type flemma.status.Data
      local data = {
        provider = {
          name = "anthropic",
          model = "claude-sonnet-4-6",
          initialized = true,
          model_info = {
            pricing = { input = 3.0, output = 15.0, cache_read = 0.30, cache_write = 3.75 },
            max_input_tokens = 200000,
            max_output_tokens = 64000,
            thinking_budgets = { minimal = 1024, low = 2048, medium = 8192, high = 16384 },
            min_thinking_budget = 1024,
            max_thinking_budget = 16384,
            min_cache_tokens = 2048,
          },
        },
        parameters = { merged = { max_tokens = 8192 }, sources = {} },
        autopilot = { enabled = false, buffer_state = "idle", max_turns = 100 },
        sandbox = {
          enabled = false,
          config_enabled = false,
          backend = "bwrap",
          backend_mode = "auto",
          backend_available = true,
          policy = { rw_paths = {}, network = true, allow_privileged = false },
        },
        tools = { enabled = {}, disabled = {} },
        approval = { approved = {}, denied = {}, pending = {}, require_approval_disabled = false },
        buffer = { is_chat = false, bufnr = 0 },
      }

      local lines = status.format(data, false)
      local text = table.concat(lines, "\n")
      assert.truthy(text:find("context:"), "expected context line")
      assert.truthy(text:find("200K"), "expected 200K input tokens")
      assert.truthy(text:find("64K"), "expected 64K output tokens")
      assert.truthy(text:find("pricing:"), "expected pricing line")
      assert.truthy(text:find("%$3.00"), "expected input price")
      assert.truthy(text:find("%$15.00"), "expected output price")
      assert.truthy(text:find("thinking:"), "expected thinking line")
      assert.truthy(text:find("1024"), "expected min thinking budget")
    end)

    it("omits model metadata lines when model_info is nil", function()
      ---@type flemma.status.Data
      local data = {
        provider = { name = "anthropic", model = "claude-unknown-99", initialized = true },
        parameters = { merged = {}, sources = {} },
        autopilot = { enabled = false, buffer_state = "idle", max_turns = 100 },
        sandbox = {
          enabled = false,
          config_enabled = false,
          backend = "bwrap",
          backend_mode = "auto",
          backend_available = true,
          policy = { rw_paths = {}, network = true, allow_privileged = false },
        },
        tools = { enabled = {}, disabled = {} },
        approval = { approved = {}, denied = {}, pending = {}, require_approval_disabled = false },
        buffer = { is_chat = false, bufnr = 0 },
      }

      local lines = status.format(data, false)
      local text = table.concat(lines, "\n")
      assert.falsy(text:find("context:"), "expected no context line")
      assert.falsy(text:find("pricing:"), "expected no pricing line")
      assert.falsy(text:find("thinking:"), "expected no thinking line")
    end)

    it("shows full model_info dump in verbose mode", function()
      apply_test_config({
        provider = "anthropic",
        model = "claude-sonnet-4-6",
        parameters = {},
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect_verbose(0)
      -- Inject model_info for the test
      data.provider.model_info = {
        pricing = { input = 3.0, output = 15.0, cache_read = 0.30, cache_write = 3.75 },
        max_input_tokens = 200000,
        max_output_tokens = 64000,
        thinking_budgets = { minimal = 1024, low = 2048, medium = 8192, high = 16384 },
        min_thinking_budget = 1024,
        max_thinking_budget = 16384,
        min_cache_tokens = 2048,
      }

      local lines = status.format(data, true)
      local text = table.concat(lines, "\n")
      assert.truthy(text:find("Model Info"), "expected Model Info header in verbose")
      assert.truthy(text:find("min_cache_tokens"), "expected min_cache_tokens in verbose dump")
      assert.truthy(text:find("thinking_budgets"), "expected thinking_budgets in verbose dump")
    end)

    it("shows frontmatter override annotations for tools", function()
      ---@type flemma.status.Data
      local data = {
        provider = { name = "anthropic", model = "claude-sonnet-4-5-20250929", initialized = true },
        parameters = {
          merged = { max_tokens = 8192, thinking = "low" },
          sources = {},
        },
        autopilot = {
          enabled = false,
          config_enabled = true,
          buffer_state = "idle",
          max_turns = 100,
        },
        sandbox = {
          enabled = false,
          config_enabled = false,
          backend = "bwrap",
          backend_mode = "auto",
          backend_available = true,
          policy = { rw_paths = {}, network = true, allow_privileged = false },
        },
        tools = { enabled = { "bash" }, disabled = {}, frontmatter_items = { bash = true } },
        approval = {
          approved = {},
          denied = {},
          pending = {},
          require_approval_disabled = false,
        },
        buffer = { is_chat = true, bufnr = 1 },
      }

      local lines = status.format(data, false)
      local text = table.concat(lines, "\n")
      assert.truthy(text:find("✲"), "expected frontmatter marker")
    end)

    it("shows tools summary", function()
      ---@type flemma.status.Data
      local data = {
        provider = { name = "anthropic", model = "claude-sonnet-4-5-20250929", initialized = true },
        parameters = { merged = {}, sources = {} },
        autopilot = { enabled = false, buffer_state = "idle", max_turns = 100 },
        sandbox = {
          enabled = false,
          config_enabled = false,
          backend = "bwrap",
          backend_mode = "auto",
          backend_available = true,
          policy = { rw_paths = {}, network = true, allow_privileged = false },
        },
        tools = { enabled = { "bash", "read_file" }, disabled = { "execute_command" } },
        approval = {
          approved = { "read_file" },
          denied = {},
          pending = { "bash" },
          require_approval_disabled = false,
        },
        buffer = { is_chat = false, bufnr = 0 },
      }

      local lines = status.format(data, false)
      local text = table.concat(lines, "\n")
      assert.truthy(text:find("✓"), "expected enabled tool marker")
      assert.truthy(text:find("✗"), "expected disabled tool marker")
      assert.truthy(text:find("bash"), "expected bash tool name")
      assert.truthy(text:find("read_file"), "expected read_file tool name")
      assert.truthy(text:find("execute_command"), "expected execute_command tool name")
    end)

    it("shows approval digest with auto-approved and pending tools", function()
      ---@type flemma.status.Data
      local data = {
        provider = { name = "anthropic", model = "claude-sonnet-4-5-20250929", initialized = true },
        parameters = { merged = {}, sources = {} },
        autopilot = { enabled = false, buffer_state = "idle", max_turns = 100 },
        sandbox = {
          enabled = false,
          config_enabled = false,
          backend = "bwrap",
          backend_mode = "auto",
          backend_available = true,
          policy = { rw_paths = {}, network = true, allow_privileged = false },
        },
        tools = { enabled = { "bash", "edit", "read", "write" }, disabled = {} },
        approval = {
          source = "$default",
          approved = { "edit", "read", "write" },
          denied = {},
          pending = { "bash" },
          require_approval_disabled = false,
        },
        buffer = { is_chat = false, bufnr = 0 },
      }

      local lines = status.format(data, false)
      local text = table.concat(lines, "\n")
      assert.truthy(text:find("Approval %($default%)"), "expected Approval header with source")
      assert.truthy(text:find("auto%-approve: edit, read, write"), "expected auto-approved tools")
      assert.truthy(text:find("require approval: bash"), "expected pending tools")
    end)

    it("shows sandbox marker on sandbox-promoted tools", function()
      ---@type flemma.status.Data
      local data = {
        provider = { name = "anthropic", model = "claude-sonnet-4-5-20250929", initialized = true },
        parameters = { merged = {}, sources = {} },
        autopilot = { enabled = false, buffer_state = "idle", max_turns = 100 },
        sandbox = {
          enabled = true,
          config_enabled = true,
          backend = "bwrap",
          backend_mode = "auto",
          backend_available = true,
          policy = { rw_paths = {}, network = true, allow_privileged = false },
        },
        tools = { enabled = { "bash", "edit", "read", "write" }, disabled = {} },
        approval = {
          source = "$default",
          approved = { "bash", "edit", "read", "write" },
          denied = {},
          pending = {},
          require_approval_disabled = false,
          sandbox_items = { bash = true },
        },
        buffer = { is_chat = false, bufnr = 0 },
      }

      local lines = status.format(data, false)
      local text = table.concat(lines, "\n")
      assert.truthy(text:find("bash ⊡"), "expected sandbox marker on bash")
      assert.truthy(text:find("⊡ auto%-approved via sandbox"), "expected sandbox legend")
    end)

    it("shows require_approval = false override", function()
      ---@type flemma.status.Data
      local data = {
        provider = { name = "anthropic", model = "claude-sonnet-4-5-20250929", initialized = true },
        parameters = { merged = {}, sources = {} },
        autopilot = { enabled = false, buffer_state = "idle", max_turns = 100 },
        sandbox = {
          enabled = false,
          config_enabled = false,
          backend = "bwrap",
          backend_mode = "auto",
          backend_available = true,
          policy = { rw_paths = {}, network = true, allow_privileged = false },
        },
        tools = { enabled = { "bash", "read" }, disabled = {} },
        approval = {
          approved = { "read" },
          denied = {},
          pending = { "bash" },
          require_approval_disabled = true,
        },
        buffer = { is_chat = false, bufnr = 0 },
      }

      local lines = status.format(data, false)
      local text = table.concat(lines, "\n")
      assert.truthy(text:find("all tools auto%-approved"), "expected catch-all message")
    end)

    it("shows booting indicator when tools are still loading", function()
      ---@type flemma.status.Data
      local data = {
        provider = { name = "anthropic", model = "claude-sonnet-4-5-20250929", initialized = true },
        parameters = { merged = {}, sources = {} },
        autopilot = { enabled = false, buffer_state = "idle", max_turns = 100 },
        sandbox = {
          enabled = false,
          config_enabled = false,
          backend = "bwrap",
          backend_mode = "auto",
          backend_available = true,
          policy = { rw_paths = {}, network = true, allow_privileged = false },
        },
        tools = { enabled = { "bash", "read" }, disabled = {}, booting = true },
        approval = {
          approved = { "read" },
          denied = {},
          pending = { "bash" },
          require_approval_disabled = false,
        },
        buffer = { is_chat = false, bufnr = 0 },
      }

      local lines = status.format(data, false)
      local text = table.concat(lines, "\n")
      assert.truthy(text:find("⏳"), "expected booting indicator")
      assert.truthy(text:find("loading async tool sources"), "expected booting message")
    end)

    it("omits booting indicator when tools are ready", function()
      ---@type flemma.status.Data
      local data = {
        provider = { name = "anthropic", model = "claude-sonnet-4-5-20250929", initialized = true },
        parameters = { merged = {}, sources = {} },
        autopilot = { enabled = false, buffer_state = "idle", max_turns = 100 },
        sandbox = {
          enabled = false,
          config_enabled = false,
          backend = "bwrap",
          backend_mode = "auto",
          backend_available = true,
          policy = { rw_paths = {}, network = true, allow_privileged = false },
        },
        tools = { enabled = { "bash", "read" }, disabled = {}, booting = false },
        approval = {
          approved = { "read" },
          denied = {},
          pending = { "bash" },
          require_approval_disabled = false,
        },
        buffer = { is_chat = false, bufnr = 0 },
      }

      local lines = status.format(data, false)
      local text = table.concat(lines, "\n")
      assert.falsy(text:find("⏳"), "expected no booting indicator")
    end)

    it("shows denied tools in approval digest", function()
      ---@type flemma.status.Data
      local data = {
        provider = { name = "anthropic", model = "claude-sonnet-4-5-20250929", initialized = true },
        parameters = { merged = {}, sources = {} },
        autopilot = { enabled = false, buffer_state = "idle", max_turns = 100 },
        sandbox = {
          enabled = false,
          config_enabled = false,
          backend = "bwrap",
          backend_mode = "auto",
          backend_available = true,
          policy = { rw_paths = {}, network = true, allow_privileged = false },
        },
        tools = { enabled = { "bash", "read" }, disabled = {} },
        approval = {
          source = "$yolo, $no-bash",
          approved = { "read" },
          denied = { "bash" },
          pending = {},
          require_approval_disabled = false,
        },
        buffer = { is_chat = false, bufnr = 0 },
      }

      local lines = status.format(data, false)
      local text = table.concat(lines, "\n")
      assert.truthy(text:find("Approval %($yolo, $no%-bash%)"), "expected Approval header with source")
      assert.truthy(text:find("deny: bash"), "expected denied tools")
    end)
  end)

  describe("collect — approval logic", function()
    before_each(function()
      require("flemma.tools.presets").setup()
    end)

    ---Set config through the facade and initialize the approval resolver chain.
    ---@param config table
    local function setup_config(config)
      local config_facade = require("flemma.config")
      config_facade.init(require("flemma.config.schema.definition"))
      if config and next(config) then
        config_facade.apply(config_facade.LAYERS.SETUP, config)
      end
      config_facade.finalize(config_facade.LAYERS.SETUP)
      require("flemma.tools.approval").clear()
      require("flemma.tools.approval").setup()
    end

    it("expands $default preset and classifies tools", function()
      setup_config({
        provider = "anthropic",
        parameters = {},
        tools = {
          auto_approve = { "$default" },
          autopilot = { enabled = false, max_turns = 100 },
        },
        sandbox = { enabled = false, backend = "auto" },
      })

      local registry = require("flemma.tools.registry")
      registry.clear()
      registry.register("read", {
        name = "read",
        description = "Read tool",
        input_schema = { type = "object" },
      })
      registry.register("bash", {
        name = "bash",
        description = "Bash tool",
        input_schema = { type = "object" },
      })
      registry.register("edit", {
        name = "edit",
        description = "Edit tool",
        input_schema = { type = "object" },
      })

      local data = status.collect(0)
      -- After finalize, $default is expanded to tool names
      assert.equals("read, write, edit", data.approval.source)
      assert.are.same({ "edit", "read" }, data.approval.approved)
      assert.are.same({ "bash" }, data.approval.pending)
      assert.are.same({}, data.approval.denied)
    end)

    it("uses schema default auto_approve when none explicitly configured", function()
      setup_config({
        provider = "anthropic",
        parameters = {},
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local registry = require("flemma.tools.registry")
      registry.clear()
      registry.register("read", {
        name = "read",
        description = "Read tool",
        input_schema = { type = "object" },
      })

      local data = status.collect(0)
      -- auto_approve always has a schema default ({ "$default" } → expanded)
      assert.equals("read, write, edit", data.approval.source)
      assert.are.same({ "read" }, data.approval.approved)
      assert.are.same({}, data.approval.pending)
    end)

    it("builds source from multiple policy entries", function()
      setup_config({
        provider = "anthropic",
        parameters = {},
        tools = {
          auto_approve = { "$default", "bash" },
          autopilot = { enabled = false, max_turns = 100 },
        },
        sandbox = { enabled = false, backend = "auto" },
      })

      local registry = require("flemma.tools.registry")
      registry.clear()
      registry.register("bash", {
        name = "bash",
        description = "Bash tool",
        input_schema = { type = "object" },
      })
      registry.register("read", {
        name = "read",
        description = "Read tool",
        input_schema = { type = "object" },
      })

      local data = status.collect(0)
      -- After finalize, $default expands to tool names; bash is appended
      assert.equals("read, write, edit, bash", data.approval.source)
      assert.are.same({ "bash", "read" }, data.approval.approved)
    end)

    it("returns all tools as pending for function policy", function()
      setup_config({
        provider = "anthropic",
        parameters = {},
        tools = {
          auto_approve = function()
            return true
          end,
          autopilot = { enabled = false, max_turns = 100 },
        },
        sandbox = { enabled = false, backend = "auto" },
      })

      local registry = require("flemma.tools.registry")
      registry.clear()
      registry.register("read", {
        name = "read",
        description = "Read tool",
        input_schema = { type = "object" },
      })

      local data = status.collect(0)
      assert.equals("(function)", data.approval.source)
      -- Function policies resolve at runtime — tools show as approved when the
      -- resolver chain evaluates them (the function returns true for all tools)
      assert.are.same({ "read" }, data.approval.approved)
      assert.are.same({}, data.approval.pending)
    end)

    it("detects require_approval = false", function()
      setup_config({
        provider = "anthropic",
        parameters = {},
        tools = {
          require_approval = false,
          autopilot = { enabled = false, max_turns = 100 },
        },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect(0)
      assert.is_true(data.approval.require_approval_disabled)
    end)

    it("reports no frontmatter_items when frontmatter layer is empty", function()
      setup_config({
        provider = "anthropic",
        parameters = {},
        tools = {
          auto_approve = { "$default" },
          autopilot = { enabled = false, max_turns = 100 },
        },
        sandbox = { enabled = false, backend = "auto" },
      })

      local registry = require("flemma.tools.registry")
      registry.clear()
      registry.register("read", {
        name = "read",
        description = "Read tool",
        input_schema = { type = "object" },
      })

      local data = status.collect(0)
      assert.is_nil(data.approval.frontmatter_items)
      assert.is_nil(data.tools.frontmatter_items)
    end)

    it("promotes sandbox-capable tools to approved when sandbox is active", function()
      setup_config({
        provider = "anthropic",
        parameters = {},
        tools = {
          auto_approve = { "$default" },
          autopilot = { enabled = false, max_turns = 100 },
        },
        sandbox = { enabled = true, backend = "auto" },
      })

      -- Stub sandbox backend availability
      local sandbox_mod = require("flemma.sandbox")
      local original_validate = sandbox_mod.validate_backend
      sandbox_mod.validate_backend = function()
        return true, nil
      end

      local registry = require("flemma.tools.registry")
      registry.clear()
      registry.register("read", {
        name = "read",
        description = "Read tool",
        input_schema = { type = "object" },
      })
      registry.register("bash", {
        name = "bash",
        description = "Bash tool",
        capabilities = { "can_auto_approve_if_sandboxed" },
        input_schema = { type = "object" },
      })

      local data = status.collect(0)
      assert.are.same({ "bash", "read" }, data.approval.approved)
      assert.are.same({}, data.approval.pending)
      assert.is_not_nil(data.approval.sandbox_items)
      assert.is_true(data.approval.sandbox_items.bash)

      sandbox_mod.validate_backend = original_validate
    end)

    it("does not promote sandbox-capable tools when sandbox is disabled", function()
      setup_config({
        provider = "anthropic",
        parameters = {},
        tools = {
          auto_approve = { "$default" },
          autopilot = { enabled = false, max_turns = 100 },
        },
        sandbox = { enabled = false, backend = "auto" },
      })

      local registry = require("flemma.tools.registry")
      registry.clear()
      registry.register("bash", {
        name = "bash",
        description = "Bash tool",
        capabilities = { "can_auto_approve_if_sandboxed" },
        input_schema = { type = "object" },
      })

      local data = status.collect(0)
      assert.are.same({}, data.approval.approved)
      assert.are.same({ "bash" }, data.approval.pending)
      assert.is_nil(data.approval.sandbox_items)
    end)

    it("promotes sandbox-capable tools with default auto_approve when sandbox is active", function()
      -- In the new config system, auto_approve always has a schema default
      -- ({ "$default" }), so sandbox promotion activates with defaults.
      setup_config({
        provider = "anthropic",
        parameters = {},
        tools = {
          autopilot = { enabled = false, max_turns = 100 },
        },
        sandbox = { enabled = true, backend = "auto" },
      })

      -- Stub sandbox backend availability
      local sandbox_mod = require("flemma.sandbox")
      local original_validate = sandbox_mod.validate_backend
      sandbox_mod.validate_backend = function()
        return true, nil
      end

      local registry = require("flemma.tools.registry")
      registry.clear()
      registry.register("bash", {
        name = "bash",
        description = "Bash tool",
        capabilities = { "can_auto_approve_if_sandboxed" },
        input_schema = { type = "object" },
      })

      local data = status.collect(0)
      -- auto_approve defaults to { "$default" } → sandbox resolver activates
      assert.are.same({ "bash" }, data.approval.approved)
      assert.are.same({}, data.approval.pending)
      assert.is_not_nil(data.approval.sandbox_items)
      assert.is_true(data.approval.sandbox_items.bash)

      sandbox_mod.validate_backend = original_validate
    end)
  end)

  describe("show", function()
    before_each(function()
      apply_test_config({
        provider = "anthropic",
        model = "claude-sonnet-4-5-20250929",
        parameters = { max_tokens = 8192 },
        tools = { autopilot = { enabled = true, max_turns = 50 } },
        sandbox = { enabled = false, backend = "auto" },
      })
    end)

    it("opens a vertical split with status content", function()
      local original_win = vim.api.nvim_get_current_win()
      status.show({})
      local new_win = vim.api.nvim_get_current_win()
      assert.is_not.equals(original_win, new_win)

      local bufnr = vim.api.nvim_win_get_buf(new_win)
      assert.equals("nofile", vim.bo[bufnr].buftype)
      assert.equals("wipe", vim.bo[bufnr].bufhidden)
      assert.is_false(vim.bo[bufnr].modifiable)
      assert.is_false(vim.bo[bufnr].swapfile)
      assert.equals("flemma-status", vim.bo[bufnr].filetype)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.is_truthy(table.concat(lines, "\n"):find("Flemma Status"))

      -- Cleanup
      vim.api.nvim_win_close(new_win, true)
    end)

    it("jumps cursor to named section when jump_to is specified", function()
      status.show({ jump_to = "Sandbox" })
      local new_win = vim.api.nvim_get_current_win()
      local bufnr = vim.api.nvim_win_get_buf(new_win)

      local cursor = vim.api.nvim_win_get_cursor(new_win)
      local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
      assert.is_truthy(line:find("Sandbox"))

      vim.api.nvim_win_close(new_win, true)
    end)

    it("reuses existing status buffer if one is open", function()
      status.show({})
      local first_win = vim.api.nvim_get_current_win()
      local first_buf = vim.api.nvim_win_get_buf(first_win)

      -- Go back to original window
      vim.cmd("wincmd p")

      -- Show again
      status.show({})
      local second_win = vim.api.nvim_get_current_win()
      local second_buf = vim.api.nvim_win_get_buf(second_win)

      -- Should reuse the same window/buffer
      assert.equals(first_win, second_win)
      assert.equals(first_buf, second_buf)

      vim.api.nvim_win_close(second_win, true)
    end)
  end)
end)
