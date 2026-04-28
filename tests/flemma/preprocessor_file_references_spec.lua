--- Tests for the file-references preprocessor rewriter

local ast
local runner
local file_refs_module

describe("flemma.preprocessor.rewriters.file_references", function()
  before_each(function()
    package.loaded["flemma.preprocessor"] = nil
    package.loaded["flemma.preprocessor.registry"] = nil
    package.loaded["flemma.preprocessor.runner"] = nil
    package.loaded["flemma.preprocessor.context"] = nil
    package.loaded["flemma.utilities.encoding"] = nil
    package.loaded["flemma.preprocessor.rewriters.file_references"] = nil
    package.loaded["flemma.ast"] = nil
    package.loaded["flemma.ast.nodes"] = nil
    package.loaded["flemma.ast.query"] = nil
    package.loaded["flemma.state"] = nil
    ast = require("flemma.ast")
    runner = require("flemma.preprocessor.runner")
    file_refs_module = require("flemma.preprocessor.rewriters.file_references")
  end)

  ---Run the file-references rewriter on a single text line in a @You message.
  ---@param text string
  ---@param start_line? integer
  ---@return flemma.ast.DocumentNode
  local function run_rewriter(text, start_line)
    start_line = start_line or 2
    local doc = ast.document(nil, {
      ast.message("You", {
        ast.text(text, { start_line = start_line, end_line = start_line }),
      }, { start_line = start_line - 1, end_line = start_line }),
    }, {}, { start_line = 1, end_line = start_line })

    return runner.run_pipeline(doc, 0, {
      interactive = false,
      rewriters = { file_refs_module.rewriter },
    })
  end

  ---Collect segment kinds from the first message.
  ---@param doc flemma.ast.DocumentNode
  ---@return string[]
  local function segment_kinds(doc)
    local kinds = {}
    for _, seg in ipairs(doc.messages[1].segments) do
      kinds[#kinds + 1] = seg.kind
    end
    return kinds
  end

  it("converts @./file to include() expression", function()
    local doc = run_rewriter("@./readme.md")
    local segs = doc.messages[1].segments
    assert.equals(1, #segs)
    assert.equals("expression", segs[1].kind)
    assert.truthy(segs[1].code:match("include%('%.%/readme%.md'"))
    assert.truthy(segs[1].code:match("%[symbols%.BINARY%] = true"))
  end)

  it("converts @../file to include() expression", function()
    local doc = run_rewriter("@../parent.txt")
    local segs = doc.messages[1].segments
    assert.equals(1, #segs)
    assert.equals("expression", segs[1].kind)
    assert.truthy(segs[1].code:match("include%('%.%.%/parent%.txt'"))
  end)

  it("preserves text before and after file reference", function()
    local doc = run_rewriter("Check @./file.txt here")
    local kinds = segment_kinds(doc)
    -- Expected: text("Check "), expression(include), text(" here")
    assert.equals("text", kinds[1])
    assert.equals("expression", kinds[2])
    assert.equals("text", kinds[3])
    assert.equals("Check ", doc.messages[1].segments[1].value)
    assert.equals(" here", doc.messages[1].segments[3].value)
  end)

  it("strips trailing punctuation", function()
    local doc = run_rewriter("See @./file.txt, then continue")
    local segs = doc.messages[1].segments
    -- Expected: text("See "), expression(include), text(","), text(" then continue")
    local expr_seg = nil
    for _, seg in ipairs(segs) do
      if seg.kind == "expression" then
        expr_seg = seg
        break
      end
    end
    assert.is_not_nil(expr_seg)
    -- The path in include() should not have a trailing comma
    local path_in_code = expr_seg.code:match("include%('([^']+)'")
    assert.is_not_nil(path_in_code)
    assert.is_nil(path_in_code:find(","), "Trailing comma should not be in file path")
  end)

  it("handles URL-encoded paths", function()
    local doc = run_rewriter("@./my%20file.txt")
    local segs = doc.messages[1].segments
    assert.equals(1, #segs)
    assert.equals("expression", segs[1].kind)
    assert.truthy(segs[1].code:match("my file%.txt"))
  end)

  it("handles ;type= MIME override", function()
    local doc = run_rewriter("@./image.bin;type=image/png")
    local segs = doc.messages[1].segments
    assert.equals(1, #segs)
    assert.equals("expression", segs[1].kind)
    assert.truthy(segs[1].code:match("%[symbols%.BINARY%] = true"))
    assert.truthy(segs[1].code:match("image/png"))
  end)

  it("strips trailing punctuation from MIME", function()
    local doc = run_rewriter("See @./image.bin;type=image/png!")
    local segs = doc.messages[1].segments
    -- Should have expression + trailing "!"
    local has_expression = false
    local has_trailing = false
    for _, seg in ipairs(segs) do
      if seg.kind == "expression" then
        has_expression = true
        assert.truthy(seg.code:match("image/png"))
      end
      if seg.kind == "text" and seg.value == "!" then
        has_trailing = true
      end
    end
    assert.is_true(has_expression)
    assert.is_true(has_trailing)
  end)

  it("multiple file references on one line", function()
    local doc = run_rewriter("@./a.txt and @./b.txt")
    local kinds = segment_kinds(doc)
    -- Expected: expression(include(a)), text(" and "), expression(include(b))
    assert.equals("expression", kinds[1])
    assert.equals("text", kinds[2])
    assert.equals("expression", kinds[3])
  end)

  it("escapes single quotes in paths", function()
    local doc = run_rewriter("@./it's.txt")
    local segs = doc.messages[1].segments
    local expr_seg = nil
    for _, seg in ipairs(segs) do
      if seg.kind == "expression" then
        expr_seg = seg
        break
      end
    end
    assert.is_not_nil(expr_seg)
    -- The single quote should be escaped in the include() call
    assert.truthy(expr_seg.code:match("\\'"))
  end)

  it("does not process @./file in Assistant messages", function()
    local doc = ast.document(nil, {
      ast.message("Assistant", {
        ast.text("See @./readme.md for details", { start_line = 2, end_line = 2 }),
      }, { start_line = 1, end_line = 2 }),
    }, {}, { start_line = 1, end_line = 2 })

    local result = runner.run_pipeline(doc, 0, {
      interactive = false,
      rewriters = { file_refs_module.rewriter },
    })

    local segs = result.messages[1].segments
    -- All segments should be text — no expression from file reference
    for _, seg in ipairs(segs) do
      assert.equals("text", seg.kind, "expected no expression segments in Assistant message")
    end
    -- Original text should be preserved
    local full_text = ""
    for _, seg in ipairs(segs) do
      full_text = full_text .. seg.value
    end
    assert.equals("See @./readme.md for details", full_text)
  end)

  it("still processes @./file in System messages", function()
    local doc = ast.document(nil, {
      ast.message("System", {
        ast.text("@./readme.md", { start_line = 2, end_line = 2 }),
      }, { start_line = 1, end_line = 2 }),
    }, {}, { start_line = 1, end_line = 2 })

    local result = runner.run_pipeline(doc, 0, {
      interactive = false,
      rewriters = { file_refs_module.rewriter },
    })

    local segs = result.messages[1].segments
    local has_expression = false
    for _, seg in ipairs(segs) do
      if seg.kind == "expression" then
        has_expression = true
      end
    end
    assert.is_true(has_expression, "System messages should still have file references processed")
  end)

  -- @~/ file reference tests

  it("converts @~/file to include() expression", function()
    local doc = run_rewriter("@~/Downloads/file.pdf")
    local segs = doc.messages[1].segments
    assert.equals(1, #segs)
    assert.equals("expression", segs[1].kind)
    assert.truthy(segs[1].code:match("include%('~/Downloads/file%.pdf'"))
    assert.truthy(segs[1].code:match("%[symbols%.BINARY%] = true"))
  end)

  it("converts @~/file with ;type= MIME override", function()
    local doc = run_rewriter("@~/Pictures/photo.bin;type=image/png")
    local segs = doc.messages[1].segments
    assert.equals(1, #segs)
    assert.equals("expression", segs[1].kind)
    assert.truthy(segs[1].code:match("%[symbols%.BINARY%] = true"))
    assert.truthy(segs[1].code:match("image/png"))
  end)

  it("strips trailing punctuation from @~/file", function()
    local doc = run_rewriter("See @~/file.txt, then continue")
    local segs = doc.messages[1].segments
    local expr_seg = nil
    for _, seg in ipairs(segs) do
      if seg.kind == "expression" then
        expr_seg = seg
        break
      end
    end
    assert.is_not_nil(expr_seg)
    local path_in_code = expr_seg.code:match("include%('([^']+)'")
    assert.is_not_nil(path_in_code)
    assert.is_nil(path_in_code:find(","), "Trailing comma should not be in file path")
  end)

  it("does not process @~/file in Assistant messages", function()
    local doc = ast.document(nil, {
      ast.message("Assistant", {
        ast.text("See @~/Downloads/readme.md for details", { start_line = 2, end_line = 2 }),
      }, { start_line = 1, end_line = 2 }),
    }, {}, { start_line = 1, end_line = 2 })

    local result = runner.run_pipeline(doc, 0, {
      interactive = false,
      rewriters = { file_refs_module.rewriter },
    })

    local segs = result.messages[1].segments
    for _, seg in ipairs(segs) do
      assert.equals("text", seg.kind, "expected no expression segments in Assistant message")
    end
    local full_text = ""
    for _, seg in ipairs(segs) do
      full_text = full_text .. seg.value
    end
    assert.equals("See @~/Downloads/readme.md for details", full_text)
  end)

  it("does not match email-like patterns", function()
    local doc = run_rewriter("email user@example.com here")
    local kinds = segment_kinds(doc)
    -- @example.com doesn't start with ./ or ../ so the pattern shouldn't match
    assert.equals(1, #kinds)
    assert.equals("text", kinds[1])
    assert.equals("email user@example.com here", doc.messages[1].segments[1].value)
  end)
end)

describe("end-to-end pipeline integration", function()
  local parser_mod, preprocessor_mod, state_mod

  before_each(function()
    package.loaded["flemma.parser"] = nil
    package.loaded["flemma.processor"] = nil
    package.loaded["flemma.preprocessor"] = nil
    package.loaded["flemma.preprocessor.registry"] = nil
    package.loaded["flemma.preprocessor.runner"] = nil
    package.loaded["flemma.preprocessor.context"] = nil
    package.loaded["flemma.preprocessor.rewriters.file_references"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.context"] = nil

    preprocessor_mod = require("flemma.preprocessor")
    parser_mod = require("flemma.parser")
    state_mod = require("flemma.state")

    -- Set up preprocessor hook (simulates what flemma.setup() does)
    preprocessor_mod.setup()
  end)

  after_each(function()
    parser_mod.set_post_parse_hook(nil)
  end)

  it("file references are resolved through the full pipeline via get_parsed_document", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.getcwd() .. "/test_integration.chat")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "Check @./tests/fixtures/a.txt please",
    })

    -- get_parsed_document runs through the post-parse hook (non-interactive preprocessor)
    local doc = parser_mod.get_parsed_document(bufnr)

    -- The rewritten AST should have an ExpressionSegment for the file ref
    local segments = doc.messages[1].segments
    local has_expression = false
    for _, seg in ipairs(segments) do
      if seg.kind == "expression" and seg.code:match("^include%(") then
        has_expression = true
      end
    end
    assert.is_true(has_expression, "get_parsed_document should return rewritten AST with include() expression")

    state_mod.cleanup_buffer_state(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("raw document does not contain file reference expressions", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.getcwd() .. "/test_raw.chat")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "@./tests/fixtures/a.txt",
    })

    -- Populate both caches
    parser_mod.get_parsed_document(bufnr)

    -- Raw document should have plain text (no expression from file ref)
    local raw = parser_mod.get_raw_document(bufnr)
    local segments = raw.messages[1].segments
    assert.equals("text", segments[1].kind)
    assert.truthy(segments[1].value:match("@%./tests/fixtures/a%.txt"))

    state_mod.cleanup_buffer_state(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
