--- Tests for the global configuration schema definition.
--- Verifies that the schema materializes correctly and matches the current
--- schema defaults, that provider schemas are accessible, and that
--- structural features (aliases, DISCOVER) are properly configured.

local config_facade = require("flemma.config")

describe("config.schema.definition", function()
  local schema

  before_each(function()
    package.loaded["flemma.config.schema"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    config_facade = require("flemma.config")
    schema = require("flemma.config.schema")
    config_facade.init(schema)
  end)

  -- ---------------------------------------------------------------------------
  -- Materialization: verify defaults match current config.lua
  -- ---------------------------------------------------------------------------

  describe("materialization", function()
    it("materializes provider default", function()
      local cfg = config_facade.get()
      assert.equals("anthropic", cfg.provider)
    end)

    it("materializes model as nil (provider-specific default)", function()
      local cfg = config_facade.get()
      assert.is_nil(cfg.model)
    end)

    it("materializes parameter defaults", function()
      local cfg = config_facade.get()
      assert.equals("50%", cfg.parameters.max_tokens)
      assert.is_nil(cfg.parameters.temperature)
      assert.equals(600, cfg.parameters.timeout)
      assert.equals(10, cfg.parameters.connect_timeout)
      assert.equals("short", cfg.parameters.cache_retention)
      assert.equals("high", cfg.parameters.thinking)
    end)

    it("materializes highlight defaults (string)", function()
      local cfg = config_facade.get()
      assert.equals("Special", cfg.highlights.system)
      assert.equals("Normal", cfg.highlights.user)
      assert.equals("Function", cfg.highlights.tool_name)
    end)

    it("materializes highlight defaults (table)", function()
      local cfg = config_facade.get()
      local tb = cfg.highlights.thinking_block
      assert.is_table(tb)
      assert.equals("Comment+bg:#000000-fg:#333333", tb.dark)
      assert.equals("Comment-bg:#000000+fg:#333333", tb.light)
    end)

    it("materializes ruler defaults", function()
      local cfg = config_facade.get()
      assert.is_true(cfg.ruler.enabled)
      assert.is_table(cfg.ruler.hl)
    end)

    it("materializes turns defaults", function()
      local cfg = config_facade.get()
      assert.is_true(cfg.turns.enabled)
      assert.equals(1, cfg.turns.padding.left)
      assert.equals(0, cfg.turns.padding.right)
      assert.equals("FlemmaTurn", cfg.turns.hl)
    end)

    it("materializes line_highlights defaults", function()
      local cfg = config_facade.get()
      assert.is_true(cfg.line_highlights.enabled)
      assert.is_table(cfg.line_highlights.frontmatter)
    end)

    it("materializes ui.usage defaults", function()
      local cfg = config_facade.get()
      assert.is_true(cfg.ui.usage.enabled)
      assert.equals(10000, cfg.ui.usage.timeout)
    end)

    it("materializes progress defaults", function()
      local cfg = config_facade.get()
      assert.equals("StatusLine", cfg.ui.progress.highlight)
    end)

    it("materializes pricing defaults", function()
      local cfg = config_facade.get()
      assert.is_true(cfg.pricing.enabled)
    end)

    it("materializes statusline defaults", function()
      local cfg = config_facade.get()
      assert.is_string(cfg.statusline.format)
      assert.truthy(cfg.statusline.format:find("#{model}"))
    end)

    it("materializes tools auto_approve default as unexpanded preset", function()
      -- Before finalize/presets setup, $standard is stored as-is
      local cfg = config_facade.get()
      assert.same({ "$standard" }, cfg.tools.auto_approve)
    end)

    it("materializes tools defaults", function()
      local cfg = config_facade.get()
      assert.is_true(cfg.tools.require_approval)
      assert.is_true(cfg.tools.auto_approve_sandboxed)
      assert.is_true(cfg.tools.autopilot.enabled)
      assert.equals(100, cfg.tools.autopilot.max_turns)
      assert.equals(2, cfg.tools.max_concurrent)
      assert.equals(30, cfg.tools.default_timeout)
      assert.is_true(cfg.tools.show_spinner)
      assert.equals("result", cfg.tools.cursor_after_result)
      assert.same({}, cfg.tools.modules)
    end)

    it("materializes templating defaults", function()
      local cfg = config_facade.get()
      assert.same({}, cfg.templating.modules)
    end)

    it("materializes presets as empty map", function()
      local cfg = config_facade.get()
      assert.same({}, cfg.presets)
    end)

    it("materializes text_object default", function()
      local cfg = config_facade.get()
      assert.equals("m", cfg.text_object)
    end)

    it("materializes editing defaults", function()
      local cfg = config_facade.get()
      assert.is_true(cfg.editing.auto_prompt)
      assert.is_true(cfg.editing.disable_textwidth)
      assert.is_false(cfg.editing.auto_write)
      assert.is_true(cfg.editing.manage_updatetime)
      assert.equals(1, cfg.editing.foldlevel)
      assert.is_true(cfg.editing.auto_close.thinking)
      assert.is_true(cfg.editing.auto_close.tool_use)
      assert.is_true(cfg.editing.auto_close.tool_result)
      assert.is_false(cfg.editing.auto_close.frontmatter)
    end)

    it("materializes logging defaults", function()
      local cfg = config_facade.get()
      assert.is_false(cfg.logging.enabled)
      assert.is_string(cfg.logging.path)
      assert.truthy(cfg.logging.path:find("flemma.log"))
      assert.equals("DEBUG", cfg.logging.level)
    end)

    it("materializes keymaps defaults", function()
      local cfg = config_facade.get()
      assert.is_true(cfg.keymaps.enabled)
      assert.equals("<C-]>", cfg.keymaps.normal.send)
      assert.equals("<C-c>", cfg.keymaps.normal.cancel)
      assert.equals("<M-CR>", cfg.keymaps.normal.tool_execute)
      assert.equals("]m", cfg.keymaps.normal.message_next)
      assert.equals("[m", cfg.keymaps.normal.message_prev)
      assert.equals("<Space>", cfg.keymaps.normal.fold_toggle)
      assert.equals("<C-]>", cfg.keymaps.insert.send)
    end)

    it("materializes diagnostics defaults", function()
      local cfg = config_facade.get()
      assert.is_false(cfg.diagnostics.enabled)
    end)

    it("materializes sandbox defaults", function()
      local cfg = config_facade.get()
      assert.is_true(cfg.sandbox.enabled)
      assert.equals("auto", cfg.sandbox.backend)
      assert.is_true(cfg.sandbox.policy.network)
      assert.is_false(cfg.sandbox.policy.allow_privileged)
      assert.is_table(cfg.sandbox.policy.rw_paths)
      assert.equals(6, #cfg.sandbox.policy.rw_paths)
      assert.equals("urn:flemma:cwd", cfg.sandbox.policy.rw_paths[1])
      -- backends object is empty at init — bwrap resolves via DISCOVER after registration
    end)

    it("materializes secrets defaults", function()
      local cfg = config_facade.get()
      assert.equals("gcloud", cfg.secrets.gcloud.path)
    end)

    it("materializes lsp defaults", function()
      local cfg = config_facade.get()
      assert.is_true(cfg.lsp.enabled)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Provider parameter schemas
  -- ---------------------------------------------------------------------------

  describe("provider parameter schemas (via registration)", function()
    local provider_reg

    before_each(function()
      -- Re-require the registry so its config_facade local picks up the current (re-init'd) config_facade
      package.loaded["flemma.provider.registry"] = nil
      provider_reg = require("flemma.provider.registry")
      provider_reg.clear()
    end)

    it("materializes OpenAI reasoning_summary default after registration", function()
      provider_reg.register("flemma.provider.adapters.openai")
      local cfg = config_facade.get()
      assert.equals("auto", cfg.parameters.openai.reasoning_summary)
    end)

    it("materializes Vertex location default after registration", function()
      provider_reg.register("flemma.provider.adapters.vertex")
      local cfg = config_facade.get()
      assert.equals("global", cfg.parameters.vertex.location)
    end)

    it("does not materialize Anthropic defaults (all optional, no defaults)", function()
      provider_reg.register("flemma.provider.adapters.anthropic")
      local cfg = config_facade.get()
      assert.is_nil(cfg.parameters.anthropic.thinking_budget)
    end)

    it("does not materialize Vertex project_id (optional, no default)", function()
      provider_reg.register("flemma.provider.adapters.vertex")
      local cfg = config_facade.get()
      assert.is_nil(cfg.parameters.vertex.project_id)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Schema setup overrides
  -- ---------------------------------------------------------------------------

  describe("setup overrides", function()
    it("accepts scalar override via apply", function()
      config_facade.apply(config_facade.LAYERS.SETUP, { provider = "openai" })
      local cfg = config_facade.get()
      assert.equals("openai", cfg.provider)
    end)

    it("accepts parameter override via apply", function()
      config_facade.apply(config_facade.LAYERS.SETUP, { parameters = { timeout = 1200 } })
      local cfg = config_facade.get()
      assert.equals(1200, cfg.parameters.timeout)
      -- temperature has no default (nil when not explicitly set)
      assert.is_nil(cfg.parameters.temperature)
    end)

    it("accepts integer max_tokens override", function()
      config_facade.apply(config_facade.LAYERS.SETUP, { parameters = { max_tokens = 8192 } })
      local cfg = config_facade.get()
      assert.equals(8192, cfg.parameters.max_tokens)
    end)

    it("accepts string max_tokens override", function()
      config_facade.apply(config_facade.LAYERS.SETUP, { parameters = { max_tokens = "75%" } })
      local cfg = config_facade.get()
      assert.equals("75%", cfg.parameters.max_tokens)
    end)

    it("accepts thinking = false (disable)", function()
      config_facade.apply(config_facade.LAYERS.SETUP, { parameters = { thinking = false } })
      local cfg = config_facade.get()
      assert.is_false(cfg.parameters.thinking)
    end)

    it("rejects thinking = true (use a named level instead)", function()
      local ok, errors = config_facade.apply(config_facade.LAYERS.SETUP, { parameters = { thinking = true } })
      assert.is_true(ok)
      assert.is_truthy(errors)
      assert.truthy(errors[1]:find("no union branch matched"))
    end)

    it("accepts thinking numeric override", function()
      config_facade.apply(config_facade.LAYERS.SETUP, { parameters = { thinking = 4096 } })
      local cfg = config_facade.get()
      assert.equals(4096, cfg.parameters.thinking)
    end)

    it("accepts highlight string override for table-default field", function()
      config_facade.apply(config_facade.LAYERS.SETUP, {
        highlights = { thinking_block = "MyCustomHighlight" },
      })
      local cfg = config_facade.get()
      assert.equals("MyCustomHighlight", cfg.highlights.thinking_block)
    end)

    it("accepts text_object = false", function()
      config_facade.apply(config_facade.LAYERS.SETUP, { text_object = false })
      local cfg = config_facade.get()
      assert.is_false(cfg.text_object)
    end)

    it("rejects text_object = true", function()
      local ok, errors = config_facade.apply(config_facade.LAYERS.SETUP, { text_object = true })
      assert.is_true(ok)
      assert.is_truthy(errors)
      assert.truthy(errors[1]:find("no union branch matched"))
    end)

    it("accepts fold_toggle = false", function()
      config_facade.apply(config_facade.LAYERS.SETUP, {
        keymaps = { normal = { fold_toggle = false } },
      })
      local cfg = config_facade.get()
      assert.is_false(cfg.keymaps.normal.fold_toggle)
    end)

    it("rejects unknown top-level key", function()
      local ok, errors = config_facade.apply(config_facade.LAYERS.SETUP, { nonexistent = true })
      assert.is_true(ok)
      assert.is_truthy(errors)
      assert.truthy(errors[1]:find("unknown key"))
    end)

    it("accepts provider-specific parameter overrides after registration", function()
      package.loaded["flemma.provider.registry"] = nil
      local provider_reg = require("flemma.provider.registry")
      provider_reg.clear()
      provider_reg.register("flemma.provider.adapters.anthropic")
      config_facade.apply(config_facade.LAYERS.SETUP, {
        parameters = { anthropic = { thinking_budget = 2048 } },
      })
      local cfg = config_facade.get()
      assert.equals(2048, cfg.parameters.anthropic.thinking_budget)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Aliases
  -- ---------------------------------------------------------------------------

  describe("aliases", function()
    it("resolves top-level timeout alias", function()
      config_facade.apply(config_facade.LAYERS.SETUP, { timeout = 1200 })
      local cfg = config_facade.get()
      assert.equals(1200, cfg.parameters.timeout)
    end)

    it("resolves top-level thinking alias", function()
      config_facade.apply(config_facade.LAYERS.SETUP, { thinking = "low" })
      local cfg = config_facade.get()
      assert.equals("low", cfg.parameters.thinking)
    end)

    it("resolves top-level max_tokens alias", function()
      config_facade.apply(config_facade.LAYERS.SETUP, { max_tokens = 4096 })
      local cfg = config_facade.get()
      assert.equals(4096, cfg.parameters.max_tokens)
    end)

    it("resolves top-level temperature alias", function()
      config_facade.apply(config_facade.LAYERS.SETUP, { temperature = 0.3 })
      local cfg = config_facade.get()
      assert.equals(0.3, cfg.parameters.temperature)
    end)

    it("resolves tools.approve alias", function()
      config_facade.apply(config_facade.LAYERS.SETUP, {
        tools = { approve = { "bash", "read" } },
      })
      local cfg = config_facade.get()
      assert.same({ "bash", "read" }, cfg.tools.auto_approve)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- DISCOVER structure
  -- ---------------------------------------------------------------------------

  describe("DISCOVER callbacks", function()
    it("parameters object has DISCOVER configured", function()
      local params_schema = schema:get_child_schema("parameters")
      assert.is_not_nil(params_schema)
      assert.is_not_nil(params_schema._discover)
    end)

    it("tools object has DISCOVER configured", function()
      local tools_schema = schema:get_child_schema("tools")
      assert.is_not_nil(tools_schema)
      assert.is_not_nil(tools_schema._discover)
    end)

    it("parameters DISCOVER returns nil for unknown provider", function()
      local params_schema = schema:get_child_schema("parameters")
      local result = params_schema:get_child_schema("nonexistent_provider")
      assert.is_nil(result)
    end)

    it("tools DISCOVER returns nil for unknown tool", function()
      local tools_schema = schema:get_child_schema("tools")
      local result = tools_schema:get_child_schema("nonexistent_tool")
      assert.is_nil(result)
    end)

    it("sandbox backends object has DISCOVER configured", function()
      local sandbox_schema = schema:get_child_schema("sandbox")
      local backends_schema = sandbox_schema:get_child_schema("backends")
      assert.is_not_nil(backends_schema)
      assert.is_not_nil(backends_schema._discover)
    end)

    it("sandbox backends DISCOVER returns nil for unknown backend", function()
      local sandbox_schema = schema:get_child_schema("sandbox")
      local backends_schema = sandbox_schema:get_child_schema("backends")
      local result = backends_schema:get_child_schema("nonexistent_backend")
      assert.is_nil(result)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Schema structural integrity
  -- ---------------------------------------------------------------------------

  describe("structural integrity", function()
    it("schema is an ObjectNode", function()
      assert.is_true(schema:is_object())
    end)

    it("all top-level fields are navigable", function()
      local expected_fields = {
        "defaults",
        "highlights",
        "role_style",
        "ruler",
        "turns",
        "line_highlights",
        "ui",
        "pricing",
        "statusline",
        "provider",
        "model",
        "parameters",
        "tools",
        "templating",
        "presets",
        "text_object",
        "editing",
        "logging",
        "keymaps",
        "diagnostics",
        "sandbox",
        "secrets",
        "lsp",
        "experimental",
      }
      for _, field in ipairs(expected_fields) do
        assert.is_not_nil(schema:get_child_schema(field), "missing field: " .. field)
      end
    end)

    it("parameters resolves built-in provider fields via DISCOVER after registration", function()
      package.loaded["flemma.provider.registry"] = nil
      local provider_reg = require("flemma.provider.registry")
      provider_reg.clear()
      provider_reg.register("flemma.provider.adapters.anthropic")
      provider_reg.register("flemma.provider.adapters.openai")
      provider_reg.register("flemma.provider.adapters.vertex")
      local params = schema:get_child_schema("parameters")
      assert.is_not_nil(params:get_child_schema("anthropic"))
      assert.is_not_nil(params:get_child_schema("openai"))
      assert.is_not_nil(params:get_child_schema("vertex"))
    end)

    it("tools.modules is a list", function()
      local tools = schema:get_child_schema("tools")
      local modules = tools:get_child_schema("modules")
      assert.is_true(modules:is_list())
    end)

    it("tools.auto_approve is a union (list, func, string)", function()
      local tools = schema:get_child_schema("tools")
      local auto_approve = tools:get_child_schema("auto_approve")
      -- Validates list
      assert.is_true(auto_approve:validate_value({ "bash" }))
      -- Validates string
      assert.is_true(auto_approve:validate_value("$all"))
      -- Validates function
      assert.is_true(auto_approve:validate_value(function() end))
      -- Rejects number
      local ok = auto_approve:validate_value(42)
      assert.is_false(ok)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- DISCOVER resolution with registered modules
  -- ---------------------------------------------------------------------------

  describe("DISCOVER resolution with registered modules", function()
    local tools_module
    local provider_reg
    local sandbox_module

    before_each(function()
      -- Re-require registries so their config_facade locals pick up the current (re-init'd) config_facade
      package.loaded["flemma.tools"] = nil
      package.loaded["flemma.tools.registry"] = nil
      tools_module = require("flemma.tools")
      tools_module.clear()
      package.loaded["flemma.provider.registry"] = nil
      provider_reg = require("flemma.provider.registry")
      provider_reg.clear()
      package.loaded["flemma.sandbox"] = nil
      sandbox_module = require("flemma.sandbox")
      sandbox_module.clear()
    end)

    describe("tool DISCOVER", function()
      it("resolves bash tool config schema", function()
        tools_module.register("flemma.tools.definitions.bash")
        config_facade.apply(config_facade.LAYERS.SETUP, {
          tools = { bash = { shell = "zsh" } },
        })
        assert.equals("zsh", config_facade.get().tools.bash.shell)
      end)

      it("resolves bash cwd and env config", function()
        tools_module.register("flemma.tools.definitions.bash")
        config_facade.apply(config_facade.LAYERS.SETUP, {
          tools = { bash = { cwd = "/home", env = { PATH = "/usr/bin" } } },
        })
        local cfg = config_facade.get()
        assert.equals("/home", cfg.tools.bash.cwd)
        assert.same({ PATH = "/usr/bin" }, cfg.tools.bash.env)
      end)

      it("resolves grep tool config with exclude list", function()
        tools_module.register("flemma.tools.definitions.grep")
        config_facade.apply(config_facade.LAYERS.SETUP, {
          tools = { grep = { exclude = { "node_modules", ".git" } } },
        })
        assert.same({ "node_modules", ".git" }, config_facade.get().tools.grep.exclude)
      end)

      it("resolves find tool config schema", function()
        tools_module.register("flemma.tools.definitions.find")
        config_facade.apply(config_facade.LAYERS.SETUP, {
          tools = { find = { cwd = "/home" } },
        })
        assert.equals("/home", config_facade.get().tools.find.cwd)
      end)

      it("resolves ls tool config schema", function()
        tools_module.register("flemma.tools.definitions.ls")
        config_facade.apply(config_facade.LAYERS.SETUP, {
          tools = { ls = { cwd = "/var" } },
        })
        assert.equals("/var", config_facade.get().tools.ls.cwd)
      end)

      it("rejects unknown field on discovered tool schema", function()
        tools_module.register("flemma.tools.definitions.bash")
        local ok, errors = config_facade.apply(config_facade.LAYERS.SETUP, {
          tools = { bash = { nonexistent = "value" } },
        })
        assert.is_true(ok)
        assert.is_truthy(errors)
        assert.truthy(errors[1]:find("unknown key"))
      end)

      it("rejects invalid type on discovered tool schema field", function()
        tools_module.register("flemma.tools.definitions.bash")
        local ok, errors = config_facade.apply(config_facade.LAYERS.SETUP, {
          tools = { bash = { shell = 42 } },
        })
        assert.is_true(ok)
        assert.is_truthy(errors)
      end)

      it("errors for unregistered tool without defer_discover", function()
        local ok, errors = config_facade.apply(config_facade.LAYERS.SETUP, {
          tools = { bash = { shell = "zsh" } },
        })
        assert.is_true(ok)
        assert.is_truthy(errors)
        assert.truthy(errors[1]:find("unknown key"))
      end)
    end)

    describe("provider DISCOVER", function()
      it("resolves custom provider config schema via registry", function()
        local s = require("flemma.schema")
        provider_reg.register("custom", {
          module = "flemma.provider.adapters.anthropic",
          capabilities = {
            supports_reasoning = false,
            supports_thinking_budget = false,
            outputs_thinking = false,
            output_has_thoughts = false,
          },
          display_name = "Custom Provider",
          config_schema = s.object({
            api_url = s.optional(s.string()),
          }),
        })
        config_facade.apply(config_facade.LAYERS.SETUP, {
          parameters = { custom = { api_url = "https://custom.api" } },
        })
        assert.equals("https://custom.api", config_facade.get().parameters.custom.api_url)
      end)

      it("built-in provider schemas require registry registration (no special treatment)", function()
        -- Without registration, DISCOVER returns nil → unknown key error
        local ok, errors = config_facade.apply(config_facade.LAYERS.SETUP, {
          parameters = { anthropic = { thinking_budget = 4096 } },
        })
        assert.is_true(ok)
        assert.is_truthy(errors)
        assert.truthy(errors[1]:find("unknown key"))
      end)

      it("built-in provider schemas work after registration", function()
        provider_reg.register("flemma.provider.adapters.anthropic")
        config_facade.apply(config_facade.LAYERS.SETUP, {
          parameters = { anthropic = { thinking_budget = 4096 } },
        })
        assert.equals(4096, config_facade.get().parameters.anthropic.thinking_budget)
      end)

      it("rejects unknown field on custom provider schema", function()
        local s = require("flemma.schema")
        provider_reg.register("custom", {
          module = "flemma.provider.adapters.anthropic",
          capabilities = {
            supports_reasoning = false,
            supports_thinking_budget = false,
            outputs_thinking = false,
            output_has_thoughts = false,
          },
          display_name = "Custom Provider",
          config_schema = s.object({
            api_url = s.optional(s.string()),
          }),
        })
        local ok, errors = config_facade.apply(config_facade.LAYERS.SETUP, {
          parameters = { custom = { nonexistent = "value" } },
        })
        assert.is_true(ok)
        assert.is_truthy(errors)
        assert.truthy(errors[1]:find("unknown key"))
      end)
    end)

    describe("sandbox backend DISCOVER", function()
      it("resolves bwrap config schema after registration", function()
        sandbox_module.setup()
        config_facade.apply(config_facade.LAYERS.SETUP, {
          sandbox = { backends = { bwrap = { path = "/usr/local/bin/bwrap" } } },
        })
        assert.equals("/usr/local/bin/bwrap", config_facade.get().sandbox.backends.bwrap.path)
      end)

      it("resolves bwrap extra_args config after registration", function()
        sandbox_module.setup()
        config_facade.apply(config_facade.LAYERS.SETUP, {
          sandbox = { backends = { bwrap = { extra_args = { "--tmpfs", "/run" } } } },
        })
        assert.same({ "--tmpfs", "/run" }, config_facade.get().sandbox.backends.bwrap.extra_args)
      end)

      it("rejects unknown field on bwrap schema", function()
        sandbox_module.setup()
        local ok, errors = config_facade.apply(config_facade.LAYERS.SETUP, {
          sandbox = { backends = { bwrap = { nonexistent = "value" } } },
        })
        assert.is_true(ok)
        assert.is_truthy(errors)
        assert.truthy(errors[1]:find("unknown key"))
      end)

      it("errors for unregistered bwrap without defer_discover", function()
        local ok, errors = config_facade.apply(config_facade.LAYERS.SETUP, {
          sandbox = { backends = { bwrap = { path = "/usr/bin/bwrap" } } },
        })
        assert.is_true(ok)
        assert.is_truthy(errors)
        assert.truthy(errors[1]:find("unknown key"))
      end)

      it("resolves custom backend config schema via registry", function()
        local s_mod = require("flemma.schema")
        sandbox_module.register("firejail", {
          available = function()
            return true
          end,
          wrap = function(_, _, cmd)
            return cmd
          end,
          config_schema = s_mod.object({
            profile = s_mod.optional(s_mod.string()),
          }),
        })
        config_facade.apply(config_facade.LAYERS.SETUP, {
          sandbox = { backends = { firejail = { profile = "restricted" } } },
        })
        assert.equals("restricted", config_facade.get().sandbox.backends.firejail.profile)
      end)

      it("rejects unknown field on custom backend schema", function()
        local s_mod = require("flemma.schema")
        sandbox_module.register("firejail", {
          available = function()
            return true
          end,
          wrap = function(_, _, cmd)
            return cmd
          end,
          config_schema = s_mod.object({
            profile = s_mod.optional(s_mod.string()),
          }),
        })
        local ok, errors = config_facade.apply(config_facade.LAYERS.SETUP, {
          sandbox = { backends = { firejail = { nonexistent = "value" } } },
        })
        assert.is_true(ok)
        assert.is_truthy(errors)
        assert.truthy(errors[1]:find("unknown key"))
      end)

      it("errors for unregistered backend without defer_discover", function()
        local ok, errors = config_facade.apply(config_facade.LAYERS.SETUP, {
          sandbox = { backends = { nsjail = { config_path = "/etc/nsjail" } } },
        })
        assert.is_true(ok)
        assert.is_truthy(errors)
        assert.truthy(errors[1]:find("unknown key"))
      end)
    end)

    describe("deferred DISCOVER", function()
      it("defers tool config writes and replays after registration", function()
        local _, err, deferred = config_facade.apply(
          config_facade.LAYERS.SETUP,
          { tools = { bash = { shell = "zsh" } } },
          { defer_discover = true }
        )
        assert.is_nil(err)
        assert.is_not_nil(deferred)
        assert.equals(1, #deferred)

        tools_module.register("flemma.tools.definitions.bash")

        local failures = config_facade.apply_deferred(config_facade.LAYERS.SETUP, deferred)
        assert.is_nil(failures)
        assert.equals("zsh", config_facade.get().tools.bash.shell)
      end)

      it("deferred write fails for genuinely unknown tool", function()
        local _, _, deferred = config_facade.apply(
          config_facade.LAYERS.SETUP,
          { tools = { nonexistent = { foo = "bar" } } },
          { defer_discover = true }
        )
        assert.is_not_nil(deferred)

        local failures = config_facade.apply_deferred(config_facade.LAYERS.SETUP, deferred)
        assert.is_not_nil(failures)
        assert.equals(1, #failures)
      end)

      it("defers multiple tool config writes", function()
        local _, _, deferred = config_facade.apply(
          config_facade.LAYERS.SETUP,
          { tools = { bash = { shell = "zsh" }, grep = { exclude = { ".git" } } } },
          { defer_discover = true }
        )
        assert.is_not_nil(deferred)
        assert.equals(2, #deferred)

        tools_module.register("flemma.tools.definitions.bash")
        tools_module.register("flemma.tools.definitions.grep")

        local failures = config_facade.apply_deferred(config_facade.LAYERS.SETUP, deferred)
        assert.is_nil(failures)
        assert.equals("zsh", config_facade.get().tools.bash.shell)
        assert.same({ ".git" }, config_facade.get().tools.grep.exclude)
      end)

      it("defers custom provider config and replays after registration", function()
        local _, _, deferred = config_facade.apply(
          config_facade.LAYERS.SETUP,
          { parameters = { my_provider = { api_url = "https://api.mine" } } },
          { defer_discover = true }
        )
        assert.is_not_nil(deferred)

        local s = require("flemma.schema")
        provider_reg.register("my_provider", {
          module = "flemma.provider.adapters.anthropic",
          capabilities = {
            supports_reasoning = false,
            supports_thinking_budget = false,
            outputs_thinking = false,
            output_has_thoughts = false,
          },
          display_name = "My Provider",
          config_schema = s.object({
            api_url = s.optional(s.string()),
          }),
        })

        local failures = config_facade.apply_deferred(config_facade.LAYERS.SETUP, deferred)
        assert.is_nil(failures)
        assert.equals("https://api.mine", config_facade.get().parameters.my_provider.api_url)
      end)

      it("defers custom backend config and replays after registration", function()
        local _, _, deferred = config_facade.apply(
          config_facade.LAYERS.SETUP,
          { sandbox = { backends = { firejail = { profile = "restricted" } } } },
          { defer_discover = true }
        )
        assert.is_not_nil(deferred)

        local s_mod = require("flemma.schema")
        sandbox_module.register("firejail", {
          available = function()
            return true
          end,
          wrap = function(_, _, cmd)
            return cmd
          end,
          config_schema = s_mod.object({
            profile = s_mod.optional(s_mod.string()),
          }),
        })

        local failures = config_facade.apply_deferred(config_facade.LAYERS.SETUP, deferred)
        assert.is_nil(failures)
        assert.equals("restricted", config_facade.get().sandbox.backends.firejail.profile)
      end)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- auto_approve coerce — preset expansion
  -- ---------------------------------------------------------------------------

  describe("auto_approve coerce", function()
    local unified_presets

    before_each(function()
      package.loaded["flemma.presets"] = nil
      unified_presets = require("flemma.presets")
    end)

    it("passes through non-$ strings unchanged", function()
      local w = config_facade.writer(nil, config_facade.LAYERS.SETUP)
      w.tools.auto_approve:append("bash")
      local cfg = config_facade.get()
      assert.truthy(vim.tbl_contains(cfg.tools.auto_approve, "bash"))
    end)

    it("passes through functions unchanged", function()
      local fn = function() end
      local w = config_facade.writer(nil, config_facade.LAYERS.SETUP)
      w.tools.auto_approve = fn
      local cfg = config_facade.get()
      assert.equals(fn, cfg.tools.auto_approve)
    end)

    it("expands $standard preset when presets are registered", function()
      unified_presets.setup(nil)
      -- The L10 default has { "$standard" }. Finalize expands it.
      config_facade.finalize(config_facade.LAYERS.SETUP)
      local cfg = config_facade.get()
      local approve = cfg.tools.auto_approve
      assert.is_table(approve)
      assert.truthy(vim.tbl_contains(approve, "read"))
      assert.truthy(vim.tbl_contains(approve, "write"))
      assert.truthy(vim.tbl_contains(approve, "edit"))
      -- $standard itself is gone (expanded into individual tool names)
      assert.is_falsy(vim.tbl_contains(approve, "$standard"))
    end)

    it("leaves $standard unexpanded before presets are registered", function()
      -- No presets.setup() call — presets registry is empty
      unified_presets.clear()
      config_facade.finalize(config_facade.LAYERS.SETUP)
      local cfg = config_facade.get()
      -- $standard stays as-is because the preset isn't found
      assert.truthy(vim.tbl_contains(cfg.tools.auto_approve, "$standard"))
    end)

    it("expands $preset per-item in list set via write proxy", function()
      unified_presets.setup({ ["$safe"] = { auto_approve = { "read" } } })
      local w = config_facade.writer(nil, config_facade.LAYERS.SETUP)
      w.tools.auto_approve = { "$safe", "bash" }
      local cfg = config_facade.get()
      assert.are.same({ "read", "bash" }, cfg.tools.auto_approve)
    end)

    it("expands $preset in append via write proxy", function()
      unified_presets.setup(nil)
      local w = config_facade.writer(nil, config_facade.LAYERS.SETUP)
      w.tools.auto_approve:append("$standard")
      local ops = config_facade.dump_layer(config_facade.LAYERS.SETUP)
      -- Should have expanded into individual append ops
      local appended = {}
      for _, op in ipairs(ops) do
        if op.op == "append" and op.path == "tools.auto_approve" then
          table.insert(appended, op.value)
        end
      end
      assert.truthy(vim.tbl_contains(appended, "read"))
      assert.truthy(vim.tbl_contains(appended, "write"))
      assert.truthy(vim.tbl_contains(appended, "edit"))
    end)

    it("expands $preset in remove via write proxy", function()
      unified_presets.setup(nil)
      -- Start with all $standard tools
      local w = config_facade.writer(nil, config_facade.LAYERS.SETUP)
      w.tools.auto_approve = { "read", "write", "edit", "bash" }
      -- Remove the $standard preset (should expand to individual remove ops)
      w.tools.auto_approve:remove("$standard")
      local cfg = config_facade.get()
      assert.are.same({ "bash" }, cfg.tools.auto_approve)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Autopilot boolean coerce
  -- ---------------------------------------------------------------------------

  describe("autopilot coerce", function()
    it("coerces boolean false to { enabled = false }", function()
      local w = config_facade.writer(nil, config_facade.LAYERS.SETUP)
      w.tools.autopilot = false
      local cfg = config_facade.materialize()
      assert.is_false(cfg.tools.autopilot.enabled)
      assert.equals(100, cfg.tools.autopilot.max_turns)
    end)

    it("coerces boolean true to { enabled = true }", function()
      local w = config_facade.writer(nil, config_facade.LAYERS.SETUP)
      w.tools.autopilot = true
      local cfg = config_facade.materialize()
      assert.is_true(cfg.tools.autopilot.enabled)
    end)

    it("passes through table value via apply", function()
      config_facade.apply(config_facade.LAYERS.SETUP, { tools = { autopilot = { enabled = false, max_turns = 5 } } })
      local cfg = config_facade.materialize()
      assert.is_false(cfg.tools.autopilot.enabled)
      assert.equals(5, cfg.tools.autopilot.max_turns)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Union list proxy on auto_approve
  -- ---------------------------------------------------------------------------

  describe("auto_approve union list ops", function()
    it("write proxy supports append on auto_approve", function()
      local w = config_facade.writer(nil, config_facade.LAYERS.SETUP)
      w.tools.auto_approve:append("bash")
      local ops = config_facade.dump_layer(config_facade.LAYERS.SETUP)
      local found = false
      for _, op in ipairs(ops) do
        if op.op == "append" and op.path == "tools.auto_approve" and op.value == "bash" then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("write proxy supports remove on auto_approve", function()
      local w = config_facade.writer(nil, config_facade.LAYERS.SETUP)
      w.tools.auto_approve:remove("read")
      local ops = config_facade.dump_layer(config_facade.LAYERS.SETUP)
      local found = false
      for _, op in ipairs(ops) do
        if op.op == "remove" and op.path == "tools.auto_approve" and op.value == "read" then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it("write proxy supports set with list on auto_approve", function()
      local w = config_facade.writer(nil, config_facade.LAYERS.SETUP)
      w.tools.auto_approve = { "bash", "grep" }
      local cfg = config_facade.get()
      assert.are.same({ "bash", "grep" }, cfg.tools.auto_approve)
    end)

    it("write proxy supports set with function on auto_approve", function()
      local fn = function() end
      local w = config_facade.writer(nil, config_facade.LAYERS.SETUP)
      w.tools.auto_approve = fn
      local cfg = config_facade.get()
      assert.equals(fn, cfg.tools.auto_approve)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Tool name population in L10
  -- ---------------------------------------------------------------------------

  describe("tool name population via record_default", function()
    -- Tests record_default directly. The tools module calls record_default in
    -- register_tool() — verified by code inspection and integration tests
    -- (testing via tools.register() here would require clearing the entire
    -- tools module cache to avoid stale facade references).

    it("appends a tool name to the tools list in L10", function()
      config_facade.record_default("append", "tools", "test_tool")
      local info = config_facade.inspect(nil, "tools")
      assert.is_table(info.value)
      assert.truthy(vim.tbl_contains(info.value, "test_tool"))
    end)

    it("multiple appends accumulate in the tools list", function()
      config_facade.record_default("append", "tools", "tool_a")
      config_facade.record_default("append", "tools", "tool_b")
      local info = config_facade.inspect(nil, "tools")
      assert.truthy(vim.tbl_contains(info.value, "tool_a"))
      assert.truthy(vim.tbl_contains(info.value, "tool_b"))
    end)

    it("dedup moves existing tool name to end", function()
      config_facade.record_default("append", "tools", "bash")
      config_facade.record_default("append", "tools", "grep")
      config_facade.record_default("append", "tools", "bash")
      local info = config_facade.inspect(nil, "tools")
      assert.are.same({ "grep", "bash" }, info.value)
    end)

    it("frontmatter set overrides default tool list", function()
      config_facade.record_default("append", "tools", "bash")
      config_facade.record_default("append", "tools", "grep")
      config_facade.record_default("append", "tools", "read")
      -- Frontmatter restricts to a subset
      local store = require("flemma.config.store")
      store.record(store.LAYERS.FRONTMATTER, 1, "set", "tools", { "bash" })
      local info = config_facade.inspect(1, "tools")
      assert.are.same({ "bash" }, info.value)
    end)

    it("frontmatter remove removes from default tool list", function()
      config_facade.record_default("append", "tools", "bash")
      config_facade.record_default("append", "tools", "grep")
      config_facade.record_default("append", "tools", "read")
      local store = require("flemma.config.store")
      store.record(store.LAYERS.FRONTMATTER, 1, "remove", "tools", "bash")
      local info = config_facade.inspect(1, "tools")
      assert.are.same({ "grep", "read" }, info.value)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- apply() with hybrid list (tools = { "bash", "grep" })
  -- ---------------------------------------------------------------------------

  describe("apply with hybrid list", function()
    it("accepts sequential table for hybrid object with allow_list", function()
      local ok, err = config_facade.apply(config_facade.LAYERS.SETUP, {
        tools = { "bash", "grep" },
      })
      assert.is_nil(err)
      assert.is_true(ok)
      -- Hybrid object: list value is read via inspect(), not the read proxy.
      local info = config_facade.inspect(nil, "tools")
      assert.are.same({ "bash", "grep" }, info.value)
    end)

    it("still accepts table of named fields", function()
      local ok, err = config_facade.apply(config_facade.LAYERS.SETUP, {
        tools = { require_approval = false },
      })
      assert.is_nil(err)
      assert.is_true(ok)
      assert.is_false(config_facade.get().tools.require_approval)
    end)
  end)

  describe("presets map", function()
    it("accepts table-valued preset definitions", function()
      local ok, err = config_facade.apply(config_facade.LAYERS.SETUP, {
        presets = {
          ["$haiku"] = { provider = "anthropic", model = "claude-haiku-4-5-20250514" },
        },
      })
      assert.is_nil(err)
      assert.is_true(ok)
      local cfg = config_facade.materialize()
      assert.equals("anthropic", cfg.presets["$haiku"].provider)
      assert.equals("claude-haiku-4-5-20250514", cfg.presets["$haiku"].model)
    end)

    it("accepts string-valued preset definitions", function()
      local ok, err = config_facade.apply(config_facade.LAYERS.SETUP, {
        presets = {
          ["$haiku"] = "anthropic claude-haiku-4-5-20250514",
        },
      })
      assert.is_nil(err)
      assert.is_true(ok)
      local cfg = config_facade.materialize()
      assert.equals("anthropic claude-haiku-4-5-20250514", cfg.presets["$haiku"])
    end)

    it("accepts mixed string and table preset definitions", function()
      local ok, err = config_facade.apply(config_facade.LAYERS.SETUP, {
        presets = {
          ["$fast"] = "anthropic claude-haiku-4-5-20250514 thinking=disabled",
          ["$smart"] = { provider = "anthropic", model = "claude-sonnet-4-20250514" },
        },
      })
      assert.is_nil(err)
      assert.is_true(ok)
      local cfg = config_facade.materialize()
      assert.is_string(cfg.presets["$fast"])
      assert.is_table(cfg.presets["$smart"])
    end)
  end)
end)
