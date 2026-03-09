local status

describe("flemma.status", function()
  before_each(function()
    package.loaded["flemma.status"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.tools.approval"] = nil
    package.loaded["flemma.autopilot"] = nil
    package.loaded["flemma.tools.registry"] = nil
    package.loaded["flemma.sandbox"] = nil
    package.loaded["flemma.sandbox.backends.bwrap"] = nil
    package.loaded["flemma.core.config.manager"] = nil
    package.loaded["flemma.tools.presets"] = nil
    status = require("flemma.status")
  end)

  describe("collect", function()
    it("returns a table with all expected sections", function()
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
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

    it("reports provider as not initialized when no provider instance exists", function()
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
        provider = "anthropic",
        model = "claude-sonnet-4-5-20250929",
        parameters = {},
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })
      state.set_provider(nil)

      local data = status.collect(0)
      assert.is_false(data.provider.initialized)
    end)

    it("separates tools into enabled and disabled lists", function()
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
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
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
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
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
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
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
        provider = "anthropic",
        parameters = {},
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect(0)
      assert.is_false(data.tools.booting)
    end)

    it("reports autopilot state", function()
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
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
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
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
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
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
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
        provider = "anthropic",
        parameters = { max_tokens = 4000, temperature = 0.5 },
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      local data = status.collect(0)
      assert.is_table(data.parameters.merged)
      -- The merged parameters should at least contain the general params
      assert.equals(4000, data.parameters.merged.max_tokens)
      assert.equals(0.5, data.parameters.merged.temperature)
    end)
  end)

  describe("collect — model_info", function()
    it("includes model_info for known models", function()
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
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
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
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

  describe("format", function()
    it("returns lines with section headers", function()
      ---@type flemma.status.Data
      local data = {
        provider = { name = "anthropic", model = "claude-sonnet-4-5-20250929", initialized = true },
        parameters = { merged = { max_tokens = 8192, temperature = 0.7 } },
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

    it("includes full config dump when verbose is true", function()
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
        provider = "anthropic",
        model = "claude-sonnet-4-5-20250929",
        parameters = { max_tokens = 8192 },
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

      ---@type flemma.status.Data
      local data = {
        provider = { name = "anthropic", model = "claude-sonnet-4-5-20250929", initialized = true },
        parameters = { merged = { max_tokens = 8192 } },
        autopilot = { enabled = false, buffer_state = "idle", max_turns = 100 },
        sandbox = {
          enabled = false,
          config_enabled = false,
          backend = "bwrap",
          backend_mode = "auto",
          backend_available = true,
          policy = { rw_paths = {}, network = true, allow_privileged = false },
        },
        tools = { enabled = { "bash" }, disabled = {} },
        approval = {
          approved = {},
          denied = {},
          pending = { "bash" },
          require_approval_disabled = false,
        },
        buffer = { is_chat = false, bufnr = 0 },
      }

      local lines = status.format(data, true)
      local text = table.concat(lines, "\n")
      assert.truthy(text:find("Config %(full%)"), "expected Config (full) header")
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
        parameters = { merged = { max_tokens = 8192 } },
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
        parameters = { merged = {} },
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
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
        provider = "anthropic",
        model = "claude-sonnet-4-6",
        parameters = {},
        tools = { autopilot = { enabled = false, max_turns = 100 } },
        sandbox = { enabled = false, backend = "auto" },
      })

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
        parameters = { merged = {} },
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

      local lines = status.format(data, true)
      local text = table.concat(lines, "\n")
      assert.truthy(text:find("Model Info"), "expected Model Info header in verbose")
      assert.truthy(text:find("min_cache_tokens"), "expected min_cache_tokens in verbose dump")
      assert.truthy(text:find("thinking_budgets"), "expected thinking_budgets in verbose dump")
    end)

    it("shows frontmatter override annotations", function()
      ---@type flemma.status.Data
      local data = {
        provider = { name = "anthropic", model = "claude-sonnet-4-5-20250929", initialized = true },
        parameters = {
          merged = { max_tokens = 8192, thinking = "low" },
          frontmatter_overrides = { thinking = "low" },
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
        tools = { enabled = {}, disabled = {} },
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
        parameters = { merged = {} },
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
        parameters = { merged = {} },
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

    it("shows require_approval = false override", function()
      ---@type flemma.status.Data
      local data = {
        provider = { name = "anthropic", model = "claude-sonnet-4-5-20250929", initialized = true },
        parameters = { merged = {} },
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

    it("shows denied tools in approval digest", function()
      ---@type flemma.status.Data
      local data = {
        provider = { name = "anthropic", model = "claude-sonnet-4-5-20250929", initialized = true },
        parameters = { merged = {} },
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

    it("expands $default preset and classifies tools", function()
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
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
      assert.equals("$default", data.approval.source)
      assert.are.same({ "edit", "read" }, data.approval.approved)
      assert.are.same({ "bash" }, data.approval.pending)
      assert.are.same({}, data.approval.denied)
    end)

    it("returns nil source when no auto_approve is configured", function()
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
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
      assert.is_nil(data.approval.source)
      assert.are.same({}, data.approval.approved)
      assert.are.same({ "read" }, data.approval.pending)
    end)

    it("builds source from multiple policy entries", function()
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
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
      assert.equals("$default, bash", data.approval.source)
      assert.are.same({ "bash", "read" }, data.approval.approved)
    end)

    it("returns all tools as pending for function policy", function()
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
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
      assert.are.same({}, data.approval.approved)
      assert.are.same({ "read" }, data.approval.pending)
    end)

    it("detects require_approval = false", function()
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
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

    it("reports no frontmatter_items when opts is nil", function()
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
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
  end)

  describe("show", function()
    before_each(function()
      local state = require("flemma.state")
      ---@diagnostic disable-next-line: missing-fields
      state.set_config({
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
      assert.equals("flemma_status", vim.bo[bufnr].filetype)

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
