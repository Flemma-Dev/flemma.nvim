--- Tests for the global configuration schema definition.
--- Verifies that the schema materializes correctly and matches the current
--- config.lua defaults, that provider schemas are accessible, and that
--- structural features (aliases, DISCOVER) are properly configured.

local facade = require("flemma.config.facade")

describe("config.schema.definition", function()
  local schema

  before_each(function()
    package.loaded["flemma.config.schema.definition"] = nil
    package.loaded["flemma.config.facade"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    facade = require("flemma.config.facade")
    schema = require("flemma.config.schema.definition")
    facade.init(schema)
  end)

  -- ---------------------------------------------------------------------------
  -- Materialization: verify defaults match current config.lua
  -- ---------------------------------------------------------------------------

  describe("materialization", function()
    it("materializes provider default", function()
      local cfg = facade.get()
      assert.equals("anthropic", cfg.provider)
    end)

    it("materializes model as nil (provider-specific default)", function()
      local cfg = facade.get()
      assert.is_nil(cfg.model)
    end)

    it("materializes parameter defaults", function()
      local cfg = facade.get()
      assert.equals("50%", cfg.parameters.max_tokens)
      assert.equals(0.7, cfg.parameters.temperature)
      assert.equals(600, cfg.parameters.timeout)
      assert.equals(10, cfg.parameters.connect_timeout)
      assert.equals("short", cfg.parameters.cache_retention)
      assert.equals("high", cfg.parameters.thinking)
    end)

    it("materializes highlight defaults (string)", function()
      local cfg = facade.get()
      assert.equals("Special", cfg.highlights.system)
      assert.equals("Normal", cfg.highlights.user)
      assert.equals("Function", cfg.highlights.tool_name)
    end)

    it("materializes highlight defaults (table)", function()
      local cfg = facade.get()
      local tb = cfg.highlights.thinking_block
      assert.is_table(tb)
      assert.equals("Comment+bg:#102020-fg:#111111", tb.dark)
      assert.equals("Comment-bg:#102020+fg:#111111", tb.light)
    end)

    it("materializes ruler defaults", function()
      local cfg = facade.get()
      assert.is_true(cfg.ruler.enabled)
      assert.is_table(cfg.ruler.hl)
    end)

    it("materializes signs defaults", function()
      local cfg = facade.get()
      assert.is_false(cfg.signs.enabled)
      assert.is_true(cfg.signs.system.hl)
      assert.is_nil(cfg.signs.system.char)
    end)

    it("materializes line_highlights defaults", function()
      local cfg = facade.get()
      assert.is_true(cfg.line_highlights.enabled)
      assert.is_table(cfg.line_highlights.frontmatter)
    end)

    it("materializes notifications defaults", function()
      local cfg = facade.get()
      assert.is_true(cfg.notifications.enabled)
      assert.equals(10000, cfg.notifications.timeout)
      assert.equals(1, cfg.notifications.limit)
      assert.equals("overlay", cfg.notifications.position)
      assert.equals(30, cfg.notifications.zindex)
      assert.is_false(cfg.notifications.border)
    end)

    it("materializes progress defaults", function()
      local cfg = facade.get()
      assert.equals("StatusLine", cfg.progress.highlight)
      assert.equals(50, cfg.progress.zindex)
    end)

    it("materializes pricing defaults", function()
      local cfg = facade.get()
      assert.is_true(cfg.pricing.enabled)
    end)

    it("materializes statusline defaults", function()
      local cfg = facade.get()
      assert.is_string(cfg.statusline.format)
      assert.truthy(cfg.statusline.format:find("#{model}"))
    end)

    it("materializes tools defaults", function()
      local cfg = facade.get()
      assert.is_true(cfg.tools.require_approval)
      assert.same({ "$default" }, cfg.tools.auto_approve)
      assert.is_true(cfg.tools.auto_approve_sandboxed)
      assert.same({}, cfg.tools.presets)
      assert.is_true(cfg.tools.autopilot.enabled)
      assert.equals(100, cfg.tools.autopilot.max_turns)
      assert.equals(2, cfg.tools.max_concurrent)
      assert.equals(30, cfg.tools.default_timeout)
      assert.is_true(cfg.tools.show_spinner)
      assert.equals("result", cfg.tools.cursor_after_result)
      assert.same({}, cfg.tools.modules)
    end)

    it("materializes templating defaults", function()
      local cfg = facade.get()
      assert.same({}, cfg.templating.modules)
    end)

    it("materializes presets as empty map", function()
      local cfg = facade.get()
      assert.same({}, cfg.presets)
    end)

    it("materializes text_object default", function()
      local cfg = facade.get()
      assert.equals("m", cfg.text_object)
    end)

    it("materializes editing defaults", function()
      local cfg = facade.get()
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
      local cfg = facade.get()
      assert.is_false(cfg.logging.enabled)
      assert.is_string(cfg.logging.path)
      assert.truthy(cfg.logging.path:find("flemma.log"))
      assert.equals("DEBUG", cfg.logging.level)
    end)

    it("materializes keymaps defaults", function()
      local cfg = facade.get()
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
      local cfg = facade.get()
      assert.is_false(cfg.diagnostics.enabled)
    end)

    it("materializes sandbox defaults", function()
      local cfg = facade.get()
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
      local cfg = facade.get()
      assert.equals("gcloud", cfg.secrets.gcloud.path)
    end)

    it("materializes experimental defaults", function()
      local cfg = facade.get()
      assert.is_true(cfg.experimental.lsp)
      assert.is_false(cfg.experimental.tools)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Provider parameter schemas
  -- ---------------------------------------------------------------------------

  describe("provider parameter schemas (via registration)", function()
    local provider_reg

    before_each(function()
      -- Re-require the registry so its facade local picks up the current (re-init'd) facade
      package.loaded["flemma.provider.registry"] = nil
      provider_reg = require("flemma.provider.registry")
      provider_reg.clear()
    end)

    it("materializes OpenAI reasoning_summary default after registration", function()
      provider_reg.register("flemma.provider.providers.openai")
      local cfg = facade.get()
      assert.equals("auto", cfg.parameters.openai.reasoning_summary)
    end)

    it("materializes Vertex location default after registration", function()
      provider_reg.register("flemma.provider.providers.vertex")
      local cfg = facade.get()
      assert.equals("global", cfg.parameters.vertex.location)
    end)

    it("does not materialize Anthropic defaults (all optional, no defaults)", function()
      provider_reg.register("flemma.provider.providers.anthropic")
      local cfg = facade.get()
      assert.is_nil(cfg.parameters.anthropic.thinking_budget)
    end)

    it("does not materialize Vertex project_id (optional, no default)", function()
      provider_reg.register("flemma.provider.providers.vertex")
      local cfg = facade.get()
      assert.is_nil(cfg.parameters.vertex.project_id)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Schema setup overrides
  -- ---------------------------------------------------------------------------

  describe("setup overrides", function()
    it("accepts scalar override via apply", function()
      facade.apply(facade.LAYERS.SETUP, { provider = "openai" })
      local cfg = facade.get()
      assert.equals("openai", cfg.provider)
    end)

    it("accepts parameter override via apply", function()
      facade.apply(facade.LAYERS.SETUP, { parameters = { timeout = 1200 } })
      local cfg = facade.get()
      assert.equals(1200, cfg.parameters.timeout)
      -- Other parameters retain defaults
      assert.equals(0.7, cfg.parameters.temperature)
    end)

    it("accepts integer max_tokens override", function()
      facade.apply(facade.LAYERS.SETUP, { parameters = { max_tokens = 8192 } })
      local cfg = facade.get()
      assert.equals(8192, cfg.parameters.max_tokens)
    end)

    it("accepts string max_tokens override", function()
      facade.apply(facade.LAYERS.SETUP, { parameters = { max_tokens = "75%" } })
      local cfg = facade.get()
      assert.equals("75%", cfg.parameters.max_tokens)
    end)

    it("accepts thinking = false (disable)", function()
      facade.apply(facade.LAYERS.SETUP, { parameters = { thinking = false } })
      local cfg = facade.get()
      assert.is_false(cfg.parameters.thinking)
    end)

    it("rejects thinking = true (use a named level instead)", function()
      local ok, err = facade.apply(facade.LAYERS.SETUP, { parameters = { thinking = true } })
      assert.is_nil(ok)
      assert.truthy(err:find("no union branch matched"))
    end)

    it("accepts thinking numeric override", function()
      facade.apply(facade.LAYERS.SETUP, { parameters = { thinking = 4096 } })
      local cfg = facade.get()
      assert.equals(4096, cfg.parameters.thinking)
    end)

    it("accepts highlight string override for table-default field", function()
      facade.apply(facade.LAYERS.SETUP, {
        highlights = { thinking_block = "MyCustomHighlight" },
      })
      local cfg = facade.get()
      assert.equals("MyCustomHighlight", cfg.highlights.thinking_block)
    end)

    it("accepts text_object = false", function()
      facade.apply(facade.LAYERS.SETUP, { text_object = false })
      local cfg = facade.get()
      assert.is_false(cfg.text_object)
    end)

    it("rejects text_object = true", function()
      local ok, err = facade.apply(facade.LAYERS.SETUP, { text_object = true })
      assert.is_nil(ok)
      assert.truthy(err:find("no union branch matched"))
    end)

    it("accepts fold_toggle = false", function()
      facade.apply(facade.LAYERS.SETUP, {
        keymaps = { normal = { fold_toggle = false } },
      })
      local cfg = facade.get()
      assert.is_false(cfg.keymaps.normal.fold_toggle)
    end)

    it("accepts notification border string override", function()
      facade.apply(facade.LAYERS.SETUP, {
        notifications = { border = "underline" },
      })
      local cfg = facade.get()
      assert.equals("underline", cfg.notifications.border)
    end)

    it("rejects unknown top-level key", function()
      local ok, err = facade.apply(facade.LAYERS.SETUP, { nonexistent = true })
      assert.is_nil(ok)
      assert.truthy(err:find("unknown key"))
    end)

    it("accepts provider-specific parameter overrides after registration", function()
      package.loaded["flemma.provider.registry"] = nil
      local provider_reg = require("flemma.provider.registry")
      provider_reg.clear()
      provider_reg.register("flemma.provider.providers.anthropic")
      facade.apply(facade.LAYERS.SETUP, {
        parameters = { anthropic = { thinking_budget = 2048 } },
      })
      local cfg = facade.get()
      assert.equals(2048, cfg.parameters.anthropic.thinking_budget)
    end)
  end)

  -- ---------------------------------------------------------------------------
  -- Aliases
  -- ---------------------------------------------------------------------------

  describe("aliases", function()
    it("resolves top-level timeout alias", function()
      facade.apply(facade.LAYERS.SETUP, { timeout = 1200 })
      local cfg = facade.get()
      assert.equals(1200, cfg.parameters.timeout)
    end)

    it("resolves top-level thinking alias", function()
      facade.apply(facade.LAYERS.SETUP, { thinking = "low" })
      local cfg = facade.get()
      assert.equals("low", cfg.parameters.thinking)
    end)

    it("resolves top-level max_tokens alias", function()
      facade.apply(facade.LAYERS.SETUP, { max_tokens = 4096 })
      local cfg = facade.get()
      assert.equals(4096, cfg.parameters.max_tokens)
    end)

    it("resolves top-level temperature alias", function()
      facade.apply(facade.LAYERS.SETUP, { temperature = 0.3 })
      local cfg = facade.get()
      assert.equals(0.3, cfg.parameters.temperature)
    end)

    it("resolves tools.approve alias", function()
      facade.apply(facade.LAYERS.SETUP, {
        tools = { approve = { "bash", "read" } },
      })
      local cfg = facade.get()
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
        "signs",
        "line_highlights",
        "notifications",
        "progress",
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
      provider_reg.register("flemma.provider.providers.anthropic")
      provider_reg.register("flemma.provider.providers.openai")
      provider_reg.register("flemma.provider.providers.vertex")
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
      -- Re-require registries so their facade locals pick up the current (re-init'd) facade
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
        facade.apply(facade.LAYERS.SETUP, {
          tools = { bash = { shell = "zsh" } },
        })
        assert.equals("zsh", facade.get().tools.bash.shell)
      end)

      it("resolves bash cwd and env config", function()
        tools_module.register("flemma.tools.definitions.bash")
        facade.apply(facade.LAYERS.SETUP, {
          tools = { bash = { cwd = "/home", env = { PATH = "/usr/bin" } } },
        })
        local cfg = facade.get()
        assert.equals("/home", cfg.tools.bash.cwd)
        assert.same({ PATH = "/usr/bin" }, cfg.tools.bash.env)
      end)

      it("resolves grep tool config with exclude list", function()
        tools_module.register("flemma.tools.definitions.grep")
        facade.apply(facade.LAYERS.SETUP, {
          tools = { grep = { exclude = { "node_modules", ".git" } } },
        })
        assert.same({ "node_modules", ".git" }, facade.get().tools.grep.exclude)
      end)

      it("resolves find tool config schema", function()
        tools_module.register("flemma.tools.definitions.find")
        facade.apply(facade.LAYERS.SETUP, {
          tools = { find = { cwd = "/home" } },
        })
        assert.equals("/home", facade.get().tools.find.cwd)
      end)

      it("resolves ls tool config schema", function()
        tools_module.register("flemma.tools.definitions.ls")
        facade.apply(facade.LAYERS.SETUP, {
          tools = { ls = { cwd = "/var" } },
        })
        assert.equals("/var", facade.get().tools.ls.cwd)
      end)

      it("rejects unknown field on discovered tool schema", function()
        tools_module.register("flemma.tools.definitions.bash")
        local ok, err = facade.apply(facade.LAYERS.SETUP, {
          tools = { bash = { nonexistent = "value" } },
        })
        assert.is_nil(ok)
        assert.truthy(err:find("unknown key"))
      end)

      it("rejects invalid type on discovered tool schema field", function()
        tools_module.register("flemma.tools.definitions.bash")
        local ok, err = facade.apply(facade.LAYERS.SETUP, {
          tools = { bash = { shell = 42 } },
        })
        assert.is_nil(ok)
        assert.truthy(err)
      end)

      it("errors for unregistered tool without defer_discover", function()
        local ok, err = facade.apply(facade.LAYERS.SETUP, {
          tools = { bash = { shell = "zsh" } },
        })
        assert.is_nil(ok)
        assert.truthy(err:find("unknown key"))
      end)
    end)

    describe("provider DISCOVER", function()
      it("resolves custom provider config schema via registry", function()
        local s = require("flemma.config.schema")
        provider_reg.register("custom", {
          module = "flemma.provider.providers.anthropic",
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
        facade.apply(facade.LAYERS.SETUP, {
          parameters = { custom = { api_url = "https://custom.api" } },
        })
        assert.equals("https://custom.api", facade.get().parameters.custom.api_url)
      end)

      it("built-in provider schemas require registry registration (no special treatment)", function()
        -- Without registration, DISCOVER returns nil → unknown key error
        local ok, err = facade.apply(facade.LAYERS.SETUP, {
          parameters = { anthropic = { thinking_budget = 4096 } },
        })
        assert.is_nil(ok)
        assert.truthy(err:find("unknown key"))
      end)

      it("built-in provider schemas work after registration", function()
        provider_reg.register("flemma.provider.providers.anthropic")
        facade.apply(facade.LAYERS.SETUP, {
          parameters = { anthropic = { thinking_budget = 4096 } },
        })
        assert.equals(4096, facade.get().parameters.anthropic.thinking_budget)
      end)

      it("rejects unknown field on custom provider schema", function()
        local s = require("flemma.config.schema")
        provider_reg.register("custom", {
          module = "flemma.provider.providers.anthropic",
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
        local ok, err = facade.apply(facade.LAYERS.SETUP, {
          parameters = { custom = { nonexistent = "value" } },
        })
        assert.is_nil(ok)
        assert.truthy(err:find("unknown key"))
      end)
    end)

    describe("sandbox backend DISCOVER", function()
      it("resolves bwrap config schema after registration", function()
        sandbox_module.setup()
        facade.apply(facade.LAYERS.SETUP, {
          sandbox = { backends = { bwrap = { path = "/usr/local/bin/bwrap" } } },
        })
        assert.equals("/usr/local/bin/bwrap", facade.get().sandbox.backends.bwrap.path)
      end)

      it("resolves bwrap extra_args config after registration", function()
        sandbox_module.setup()
        facade.apply(facade.LAYERS.SETUP, {
          sandbox = { backends = { bwrap = { extra_args = { "--tmpfs", "/run" } } } },
        })
        assert.same({ "--tmpfs", "/run" }, facade.get().sandbox.backends.bwrap.extra_args)
      end)

      it("rejects unknown field on bwrap schema", function()
        sandbox_module.setup()
        local ok, err = facade.apply(facade.LAYERS.SETUP, {
          sandbox = { backends = { bwrap = { nonexistent = "value" } } },
        })
        assert.is_nil(ok)
        assert.truthy(err:find("unknown key"))
      end)

      it("errors for unregistered bwrap without defer_discover", function()
        local ok, err = facade.apply(facade.LAYERS.SETUP, {
          sandbox = { backends = { bwrap = { path = "/usr/bin/bwrap" } } },
        })
        assert.is_nil(ok)
        assert.truthy(err:find("unknown key"))
      end)

      it("resolves custom backend config schema via registry", function()
        local s_mod = require("flemma.config.schema")
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
        facade.apply(facade.LAYERS.SETUP, {
          sandbox = { backends = { firejail = { profile = "restricted" } } },
        })
        assert.equals("restricted", facade.get().sandbox.backends.firejail.profile)
      end)

      it("rejects unknown field on custom backend schema", function()
        local s_mod = require("flemma.config.schema")
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
        local ok, err = facade.apply(facade.LAYERS.SETUP, {
          sandbox = { backends = { firejail = { nonexistent = "value" } } },
        })
        assert.is_nil(ok)
        assert.truthy(err:find("unknown key"))
      end)

      it("errors for unregistered backend without defer_discover", function()
        local ok, err = facade.apply(facade.LAYERS.SETUP, {
          sandbox = { backends = { nsjail = { config_path = "/etc/nsjail" } } },
        })
        assert.is_nil(ok)
        assert.truthy(err:find("unknown key"))
      end)
    end)

    describe("deferred DISCOVER", function()
      it("defers tool config writes and replays after registration", function()
        local _, err, deferred = facade.apply(
          facade.LAYERS.SETUP,
          { tools = { bash = { shell = "zsh" } } },
          { defer_discover = true }
        )
        assert.is_nil(err)
        assert.is_not_nil(deferred)
        assert.equals(1, #deferred)

        tools_module.register("flemma.tools.definitions.bash")

        local failures = facade.apply_deferred(facade.LAYERS.SETUP, deferred)
        assert.is_nil(failures)
        assert.equals("zsh", facade.get().tools.bash.shell)
      end)

      it("deferred write fails for genuinely unknown tool", function()
        local _, _, deferred = facade.apply(
          facade.LAYERS.SETUP,
          { tools = { nonexistent = { foo = "bar" } } },
          { defer_discover = true }
        )
        assert.is_not_nil(deferred)

        local failures = facade.apply_deferred(facade.LAYERS.SETUP, deferred)
        assert.is_not_nil(failures)
        assert.equals(1, #failures)
      end)

      it("defers multiple tool config writes", function()
        local _, _, deferred = facade.apply(
          facade.LAYERS.SETUP,
          { tools = { bash = { shell = "zsh" }, grep = { exclude = { ".git" } } } },
          { defer_discover = true }
        )
        assert.is_not_nil(deferred)
        assert.equals(2, #deferred)

        tools_module.register("flemma.tools.definitions.bash")
        tools_module.register("flemma.tools.definitions.grep")

        local failures = facade.apply_deferred(facade.LAYERS.SETUP, deferred)
        assert.is_nil(failures)
        assert.equals("zsh", facade.get().tools.bash.shell)
        assert.same({ ".git" }, facade.get().tools.grep.exclude)
      end)

      it("defers custom provider config and replays after registration", function()
        local _, _, deferred = facade.apply(
          facade.LAYERS.SETUP,
          { parameters = { my_provider = { api_url = "https://api.mine" } } },
          { defer_discover = true }
        )
        assert.is_not_nil(deferred)

        local s = require("flemma.config.schema")
        provider_reg.register("my_provider", {
          module = "flemma.provider.providers.anthropic",
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

        local failures = facade.apply_deferred(facade.LAYERS.SETUP, deferred)
        assert.is_nil(failures)
        assert.equals("https://api.mine", facade.get().parameters.my_provider.api_url)
      end)

      it("defers custom backend config and replays after registration", function()
        local _, _, deferred = facade.apply(
          facade.LAYERS.SETUP,
          { sandbox = { backends = { firejail = { profile = "restricted" } } } },
          { defer_discover = true }
        )
        assert.is_not_nil(deferred)

        local s_mod = require("flemma.config.schema")
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

        local failures = facade.apply_deferred(facade.LAYERS.SETUP, deferred)
        assert.is_nil(failures)
        assert.equals("restricted", facade.get().sandbox.backends.firejail.profile)
      end)
    end)
  end)
end)
