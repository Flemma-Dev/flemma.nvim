local stub = require("luassert.stub")

describe("Lualine component", function()
  local flemma_component

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
    package.loaded["lualine.components.flemma"] = nil

    -- Load the component to be tested
    flemma_component = require("lualine.components.flemma")

    -- Initialize flemma with default settings
    require("flemma").setup({})

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
    local flemma = require("flemma")
    flemma.switch("openai", "o1-mini", { reasoning = "high", temperature = 1 })

    -- Act
    local status = flemma_component:update_status()

    -- Assert
    assert.are.equal("o1-mini (high)", status)
  end)

  it("should display only the model name when reasoning is not set for an o-series model", function()
    -- Arrange
    local flemma = require("flemma")
    flemma.switch("openai", "o1-mini", {}) -- No reasoning parameter

    -- Act
    local status = flemma_component:update_status()

    -- Assert
    assert.are.equal("o1-mini", status)
  end)

  it("should display only the model name for non-o-series models", function()
    -- Arrange
    local flemma = require("flemma")
    flemma.switch("openai", "gpt-4o", { reasoning = "high" }) -- Reasoning should be ignored

    -- Act
    local status = flemma_component:update_status()

    -- Assert
    assert.are.equal("gpt-4o", status)
  end)

  it("should display only the model name for non-openai providers", function()
    -- Arrange
    local flemma = require("flemma")
    flemma.switch("claude", "claude-3-5-sonnet", {})

    -- Act
    local status = flemma_component:update_status()

    -- Assert
    assert.are.equal("claude-3-5-sonnet", status)
  end)

  it("should return an empty string if filetype is not 'chat'", function()
    -- Arrange
    vim.bo.filetype = "lua"
    local flemma = require("flemma")
    flemma.switch("openai", "o1-mini", { reasoning = "high" })

    -- Act
    local status = flemma_component:update_status()

    -- Assert
    assert.are.equal("", status)
  end)

  it("should return an empty string if model is not set", function()
    -- Arrange
    local flemma = require("flemma")
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
end)
