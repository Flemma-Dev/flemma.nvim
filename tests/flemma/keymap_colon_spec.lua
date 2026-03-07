-- Force load keymaps from working directory (vim-pack-dir copy may shadow)
local project_root = os.getenv("PROJECT_ROOT")
local keymaps
if project_root then
  keymaps = dofile(project_root .. "/lua/flemma/keymaps.lua")
else
  keymaps = require("flemma.keymaps")
end

describe("insert-mode colon auto-newline", function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = "chat"
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("inserts colon and newline after @You", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You" })
    vim.api.nvim_win_set_cursor(0, { 1, 4 })
    local handled = keymaps.handle_colon_insert()
    assert.is_true(handled)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.equals("@You:", lines[1])
    assert.equals("", lines[2])
  end)

  it("returns false for non-role context", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Hello" })
    vim.api.nvim_win_set_cursor(0, { 1, 5 })
    local handled = keymaps.handle_colon_insert()
    assert.is_false(handled)
  end)

  it("returns false for invalid role", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@Foo" })
    vim.api.nvim_win_set_cursor(0, { 1, 4 })
    local handled = keymaps.handle_colon_insert()
    assert.is_false(handled)
  end)

  it("works for @System", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@System" })
    vim.api.nvim_win_set_cursor(0, { 1, 7 })
    local handled = keymaps.handle_colon_insert()
    assert.is_true(handled)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.equals("@System:", lines[1])
    assert.equals("", lines[2])
  end)

  it("works for @Assistant", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@Assistant" })
    vim.api.nvim_win_set_cursor(0, { 1, 10 })
    local handled = keymaps.handle_colon_insert()
    assert.is_true(handled)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.equals("@Assistant:", lines[1])
    assert.equals("", lines[2])
  end)

  it("does not trigger mid-line", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "text @You" })
    vim.api.nvim_win_set_cursor(0, { 1, 9 })
    local handled = keymaps.handle_colon_insert()
    assert.is_false(handled)
  end)

  it("does not trigger when cursor is not at end of line", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You more" })
    vim.api.nvim_win_set_cursor(0, { 1, 4 })
    local handled = keymaps.handle_colon_insert()
    assert.is_false(handled)
  end)
end)
