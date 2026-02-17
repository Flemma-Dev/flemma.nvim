local status

describe("flemma.status", function()
  before_each(function()
    package.loaded["flemma.status"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.autopilot"] = nil
    package.loaded["flemma.tools.registry"] = nil
    package.loaded["flemma.sandbox"] = nil
    package.loaded["flemma.sandbox.backends.bwrap"] = nil
    package.loaded["flemma.core.config.manager"] = nil
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
      registry.define("alpha_tool", {
        name = "alpha_tool",
        description = "An enabled tool",
        input_schema = { type = "object" },
        enabled = true,
      })
      registry.define("beta_tool", {
        name = "beta_tool",
        description = "A disabled tool",
        input_schema = { type = "object" },
        enabled = false,
      })
      registry.define("gamma_tool", {
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
        },
        tools = { enabled = { "bash", "read_file" }, disabled = {} },
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
        },
        tools = { enabled = { "bash" }, disabled = {} },
        buffer = { is_chat = false, bufnr = 0 },
      }

      local lines = status.format(data, true)
      local text = table.concat(lines, "\n")
      assert.truthy(text:find("Config %(full%)"), "expected Config (full) header")
    end)

    it("shows frontmatter override annotations", function()
      ---@type flemma.status.Data
      local data = {
        provider = { name = "anthropic", model = "claude-sonnet-4-5-20250929", initialized = true },
        parameters = {
          merged = { max_tokens = 8192, thinking = "low" },
          frontmatter_overrides = { thinking = "low" },
        },
        autopilot = { enabled = false, buffer_state = "idle", max_turns = 100, frontmatter_override = false },
        sandbox = {
          enabled = false,
          config_enabled = false,
          backend = "bwrap",
          backend_mode = "auto",
          backend_available = true,
        },
        tools = { enabled = {}, disabled = {} },
        buffer = { is_chat = true, bufnr = 1 },
      }

      local lines = status.format(data, false)
      local text = table.concat(lines, "\n")
      assert.truthy(text:find("frontmatter"), "expected frontmatter annotation")
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
        },
        tools = { enabled = { "bash", "read_file" }, disabled = { "execute_command" } },
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
  end)
end)
