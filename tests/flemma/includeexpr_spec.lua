local navigation = require("flemma.navigation")

describe("Include expression navigation", function()
  before_each(function()
    package.loaded["flemma.navigation"] = nil
    package.loaded["flemma.parser"] = nil
    package.loaded["flemma.templating.eval"] = nil
    package.loaded["flemma.context"] = nil
    package.loaded["flemma.processor"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.preprocessor"] = nil
    package.loaded["flemma.preprocessor.registry"] = nil
    package.loaded["flemma.preprocessor.runner"] = nil
    package.loaded["flemma.preprocessor.context"] = nil
    package.loaded["flemma.utilities.encoding"] = nil
    package.loaded["flemma.preprocessor.rewriters.file_references"] = nil
    navigation = require("flemma.navigation")
    -- Re-register the post-parse hook so @./file refs are converted to expressions
    local parser_mod = require("flemma.parser")
    local runner_mod = require("flemma.preprocessor.runner")
    local file_refs_rewriter = require("flemma.preprocessor.rewriters.file_references")
    parser_mod.set_post_parse_hook(function(doc, _bufnr)
      local result_doc = runner_mod.run_pipeline(doc, 0, {
        interactive = false,
        rewriters = { file_refs_rewriter.rewriter },
      })
      return result_doc
    end)
  end)

  after_each(function()
    local parser_mod = require("flemma.parser")
    parser_mod.set_post_parse_hook(nil)
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

  it("returns nil gracefully when frontmatter include references missing file", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    local fixture_dir = vim.fn.fnamemodify("tests/fixtures", ":p")
    vim.api.nvim_buf_set_name(bufnr, fixture_dir .. "test.chat")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```lua",
      "file = './nonexistent.txt'",
      "mod = include(file)",
      "```",
      "@You:",
      "See {{ mod }}",
    })
    -- Place cursor on the {{ mod }} expression
    vim.api.nvim_win_set_cursor(0, { 6, 5 })

    -- Should not crash — frontmatter error means variables are lost,
    -- so expression returns nil and falls back gracefully
    local result = navigation.resolve_include_path(bufnr)
    assert.is_nil(result)
  end)

  it("resolves include when frontmatter uses flemma.opt alongside user variables", function()
    -- Regression: frontmatter with flemma.opt usage must not crash navigation.
    -- The config store write proxy requires bufnr to be passed through to the
    -- frontmatter evaluator; without it, flemma.opt is a plain {} table that
    -- errors on nested access (e.g. flemma.opt.tools.max_concurrent).
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    local fixture_dir = vim.fn.fnamemodify("tests/fixtures", ":p")
    vim.api.nvim_buf_set_name(bufnr, fixture_dir .. "test.chat")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```lua",
      "flemma.opt.thinking = 'minimal'",
      "flemma.opt.tools.max_concurrent = 1",
      "file = './include_target.txt'",
      "```",
      "@System:",
      "{{ include(file) }}",
    })
    -- Place cursor inside the expression
    vim.api.nvim_win_set_cursor(0, { 7, 5 })

    local result = navigation.resolve_include_path(bufnr)
    assert.is_not_nil(result, "flemma.opt usage in frontmatter must not break include resolution")
    assert.is_truthy(result:find("include_target.txt"))
  end)

  it("resolves include for files containing literal {{ }} documentation", function()
    -- Regression: the real include() compiles file content as a template.
    -- Files like README.md that document {{ }} and {% %} syntax cause compile
    -- errors. Navigation's path-only include() must resolve the path without
    -- touching file content.
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    local fixture_dir = vim.fn.fnamemodify("tests/fixtures", ":p")
    vim.api.nvim_buf_set_name(bufnr, fixture_dir .. "test.chat")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```lua",
      "doc = './doc_with_templates.txt'",
      "```",
      "@System:",
      "{{ include(doc) }}",
    })
    vim.api.nvim_win_set_cursor(0, { 5, 5 })

    local result = navigation.resolve_include_path(bufnr)
    assert.is_not_nil(result, "include of file with literal {{ }} must resolve path without compiling content")
    assert.is_truthy(result:find("doc_with_templates.txt"))
  end)

  it("returns nil gracefully for urn:flemma: personality includes", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@System:",
      "{{ include('urn:flemma:personality:coding-assistant') }}",
    })
    vim.api.nvim_win_set_cursor(0, { 2, 5 })

    -- URN includes are virtual (rendered content, not a file) — no path to jump to
    local result = navigation.resolve_include_path(bufnr)
    assert.is_nil(result)
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
