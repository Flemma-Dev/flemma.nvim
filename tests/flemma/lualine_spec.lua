describe("Lualine component", function()
  local flemma_component, core

  before_each(function()
    -- Clean up any buffers created during previous tests
    vim.cmd("silent! %bdelete!")

    -- Mock lualine.component before requiring the flemma component
    package.preload["lualine.component"] = function()
      local component = {}
      component.init = function() end
      component.extend = function()
        return setmetatable({}, { __index = component })
      end
      return component
    end

    -- Invalidate caches to ensure we get fresh modules
    package.loaded["flemma"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.templating.builtins.format"] = nil
    package.loaded["flemma.templating.renderer"] = nil
    package.loaded["lualine.components.flemma"] = nil

    -- Load the component to be tested
    flemma_component = require("lualine.components.flemma")

    -- Initialize flemma with default settings
    local flemma = require("flemma")
    core = require("flemma.core")
    flemma.setup({})

    -- Reset session to prevent leakage between tests
    require("flemma.session").get():reset()

    -- Set up a chat buffer
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = "chat"
  end)

  after_each(function()
    -- Clean up any buffers created during the test
    vim.cmd("silent! %bdelete!")
    -- Clear the preload cache
    package.preload["lualine.component"] = nil
  end)

  it("should display model and reasoning when applicable", function()
    -- Arrange
    core.switch_provider("openai", "o3", { reasoning = "high", temperature = 1 })

    -- Act
    local status = flemma_component:update_status()

    -- Assert (default format from config.lua)
    assert.are.equal("o3 (high)", status)
  end)

  it("should display thinking level from default for o-series model", function()
    -- Arrange: No explicit reasoning, but default thinking="high" applies
    core.switch_provider("openai", "o4-mini", {})

    -- Act
    local status = flemma_component:update_status()

    -- Assert: Default thinking="high" is active
    assert.are.equal("o4-mini (high)", status)
  end)

  it("should display only model name when thinking is explicitly disabled", function()
    -- Arrange
    core.switch_provider("openai", "o4-mini", { thinking = false })

    -- Act
    local status = flemma_component:update_status()

    -- Assert
    assert.are.equal("o4-mini", status)
  end)

  it("should display only the model name for non-o-series models", function()
    -- Arrange
    core.switch_provider("openai", "gpt-4o", { reasoning = "high" }) -- Reasoning should be ignored

    -- Act
    local status = flemma_component:update_status()

    -- Assert
    assert.are.equal("gpt-4o", status)
  end)

  it("should display thinking level from default for Anthropic", function()
    -- Arrange: No explicit thinking_budget, but default thinking="high" applies
    core.switch_provider("anthropic", "claude-sonnet-4-5", {})

    -- Act
    local status = flemma_component:update_status()

    -- Assert: Default thinking="high" maps to budget 32768 → level "high"
    assert.are.equal("claude-sonnet-4-5 (high)", status)
  end)

  it("should display only model name for Anthropic when thinking is disabled", function()
    -- Arrange
    core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })

    -- Act
    local status = flemma_component:update_status()

    -- Assert
    assert.are.equal("claude-sonnet-4-5", status)
  end)

  it("should display model with thinking level for Anthropic with valid thinking_budget", function()
    -- Arrange: 2048 maps to "low" level
    core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking_budget = 2048 })

    -- Act
    local status = flemma_component:update_status()

    -- Assert
    assert.are.equal("claude-sonnet-4-5 (low)", status)
  end)

  it("should display thinking indicator for Anthropic with thinking_budget below 1024 (clamped)", function()
    -- Arrange: budget 500 is clamped to 1024, which maps to "low"
    core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking_budget = 500 })

    -- Act
    local status = flemma_component:update_status()

    -- Assert
    assert.are.equal("claude-sonnet-4-5 (low)", status)
  end)

  it("should display model with thinking level for Vertex with valid thinking_budget", function()
    -- Arrange: 1000 maps to "low" level
    core.switch_provider("vertex", "gemini-2.5-pro", { thinking_budget = 1000, project_id = "test-project" })

    -- Act
    local status = flemma_component:update_status()

    -- Assert
    assert.are.equal("gemini-2.5-pro (low)", status)
  end)

  it("should return an empty string if filetype is not 'chat'", function()
    -- Arrange
    vim.bo.filetype = "lua"
    core.switch_provider("openai", "o4-mini", { reasoning = "high" })

    -- Act
    local status = flemma_component:update_status()

    -- Assert
    assert.are.equal("", status)
  end)

  it("should return an empty string if model is not set", function()
    -- Arrange: override model to nil at runtime layer (setup sets a default model)
    local store = require("flemma.config.store")
    store.record(require("flemma.config").LAYERS.RUNTIME, nil, "set", "model", nil)

    -- Act
    local status = flemma_component:update_status()

    -- Assert
    assert.are.equal("", status)
  end)

  describe("custom format strings", function()
    it("should use provider:model format when configured", function()
      -- Arrange: switch first, then set format
      core.switch_provider("anthropic", "claude-sonnet-4-5", {})
      local config_facade = require("flemma.config")
      config_facade.apply(
        config_facade.LAYERS.RUNTIME,
        { statusline = { format = "{{ provider.name }}:{{ model.name }}" } }
      )

      -- Act
      local status = flemma_component:update_status()

      -- Assert
      assert.are.equal("anthropic:claude-sonnet-4-5", status)
    end)

    it("should handle conditionals in custom format", function()
      -- Arrange: switch first, then set format (switch_provider re-materializes state)
      core.switch_provider("openai", "o3", { reasoning = "high", temperature = 1 })
      local config_facade = require("flemma.config")
      config_facade.apply(
        config_facade.LAYERS.RUNTIME,
        { statusline = { format = "{{ model.name }}{% if thinking.enabled then %} [{{ thinking.level }}]{% end %}" } }
      )

      -- Act
      local status = flemma_component:update_status()

      -- Assert
      assert.are.equal("o3 [high]", status)
    end)

    it("should collapse conditional when thinking is off", function()
      -- Arrange
      local config_facade = require("flemma.config")
      config_facade.apply(
        config_facade.LAYERS.RUNTIME,
        { statusline = { format = "{{ model.name }}{% if thinking.enabled then %} [{{ thinking.level }}]{% end %}" } }
      )
      core.switch_provider("openai", "gpt-4o", {})

      -- Act
      local status = flemma_component:update_status()

      -- Assert
      assert.are.equal("gpt-4o", status)
    end)

    it("should support provider-conditional format", function()
      -- Arrange: switch first, then set format
      core.switch_provider("anthropic", "claude-sonnet-4-5", {})
      local config_facade = require("flemma.config")
      config_facade.apply(config_facade.LAYERS.RUNTIME, {
        statusline = { format = "{% if provider.name == 'anthropic' then %}A{% else %}O{% end %}: {{ model.name }}" },
      })

      -- Act
      local status = flemma_component:update_status()

      -- Assert
      assert.are.equal("A: claude-sonnet-4-5", status)
    end)

    it("should trim incidental outer whitespace from multiline string formats", function()
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })
      local config_facade = require("flemma.config")
      config_facade.apply(config_facade.LAYERS.RUNTIME, {
        statusline = {
          format = [[
{{ model.name }}
]],
        },
      })

      local status = flemma_component:update_status()

      assert.are.equal("claude-sonnet-4-5", status)
    end)

    it("should preserve non-breaking spaces at the edges of string formats", function()
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })
      local non_breaking_space = "\194\160"
      local config_facade = require("flemma.config")
      config_facade.apply(config_facade.LAYERS.RUNTIME, {
        statusline = {
          format = non_breaking_space .. "{{ model.name }}" .. non_breaking_space,
        },
      })

      local status = flemma_component:update_status()

      assert.are.equal(non_breaking_space .. "claude-sonnet-4-5" .. non_breaking_space, status)
    end)

    it("should support function formats", function()
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })
      local config_facade = require("flemma.config")
      config_facade.apply(config_facade.LAYERS.RUNTIME, {
        statusline = {
          format = function(env)
            return env.provider.name .. ":" .. env.model.name
          end,
        },
      })

      local status = flemma_component:update_status()

      assert.are.equal("anthropic:claude-sonnet-4-5", status)
    end)

    it("does not escape percent signs in function format output", function()
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })
      local config_facade = require("flemma.config")
      config_facade.apply(config_facade.LAYERS.RUNTIME, {
        statusline = {
          format = function(env)
            return env.model.name .. " 50%"
          end,
        },
      })

      local status = flemma_component:update_status()

      assert.are.equal("claude-sonnet-4-5 50%", status)
    end)

    it("escapes percent signs in template expression output", function()
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })
      local config_facade = require("flemma.config")
      config_facade.apply(config_facade.LAYERS.RUNTIME, {
        statusline = {
          format = "{{ model.name .. ' 50%' }}",
        },
      })

      local status = flemma_component:update_status()

      assert.are.equal("claude-sonnet-4-5 50%%", status)
    end)

    it("does not escape percent signs in template literal text", function()
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })
      local config_facade = require("flemma.config")
      config_facade.apply(config_facade.LAYERS.RUNTIME, {
        statusline = {
          format = "%#Comment#{{ model.name }}%*",
        },
      })

      local status = flemma_component:update_status()

      assert.are.equal("%#Comment#claude-sonnet-4-5%*", status)
    end)
  end)

  describe("session variables", function()
    it("should display session cost when format includes session.cost", function()
      -- Arrange: switch first, then set format
      core.switch_provider("anthropic", "claude-sonnet-4-5", {})
      local config_facade = require("flemma.config")
      config_facade.apply(config_facade.LAYERS.RUNTIME, {
        statusline = {
          format = "{{ model.name }}{% if session.cost then %} {{ format.money(session.cost) }}{% end %}",
        },
      })

      -- Add a request to the session
      local s = require("flemma.session").get()
      s:reset()
      s:add_request({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 1000,
        output_tokens = 500,
        input_price = 3.0,
        output_price = 15.0,
      })

      -- Act
      local status = flemma_component:update_status()

      -- Assert: cost = (1000/1M)*3 + (500/1M)*15 = 0.003 + 0.0075 = 0.0105 → $0.01
      assert.are.equal("claude-sonnet-4-5 $0.01", status)
    end)

    it("should display request count", function()
      -- Arrange: switch first, then set format
      core.switch_provider("anthropic", "claude-sonnet-4-5", {})
      local config_facade = require("flemma.config")
      config_facade.apply(
        config_facade.LAYERS.RUNTIME,
        { statusline = { format = "{{ model.name }} ({{ session.requests }})" } }
      )

      local s = require("flemma.session").get()
      s:reset()
      s:add_request({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 100,
        output_tokens = 50,
        input_price = 3.0,
        output_price = 15.0,
      })
      s:add_request({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 200,
        output_tokens = 100,
        input_price = 3.0,
        output_price = 15.0,
      })

      -- Act
      local status = flemma_component:update_status()

      -- Assert
      assert.are.equal("claude-sonnet-4-5 (2)", status)
    end)

    it("should hide session variables when no requests exist", function()
      -- Arrange: switch first, then set format (switch_provider re-materializes state)
      core.switch_provider("anthropic", "claude-sonnet-4-5", {})
      local config_facade = require("flemma.config")
      config_facade.apply(config_facade.LAYERS.RUNTIME, {
        statusline = {
          format = "{{ model.name }}{% if session.cost then %} {{ format.money(session.cost) }}{% end %}",
        },
      })

      local s = require("flemma.session").get()
      s:reset()

      -- Act
      local status = flemma_component:update_status()

      -- Assert: cost is empty, conditional collapses
      assert.are.equal("claude-sonnet-4-5", status)
    end)

    it("should format tokens compactly", function()
      -- Arrange: switch first, then set format
      core.switch_provider("anthropic", "claude-sonnet-4-5", {})
      local config_facade = require("flemma.config")
      config_facade.apply(config_facade.LAYERS.RUNTIME, {
        statusline = {
          format = "↑{{ format.tokens(session.tokens.input) }} ↓{{ format.tokens(session.tokens.output) }}",
        },
      })

      local s = require("flemma.session").get()
      s:reset()
      s:add_request({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 15000,
        output_tokens = 2000000,
        input_price = 3.0,
        output_price = 15.0,
      })

      -- Act
      local status = flemma_component:update_status()

      -- Assert
      assert.are.equal("↑15K ↓2M", status)
    end)

    it("should display last request cost", function()
      -- Arrange: switch first, then set format (switch_provider re-materializes state)
      core.switch_provider("anthropic", "claude-sonnet-4-5", {})
      local config_facade = require("flemma.config")
      config_facade.apply(
        config_facade.LAYERS.RUNTIME,
        { statusline = { format = "{{ model.name }} last:{{ format.money(last.cost) }}" } }
      )

      local s = require("flemma.session").get()
      s:reset()
      s:add_request({
        provider = "anthropic",
        model = "claude-sonnet-4-5",
        input_tokens = 100000,
        output_tokens = 5000,
        input_price = 3.0,
        output_price = 15.0,
      })

      -- Act
      local status = flemma_component:update_status()

      -- Assert: cost = (100000/1M)*3 + (5000/1M)*15 = 0.30 + 0.075 = 0.375
      assert.are.equal("claude-sonnet-4-5 last:$0.375", status)
    end)
  end)

  describe("lualine options format override", function()
    after_each(function()
      flemma_component.options = nil
    end)

    it("should use format from lualine options when provided", function()
      -- Arrange: simulates { 'flemma', format = '...' } in lualine section config
      flemma_component.options = { format = "{{ provider.name }}:{{ model.name }}" }
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })

      -- Act
      local status = flemma_component:update_status()

      -- Assert
      assert.are.equal("anthropic:claude-sonnet-4-5", status)
    end)

    it("should fall back to flemma config format when lualine options has no format key", function()
      -- Arrange: options table present but no format key
      flemma_component.options = {}
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })

      -- Act
      local status = flemma_component:update_status()

      -- Assert: default format from flemma config
      assert.are.equal("claude-sonnet-4-5", status)
    end)

    it("should prefer lualine options format over flemma config format", function()
      -- Arrange: conflicting formats — lualine option should win
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })
      local config_facade = require("flemma.config")
      config_facade.apply(config_facade.LAYERS.RUNTIME, { statusline = { format = "config:{{ model.name }}" } })
      flemma_component.options = { format = "options:{{ model.name }}" }

      -- Act
      local status = flemma_component:update_status()

      -- Assert
      assert.are.equal("options:claude-sonnet-4-5", status)
    end)
  end)

  describe("booting variable", function()
    it("should be truthy while async tool sources are pending", function()
      -- Arrange
      local config_facade = require("flemma.config")
      config_facade.apply(
        config_facade.LAYERS.RUNTIME,
        { statusline = { format = "{% if booting then %}booting{% else %}ready{% end %}" } }
      )

      local tools = require("flemma.tools")
      tools.clear()
      local captured_done
      tools.register_async(function(_register, done)
        captured_done = done
      end)

      -- Act
      local status_text = flemma_component:update_status()

      -- Assert
      assert.are.equal("booting", status_text)

      -- Cleanup: resolve the async source
      captured_done()
    end)

    it("should refresh lualine on FlemmaBootComplete", function()
      -- Arrange: track lualine.refresh() calls
      local refresh_called = false
      package.loaded["lualine"] = {
        refresh = function()
          refresh_called = true
        end,
      }

      -- Re-require component so init() picks up the mock
      package.loaded["lualine.components.flemma"] = nil
      flemma_component = require("lualine.components.flemma")

      -- Simulate init() being called (lualine calls this on component creation)
      if flemma_component.init then
        flemma_component:init({})
      end

      -- Act: emit the autocmd
      vim.api.nvim_exec_autocmds("User", { pattern = "FlemmaBootComplete" })

      -- Assert
      assert.is_true(refresh_called)

      -- Cleanup
      package.loaded["lualine"] = nil
    end)

    it("should refresh lualine on FlemmaConfigUpdated", function()
      -- Arrange: track lualine.refresh() calls
      local refresh_count = 0
      package.loaded["lualine"] = {
        refresh = function()
          refresh_count = refresh_count + 1
        end,
      }

      -- Re-require component so init() picks up the mock
      package.loaded["lualine.components.flemma"] = nil
      flemma_component = require("lualine.components.flemma")

      -- Simulate init() being called (lualine calls this on component creation)
      if flemma_component.init then
        flemma_component:init({})
      end

      -- Act: emit the autocmd twice (not once-only like BootComplete)
      vim.api.nvim_exec_autocmds("User", { pattern = "FlemmaConfigUpdated" })
      vim.api.nvim_exec_autocmds("User", { pattern = "FlemmaConfigUpdated" })

      -- Assert
      assert.are.equal(2, refresh_count)

      -- Cleanup
      package.loaded["lualine"] = nil
    end)

    it("should be falsy once all async tool sources resolve", function()
      -- Arrange
      local config_facade = require("flemma.config")
      config_facade.apply(
        config_facade.LAYERS.RUNTIME,
        { statusline = { format = "{% if booting then %}booting{% else %}ready{% end %}" } }
      )

      local tools = require("flemma.tools")
      tools.clear()

      -- Act (no pending async sources)
      local status_text = flemma_component:update_status()

      -- Assert
      assert.are.equal("ready", status_text)
    end)
  end)

  describe("buffer.tokens.input variable", function()
    local client = require("flemma.client")

    before_each(function()
      -- Add a @You: message so build_prompt_and_provider does not bail early.
      local bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "Hello" })
      -- Reset prefetch state so prior test entries do not bleed across.
      package.loaded["flemma.usage.prefetch"] = nil
    end)

    after_each(function()
      client.clear_fixtures()
      local prefetch = require("flemma.usage.prefetch")
      prefetch._reset_for_tests()
    end)

    it("does not start token prefetch when buffer tokens are not referenced", function()
      core.switch_provider("anthropic", "claude-sonnet-4-6", { thinking = false })
      flemma_component.options = { format = "{{ model.name }}" }

      local status = flemma_component:update_status()
      local prefetch = require("flemma.usage.prefetch")

      assert.equals("claude-sonnet-4-6", status)
      assert.is_false(prefetch._is_tracked(vim.api.nvim_get_current_buf()))
    end)

    it("renders empty before the fetch completes", function()
      core.switch_provider("anthropic", "claude-sonnet-4-6", { thinking = false })
      -- No fixture registered — fetch hasn't landed yet.

      flemma_component.options =
        { format = "{% if buffer.tokens.input then %}{{ format.number(buffer.tokens.input) }}{% end %}" }
      local status = flemma_component:update_status()

      assert.equals("", status)
    end)

    it("renders the formatted token count after a successful fetch", function()
      client.register_fixture("messages/count_tokens", "tests/fixtures/anthropic/count_tokens_response.txt")
      core.switch_provider("anthropic", "claude-sonnet-4-6", { thinking = false })

      flemma_component.options =
        { format = "{% if buffer.tokens.input then %}{{ format.number(buffer.tokens.input) }}{% end %}" }
      -- First call installs tracking; wait for the fetch to populate the cache.
      flemma_component:update_status()
      local prefetch = require("flemma.usage.prefetch")
      vim.wait(2000, function()
        return prefetch.get_tokens(vim.api.nvim_get_current_buf()) ~= nil
      end, 10)

      local status = flemma_component:update_status()
      assert.equals("5,432", status)
    end)

    it("can render context percentage from raw buffer and model token values", function()
      client.register_fixture("messages/count_tokens", "tests/fixtures/anthropic/count_tokens_response.txt")
      core.switch_provider("anthropic", "claude-sonnet-4-6", { thinking = false })

      flemma_component.options = {
        format = "{% if buffer.tokens.input and model.max_input_tokens then %}{{ format.percent(buffer.tokens.input / model.max_input_tokens, 1) }}{% end %}",
      }
      flemma_component:update_status()
      local prefetch = require("flemma.usage.prefetch")
      vim.wait(2000, function()
        return prefetch.get_tokens(vim.api.nvim_get_current_buf()) ~= nil
      end, 10)

      local status = flemma_component:update_status()
      assert.equals("0.5%%", status)
    end)

    it("refreshes lualine on FlemmaUsageEstimated", function()
      local refresh_count = 0
      package.loaded["lualine"] = {
        refresh = function()
          refresh_count = refresh_count + 1
        end,
      }

      package.loaded["lualine.components.flemma"] = nil
      flemma_component = require("lualine.components.flemma")
      if flemma_component.init then
        flemma_component:init({})
      end

      vim.api.nvim_exec_autocmds("User", { pattern = "FlemmaUsageEstimated" })
      vim.api.nvim_exec_autocmds("User", { pattern = "FlemmaUsageEstimated" })

      assert.are.equal(2, refresh_count)
      package.loaded["lualine"] = nil
    end)
  end)

  describe("%* rewrite for lualine section default", function()
    after_each(function()
      flemma_component.options = nil
      flemma_component.get_default_hl = nil
    end)

    it("should rewrite %* to section default hl when rendered via lualine", function()
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })
      flemma_component.options = { format = "pre%*post" }
      flemma_component.get_default_hl = function()
        return "%#lualine_c_normal#"
      end

      local status = flemma_component:update_status()

      assert.are.equal("pre%#lualine_c_normal#post", status)
    end)

    it("should leave %* untouched when get_default_hl is absent (raw statusline)", function()
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })
      flemma_component.options = { format = "pre%*post" }

      local status = flemma_component:update_status()

      assert.are.equal("pre%*post", status)
    end)

    it("should rewrite multiple %* occurrences", function()
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })
      flemma_component.options = { format = "%*a%*b%*" }
      flemma_component.get_default_hl = function()
        return "%#X#"
      end

      local status = flemma_component:update_status()

      assert.are.equal("%#X#a%#X#b%#X#", status)
    end)

    it("should leave %* untouched when get_default_hl returns empty string", function()
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })
      flemma_component.options = { format = "pre%*post" }
      flemma_component.get_default_hl = function()
        return ""
      end

      local status = flemma_component:update_status()

      assert.are.equal("pre%*post", status)
    end)
  end)

  describe("FlemmaStatusTextMuted rewrite for lualine section bg", function()
    after_each(function()
      flemma_component.options = nil
      flemma_component.get_default_hl = nil
      flemma_component._muted_section_bg = nil
      flemma_component._muted_fg = nil
      vim.api.nvim_set_hl(0, "FlemmaStatusTextMuted", {})
      vim.api.nvim_set_hl(0, "FlemmaStatusTextMuted2", {})
      vim.api.nvim_set_hl(0, "lualine_c_normal", {})
    end)

    it("should rewrite %#FlemmaStatusTextMuted# to render group with section bg", function()
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })
      vim.api.nvim_set_hl(0, "FlemmaStatusTextMuted", { bg = 0x202020, fg = 0x9c9c9c })
      vim.api.nvim_set_hl(0, "lualine_c_normal", { bg = 0x303040, fg = 0xe0e0e0 })
      flemma_component.options = { format = "pre%#FlemmaStatusTextMuted#post" }
      flemma_component.get_default_hl = function()
        return "%#lualine_c_normal#"
      end

      local status = flemma_component:update_status()

      assert.are.equal("pre%#FlemmaStatusTextMuted2#post", status)
      local render_hl = vim.api.nvim_get_hl(0, { name = "FlemmaStatusTextMuted2", link = false })
      assert.are.equal(0x303040, render_hl.bg)
      assert.are.equal(0x9c9c9c, render_hl.fg)
    end)

    it("should leave %#FlemmaStatusTextMuted# untouched when get_default_hl is absent", function()
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })
      vim.api.nvim_set_hl(0, "FlemmaStatusTextMuted", { bg = 0x202020, fg = 0x9c9c9c })
      flemma_component.options = { format = "pre%#FlemmaStatusTextMuted#post" }

      local status = flemma_component:update_status()

      assert.are.equal("pre%#FlemmaStatusTextMuted#post", status)
    end)

    it("should not touch FlemmaStatusTextMuted2 when the escape is absent from the format", function()
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })
      vim.api.nvim_set_hl(0, "FlemmaStatusTextMuted", { bg = 0x202020, fg = 0x9c9c9c })
      vim.api.nvim_set_hl(0, "lualine_c_normal", { bg = 0x303040, fg = 0xe0e0e0 })
      -- Pre-set FlemmaStatusTextMuted2 to a sentinel; the gate should leave it alone.
      vim.api.nvim_set_hl(0, "FlemmaStatusTextMuted2", { bg = 0xaabbcc, fg = 0x112233 })
      flemma_component.options = { format = "{{ model.name }}" }
      flemma_component.get_default_hl = function()
        return "%#lualine_c_normal#"
      end

      flemma_component:update_status()

      local hl = vim.api.nvim_get_hl(0, { name = "FlemmaStatusTextMuted2", link = false })
      assert.are.equal(0xaabbcc, hl.bg)
      assert.are.equal(0x112233, hl.fg)
    end)

    it("should skip rewrite when default_hl is not a lualine_ escape", function()
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })
      vim.api.nvim_set_hl(0, "FlemmaStatusTextMuted", { bg = 0x202020, fg = 0x9c9c9c })
      flemma_component.options = { format = "pre%#FlemmaStatusTextMuted#post" }
      flemma_component.get_default_hl = function()
        return "%#StatusLine#"
      end

      local status = flemma_component:update_status()

      assert.are.equal("pre%#FlemmaStatusTextMuted#post", status)
    end)

    it("should skip rewrite when section hl lacks bg", function()
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })
      vim.api.nvim_set_hl(0, "FlemmaStatusTextMuted", { bg = 0x202020, fg = 0x9c9c9c })
      vim.api.nvim_set_hl(0, "lualine_c_normal", { fg = 0xe0e0e0 })
      flemma_component.options = { format = "pre%#FlemmaStatusTextMuted#post" }
      flemma_component.get_default_hl = function()
        return "%#lualine_c_normal#"
      end

      local status = flemma_component:update_status()

      assert.are.equal("pre%#FlemmaStatusTextMuted#post", status)
    end)

    it("should not re-set FlemmaStatusTextMuted2 when inputs are unchanged", function()
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })
      vim.api.nvim_set_hl(0, "FlemmaStatusTextMuted", { bg = 0x202020, fg = 0x9c9c9c })
      vim.api.nvim_set_hl(0, "lualine_c_normal", { bg = 0x303040, fg = 0xe0e0e0 })
      flemma_component.options = { format = "%#FlemmaStatusTextMuted#" }
      flemma_component.get_default_hl = function()
        return "%#lualine_c_normal#"
      end

      -- First call populates the cache and sets FlemmaStatusTextMuted2
      flemma_component:update_status()
      assert.are.equal(0x303040, vim.api.nvim_get_hl(0, { name = "FlemmaStatusTextMuted2", link = false }).bg)

      -- Tamper with the render group to detect whether the next call rewrites it.
      -- If the cache is working, identical inputs short-circuit nvim_set_hl and
      -- the tampered values survive.
      vim.api.nvim_set_hl(0, "FlemmaStatusTextMuted2", { bg = 0xaabbcc, fg = 0x112233 })
      flemma_component:update_status()

      local hl = vim.api.nvim_get_hl(0, { name = "FlemmaStatusTextMuted2", link = false })
      assert.are.equal(0xaabbcc, hl.bg)
      assert.are.equal(0x112233, hl.fg)
    end)

    it("should re-set FlemmaStatusTextMuted2 when section bg changes (mode switch)", function()
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })
      vim.api.nvim_set_hl(0, "FlemmaStatusTextMuted", { bg = 0x202020, fg = 0x9c9c9c })
      vim.api.nvim_set_hl(0, "lualine_c_normal", { bg = 0x303040, fg = 0xe0e0e0 })
      flemma_component.options = { format = "%#FlemmaStatusTextMuted#" }
      flemma_component.get_default_hl = function()
        return "%#lualine_c_normal#"
      end

      flemma_component:update_status()

      -- Simulate mode change: section bg shifts to a different value
      vim.api.nvim_set_hl(0, "lualine_c_normal", { bg = 0x404050, fg = 0xe0e0e0 })
      flemma_component:update_status()

      assert.are.equal(0x404050, vim.api.nvim_get_hl(0, { name = "FlemmaStatusTextMuted2", link = false }).bg)
    end)

    it("should re-set FlemmaStatusTextMuted2 when muted fg changes (colorscheme)", function()
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking = false })
      vim.api.nvim_set_hl(0, "FlemmaStatusTextMuted", { bg = 0x202020, fg = 0x9c9c9c })
      vim.api.nvim_set_hl(0, "lualine_c_normal", { bg = 0x303040, fg = 0xe0e0e0 })
      flemma_component.options = { format = "%#FlemmaStatusTextMuted#" }
      flemma_component.get_default_hl = function()
        return "%#lualine_c_normal#"
      end

      flemma_component:update_status()

      -- Simulate colorscheme change: muted fg shifts
      vim.api.nvim_set_hl(0, "FlemmaStatusTextMuted", { bg = 0x202020, fg = 0x7a7a7a })
      flemma_component:update_status()

      assert.are.equal(0x7a7a7a, vim.api.nvim_get_hl(0, { name = "FlemmaStatusTextMuted2", link = false }).fg)
    end)
  end)

  describe("suspense handling", function()
    local readiness

    before_each(function()
      readiness = require("flemma.readiness")
      core.switch_provider("anthropic", "claude-sonnet-4-6", { thinking = false })
    end)

    after_each(function()
      flemma_component._reset_pending_refreshes()
      readiness._reset_for_tests()
    end)

    it("returns empty string when _do_update_status raises suspense", function()
      local boundary = readiness.get_or_create_boundary("test:lualine", function() end)
      local original = flemma_component._do_update_status
      flemma_component._do_update_status = function()
        error(readiness.Suspense.new("Resolving\u{2026}", boundary))
      end

      local status = flemma_component:update_status()

      assert.are.equal("", status)
      flemma_component._do_update_status = original
    end)

    it("subscribes to the boundary and refreshes lualine on success", function()
      local captured_done
      local boundary = readiness.get_or_create_boundary("test:lualine:refresh", function(done)
        captured_done = done
      end)

      local original = flemma_component._do_update_status
      flemma_component._do_update_status = function()
        error(readiness.Suspense.new("Resolving\u{2026}", boundary))
      end

      flemma_component:update_status()
      flemma_component._do_update_status = original

      vim.wait(100, function()
        return captured_done ~= nil
      end, 10)

      local refresh_count = 0
      package.loaded["lualine"] = {
        refresh = function()
          refresh_count = refresh_count + 1
        end,
      }
      captured_done({ ok = true })

      assert.are.equal(1, refresh_count)
      package.loaded["lualine"] = nil
    end)

    it("does not refresh on boundary failure", function()
      local captured_done
      local boundary = readiness.get_or_create_boundary("test:lualine:fail", function(done)
        captured_done = done
      end)

      local original = flemma_component._do_update_status
      flemma_component._do_update_status = function()
        error(readiness.Suspense.new("Resolving\u{2026}", boundary))
      end

      flemma_component:update_status()
      flemma_component._do_update_status = original

      vim.wait(100, function()
        return captured_done ~= nil
      end, 10)

      local refresh_count = 0
      package.loaded["lualine"] = {
        refresh = function()
          refresh_count = refresh_count + 1
        end,
      }
      captured_done({ ok = false })

      assert.are.equal(0, refresh_count)
      package.loaded["lualine"] = nil
    end)

    it("deduplicates subscriptions for the same boundary", function()
      local captured_done
      local boundary = readiness.get_or_create_boundary("test:lualine:dedup", function(done)
        captured_done = done
      end)

      local original = flemma_component._do_update_status
      flemma_component._do_update_status = function()
        error(readiness.Suspense.new("Resolving\u{2026}", boundary))
      end

      flemma_component:update_status()
      flemma_component:update_status()
      flemma_component:update_status()
      flemma_component._do_update_status = original

      vim.wait(100, function()
        return captured_done ~= nil
      end, 10)

      local refresh_count = 0
      package.loaded["lualine"] = {
        refresh = function()
          refresh_count = refresh_count + 1
        end,
      }
      captured_done({ ok = true })

      assert.are.equal(1, refresh_count)
      package.loaded["lualine"] = nil
    end)
  end)

  describe("parameter changes via switch reflect in display", function()
    it("should reflect reasoning level from config facade", function()
      -- Start with base config: default thinking="high" applies
      core.switch_provider("openai", "o3", { temperature = 1 })
      assert.are.equal("o3 (high)", flemma_component:update_status())

      -- Switch again with different reasoning level — writes to RUNTIME layer
      core.switch_provider("openai", "o3", { reasoning = "low", temperature = 1 })
      assert.are.equal("o3 (low)", flemma_component:update_status())
    end)

    it("should reflect thinking_budget changes from config facade", function()
      -- Start with base config: default thinking="high" → budget 32768 → "high"
      core.switch_provider("anthropic", "claude-sonnet-4-5", {})
      assert.are.equal("claude-sonnet-4-5 (high)", flemma_component:update_status())

      -- Switch with explicit thinking_budget — writes to RUNTIME layer
      core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking_budget = 2048 })
      assert.are.equal("claude-sonnet-4-5 (low)", flemma_component:update_status())
    end)

    it("should reflect changed reasoning level via switch", function()
      -- Start with base reasoning = "low"
      core.switch_provider("openai", "o3", { reasoning = "low", temperature = 1 })
      assert.are.equal("o3 (low)", flemma_component:update_status())

      -- Switch with "high" reasoning
      core.switch_provider("openai", "o3", { reasoning = "high", temperature = 1 })
      assert.are.equal("o3 (high)", flemma_component:update_status())
    end)
  end)
end)
