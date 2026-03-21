--- Tests for editing.auto_prompt

local editing = require("flemma.buffer.editing")

describe("editing.auto_prompt", function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    require("flemma").setup({ editing = { auto_prompt = true } })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("prepends @You: and empty line to an empty buffer", function()
    editing.auto_prompt(bufnr)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({ "@You:", "" }, lines)
  end)

  it("places cursor on line 2", function()
    vim.api.nvim_set_current_buf(bufnr)

    editing.auto_prompt(bufnr)

    local cursor = vim.api.nvim_win_get_cursor(0)
    assert.are.equal(2, cursor[1])
    assert.are.equal(0, cursor[2])
  end)

  it("prepends to a whitespace-only buffer", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "  ", "\t", "", "   " })

    editing.auto_prompt(bufnr)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({ "@You:", "" }, lines)
  end)

  it("does not modify a buffer with content", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@System:", "You are helpful." })

    editing.auto_prompt(bufnr)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({ "@System:", "You are helpful." }, lines)
  end)

  it("does not modify a buffer with a role marker", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "Hello" })

    editing.auto_prompt(bufnr)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({ "@You:", "Hello" }, lines)
  end)

  it("does nothing when auto_prompt is disabled", function()
    require("flemma").setup({ editing = { auto_prompt = false } })

    editing.auto_prompt(bufnr)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.same({ "" }, lines)
  end)
end)
