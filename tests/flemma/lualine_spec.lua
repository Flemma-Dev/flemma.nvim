describe("Lualine component", function()
  local flemma_component, core

  before_each(function()
    -- Clean up any buffers created during previous tests
    vim.cmd("silent! %bdelete!")

    -- Mock lualine.component before requiring the flemma component
    package.preload["lualine.component"] = function()
      return {
        extend = function()
          return {}
        end,
      }
    end

    -- Invalidate caches to ensure we get fresh modules
    package.loaded["flemma"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.utilities.format"] = nil
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

    -- Assert (uses default format "#{model}#{?#{thinking}, (#{thinking}),}")
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
    -- Arrange: set model to nil via config
    local state = require("flemma.state")
    local config = state.get_config()
    config.model = nil

    -- Act
    local status = flemma_component:update_status()

    -- Assert
    assert.are.equal("", status)
  end)

  describe("custom format strings", function()
    it("should use provider:model format when configured", function()
      -- Arrange
      local state = require("flemma.state")
      local config = state.get_config()
      config.statusline.format = "#{provider}:#{model}"
      core.switch_provider("anthropic", "claude-sonnet-4-5", {})

      -- Act
      local status = flemma_component:update_status()

      -- Assert
      assert.are.equal("anthropic:claude-sonnet-4-5", status)
    end)

    it("should handle conditionals in custom format", function()
      -- Arrange
      local state = require("flemma.state")
      local config = state.get_config()
      config.statusline.format = "#{model}#{?#{thinking}, [#{thinking}],}"
      core.switch_provider("openai", "o3", { reasoning = "high", temperature = 1 })

      -- Act
      local status = flemma_component:update_status()

      -- Assert
      assert.are.equal("o3 [high]", status)
    end)

    it("should collapse conditional when thinking is off", function()
      -- Arrange
      local state = require("flemma.state")
      local config = state.get_config()
      config.statusline.format = "#{model}#{?#{thinking}, [#{thinking}],}"
      core.switch_provider("openai", "gpt-4o", {})

      -- Act
      local status = flemma_component:update_status()

      -- Assert
      assert.are.equal("gpt-4o", status)
    end)

    it("should support provider-conditional format", function()
      -- Arrange
      local state = require("flemma.state")
      local config = state.get_config()
      config.statusline.format = "#{?#{==:#{provider},anthropic},A,O}: #{model}"
      core.switch_provider("anthropic", "claude-sonnet-4-5", {})

      -- Act
      local status = flemma_component:update_status()

      -- Assert
      assert.are.equal("A: claude-sonnet-4-5", status)
    end)
  end)

  describe("session variables", function()
    it("should display session cost when format includes #{session.cost}", function()
      -- Arrange
      local state = require("flemma.state")
      local config = state.get_config()
      config.statusline.format = "#{model} #{?#{session.cost},#{session.cost},}"
      core.switch_provider("anthropic", "claude-sonnet-4-5", {})

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
      -- Arrange
      local state = require("flemma.state")
      local config = state.get_config()
      config.statusline.format = "#{model} (#{session.requests})"
      core.switch_provider("anthropic", "claude-sonnet-4-5", {})

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
      -- Arrange
      local state = require("flemma.state")
      local config = state.get_config()
      config.statusline.format = "#{model}#{?#{session.cost}, #{session.cost},}"
      core.switch_provider("anthropic", "claude-sonnet-4-5", {})

      local s = require("flemma.session").get()
      s:reset()

      -- Act
      local status = flemma_component:update_status()

      -- Assert: cost is empty, conditional collapses
      assert.are.equal("claude-sonnet-4-5", status)
    end)

    it("should format tokens compactly", function()
      -- Arrange
      local state = require("flemma.state")
      local config = state.get_config()
      config.statusline.format = "↑#{session.tokens.input} ↓#{session.tokens.output}"
      core.switch_provider("anthropic", "claude-sonnet-4-5", {})

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
      -- Arrange
      local state = require("flemma.state")
      local config = state.get_config()
      config.statusline.format = "#{model} last:#{last.cost}"
      core.switch_provider("anthropic", "claude-sonnet-4-5", {})

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
      assert.are.equal("claude-sonnet-4-5 last:$0.38", status)
    end)
  end)

  describe("frontmatter overrides", function()
    local state = require("flemma.state")

    it("should reflect reasoning override from frontmatter", function()
      -- Start with base config: default thinking="high" applies
      core.switch_provider("openai", "o3", { temperature = 1 })
      assert.are.equal("o3 (high)", flemma_component:update_status())

      -- Simulate frontmatter override lowering reasoning
      local provider = state.get_provider()
      provider:set_parameter_overrides({ reasoning = "low" })

      -- Lualine should now show the overridden reasoning level
      assert.are.equal("o3 (low)", flemma_component:update_status())
    end)

    it("should reflect thinking_budget override from frontmatter", function()
      -- Start with base config: default thinking="high" → budget 32768 → "high"
      core.switch_provider("anthropic", "claude-sonnet-4-5", {})
      assert.are.equal("claude-sonnet-4-5 (high)", flemma_component:update_status())

      -- Simulate frontmatter override lowering budget
      local provider = state.get_provider()
      provider:set_parameter_overrides({ thinking_budget = 2048 })

      -- Lualine should now show the overridden thinking level (2048 maps to "low")
      assert.are.equal("claude-sonnet-4-5 (low)", flemma_component:update_status())
    end)

    it("should let frontmatter override win over base config", function()
      -- Start with base reasoning = "low"
      core.switch_provider("openai", "o3", { reasoning = "low", temperature = 1 })
      assert.are.equal("o3 (low)", flemma_component:update_status())

      -- Frontmatter sets reasoning = "high"
      local provider = state.get_provider()
      provider:set_parameter_overrides({ reasoning = "high" })

      assert.are.equal("o3 (high)", flemma_component:update_status())
    end)

    it("should revert to base config when overrides are cleared", function()
      core.switch_provider("openai", "o3", { reasoning = "low", temperature = 1 })
      local provider = state.get_provider()

      -- Set then clear overrides
      provider:set_parameter_overrides({ reasoning = "high" })
      assert.are.equal("o3 (high)", flemma_component:update_status())

      provider:set_parameter_overrides(nil)
      assert.are.equal("o3 (low)", flemma_component:update_status())
    end)
  end)
end)
