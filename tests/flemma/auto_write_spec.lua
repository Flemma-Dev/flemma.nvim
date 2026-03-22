--- Tests for editing.auto_write

local editing = require("flemma.buffer.editing")

describe("editing.auto_write", function()
  local test_dir
  local test_file

  before_each(function()
    test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")
    test_file = test_dir .. "/test.txt"
    vim.fn.writefile({ "original" }, test_file)

    require("flemma").setup({ editing = { auto_write = true, auto_prompt = false } })
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
    if test_dir then
      vim.fn.delete(test_dir, "rf")
    end
  end)

  it("writes a modified buffer to disk", function()
    vim.cmd("noautocmd edit " .. vim.fn.fnameescape(test_file))
    local bufnr = vim.api.nvim_get_current_buf()

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "modified" })
    assert.is_true(vim.bo[bufnr].modified)

    editing.auto_write(bufnr)

    assert.are.same({ "modified" }, vim.fn.readfile(test_file))
    assert.is_false(vim.bo[bufnr].modified)
  end)

  it("succeeds when file was externally modified on disk", function()
    vim.cmd("noautocmd edit " .. vim.fn.fnameescape(test_file))
    local bufnr = vim.api.nvim_get_current_buf()

    -- Buffer gets new content (simulates streaming response)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "buffer content" })

    -- External tool modifies the file on disk
    vim.fn.writefile({ "external content" }, test_file)

    -- Must not throw
    assert.has_no_errors(function()
      editing.auto_write(bufnr)
    end)

    -- Buffer content wins (write! overrides the file-changed check)
    assert.are.same({ "buffer content" }, vim.fn.readfile(test_file))
    assert.is_false(vim.bo[bufnr].modified)
  end)

  it("skips write when auto_write config is false", function()
    require("flemma").setup({ editing = { auto_write = false, auto_prompt = false } })

    vim.cmd("noautocmd edit " .. vim.fn.fnameescape(test_file))
    local bufnr = vim.api.nvim_get_current_buf()

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "modified" })

    editing.auto_write(bufnr)

    assert.are.same({ "original" }, vim.fn.readfile(test_file))
    assert.is_true(vim.bo[bufnr].modified)
  end)

  it("skips write when buffer is not modified", function()
    vim.cmd("noautocmd edit " .. vim.fn.fnameescape(test_file))
    local bufnr = vim.api.nvim_get_current_buf()

    editing.auto_write(bufnr)

    assert.are.same({ "original" }, vim.fn.readfile(test_file))
  end)

  it("does not throw for an invalid buffer", function()
    assert.has_no_errors(function()
      editing.auto_write(99999)
    end)
  end)
end)
