local navigation = require("flemma.navigation")

describe("Include expression navigation", function()
  before_each(function()
    package.loaded["flemma.navigation"] = nil
    package.loaded["flemma.parser"] = nil
    package.loaded["flemma.eval"] = nil
    package.loaded["flemma.context"] = nil
    package.loaded["flemma.processor"] = nil
    navigation = require("flemma.navigation")
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  it("resolves @./file reference under cursor", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    local fixture_dir = vim.fn.fnamemodify("tests/fixtures", ":p")
    vim.api.nvim_buf_set_name(bufnr, fixture_dir .. "test.chat")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "Check @./include_target.txt for details",
    })
    -- Place cursor on the file reference
    vim.api.nvim_win_set_cursor(0, { 2, 7 })

    local result = navigation.resolve_include_path(bufnr)
    assert.is_not_nil(result)
    assert.is_truthy(result:find("include_target.txt"))
  end)

  it("resolves {{ include() }} expression under cursor", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    local fixture_dir = vim.fn.fnamemodify("tests/fixtures", ":p")
    vim.api.nvim_buf_set_name(bufnr, fixture_dir .. "test.chat")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "{{ include('./include_target.txt') }}",
    })
    -- Place cursor inside the expression
    vim.api.nvim_win_set_cursor(0, { 2, 5 })

    local result = navigation.resolve_include_path(bufnr)
    assert.is_not_nil(result)
    assert.is_truthy(result:find("include_target.txt"))
  end)

  it("returns nil when cursor is on plain text", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "Just some plain text here",
    })
    vim.api.nvim_win_set_cursor(0, { 2, 5 })

    local result = navigation.resolve_include_path(bufnr)
    assert.is_nil(result)
  end)

  it("returns nil for non-include expressions", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "Result: {{ 2 + 2 }}",
    })
    vim.api.nvim_win_set_cursor(0, { 2, 12 })

    local result = navigation.resolve_include_path(bufnr)
    assert.is_nil(result)
  end)

  it("resolves include with frontmatter variable", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    local fixture_dir = vim.fn.fnamemodify("tests/fixtures", ":p")
    vim.api.nvim_buf_set_name(bufnr, fixture_dir .. "test.chat")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```lua",
      "target = './include_target.txt'",
      "```",
      "@You:",
      "{{ include(target) }}",
    })
    -- Place cursor inside the expression
    vim.api.nvim_win_set_cursor(0, { 5, 5 })

    local result = navigation.resolve_include_path(bufnr)
    assert.is_not_nil(result)
    assert.is_truthy(result:find("include_target.txt"))
  end)

  it("resolves indirect include via frontmatter variable", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    local fixture_dir = vim.fn.fnamemodify("tests/fixtures", ":p")
    vim.api.nvim_buf_set_name(bufnr, fixture_dir .. "test.chat")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```lua",
      "file = './include_target.txt'",
      "mod = include(file)",
      "```",
      "@You:",
      "See {{ mod }}",
    })
    -- Place cursor on the {{ mod }} expression
    vim.api.nvim_win_set_cursor(0, { 6, 5 })

    local result = navigation.resolve_include_path(bufnr)
    assert.is_not_nil(result)
    assert.is_truthy(result:find("include_target.txt"))
  end)

  it("resolve_include_path_expr returns a string when cursor is on plain text", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "Just text",
    })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    -- When no include expression is found, falls back to vim.v.fname
    local result = navigation.resolve_include_path_expr()
    assert.equals("string", type(result))
  end)
end)
