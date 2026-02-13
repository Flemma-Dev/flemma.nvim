local stub = require("luassert.stub")

describe("Lualine component", function()
  local flemma_component, flemma, core

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
    package.loaded["flemma.core"] = nil
    package.loaded["lualine.components.flemma"] = nil

    -- Load the component to be tested
    flemma_component = require("lualine.components.flemma")

    -- Initialize flemma with default settings
    flemma = require("flemma")
    core = require("flemma.core")
    flemma.setup({})

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

    -- Assert (uses default format "{model} ({level})")
    assert.are.equal("o3 (high)", status)
  end)

  it("should display only the model name when reasoning is not set for an o-series model", function()
    -- Arrange
    core.switch_provider("openai", "o4-mini", {}) -- No reasoning parameter

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

  it("should display only the model name for non-openai providers without thinking", function()
    -- Arrange
    core.switch_provider("anthropic", "claude-sonnet-4-5", {})

    -- Act
    local status = flemma_component:update_status()

    -- Assert
    assert.are.equal("claude-sonnet-4-5", status)
  end)

  it("should display model with thinking indicator for Anthropic with valid thinking_budget", function()
    -- Arrange
    core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking_budget = 2048 })

    -- Act
    local status = flemma_component:update_status()

    -- Assert
    assert.are.equal("claude-sonnet-4-5  ✓ thinking", status)
  end)

  it("should not display thinking indicator for Anthropic with thinking_budget below 1024", function()
    -- Arrange
    core.switch_provider("anthropic", "claude-sonnet-4-5", { thinking_budget = 500 })

    -- Act
    local status = flemma_component:update_status()

    -- Assert
    assert.are.equal("claude-sonnet-4-5", status)
  end)

  it("should display model with thinking indicator for Vertex with valid thinking_budget", function()
    -- Arrange
    core.switch_provider("vertex", "gemini-2.5-pro", { thinking_budget = 1000, project_id = "test-project" })

    -- Act
    local status = flemma_component:update_status()

    -- Assert
    assert.are.equal("gemini-2.5-pro  ✓ thinking", status)
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
    -- Arrange
    local s = stub.new(flemma, "get_current_model_name", function()
      return nil
    end)

    -- Act
    local status = flemma_component:update_status()

    -- Assert
    assert.are.equal("", status)

    -- Cleanup
    s:revert()
  end)

  describe("frontmatter overrides", function()
    local state = require("flemma.state")

    it("should reflect reasoning override from frontmatter", function()
      -- Start with base config: no reasoning
      core.switch_provider("openai", "o3", { temperature = 1 })
      assert.are.equal("o3", flemma_component:update_status())

      -- Simulate frontmatter override (as core.lua does during a request)
      local provider = state.get_provider()
      provider:set_parameter_overrides({ reasoning = "high" })

      -- Lualine should now show the overridden reasoning level
      assert.are.equal("o3 (high)", flemma_component:update_status())
    end)

    it("should reflect thinking_budget override from frontmatter", function()
      -- Start with base config: no thinking_budget
      core.switch_provider("anthropic", "claude-sonnet-4-5", {})
      assert.are.equal("claude-sonnet-4-5", flemma_component:update_status())

      -- Simulate frontmatter override
      local provider = state.get_provider()
      provider:set_parameter_overrides({ thinking_budget = 2048 })

      -- Lualine should now show the thinking indicator
      assert.are.equal("claude-sonnet-4-5  ✓ thinking", flemma_component:update_status())
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
