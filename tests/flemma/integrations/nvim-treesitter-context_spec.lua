package.loaded["flemma.integrations.nvim-treesitter-context"] = nil

local integration

local function make_buffer(filetype)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].filetype = filetype
  return bufnr
end

describe("flemma.integrations.nvim-treesitter-context", function()
  before_each(function()
    package.loaded["flemma.integrations.nvim-treesitter-context"] = nil
    integration = require("flemma.integrations.nvim-treesitter-context")
  end)

  describe("on_attach()", function()
    it("returns false for chat buffers", function()
      local bufnr = make_buffer("chat")
      assert.is_false(integration.on_attach(bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("returns true for non-chat filetypes", function()
      for _, ft in ipairs({ "markdown", "lua", "" }) do
        local bufnr = make_buffer(ft)
        assert.is_true(integration.on_attach(bufnr))
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)
  end)

  describe("wrap()", function()
    it("returns false for chat buffers without invoking the wrapped callback", function()
      local calls = 0
      local wrapped = integration.wrap(function()
        calls = calls + 1
        return true
      end)
      local bufnr = make_buffer("chat")
      assert.is_false(wrapped(bufnr))
      assert.are.equal(0, calls)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("delegates to the wrapped callback for non-chat buffers", function()
      local wrapped_false = integration.wrap(function()
        return false
      end)
      local wrapped_true = integration.wrap(function()
        return true
      end)
      local bufnr = make_buffer("markdown")
      assert.is_false(wrapped_false(bufnr))
      assert.is_true(wrapped_true(bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("treats a wrapped callback returning nil as true", function()
      local wrapped = integration.wrap(function()
        return nil
      end)
      local bufnr = make_buffer("markdown")
      assert.is_true(wrapped(bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
