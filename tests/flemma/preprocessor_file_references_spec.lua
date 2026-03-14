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
    package.loaded["flemma.preprocessor.utilities"] = nil
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
    assert.truthy(segs[1].code:match("binary = true"))
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
    assert.truthy(segs[1].code:match("binary = true"))
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

  it("does not match email-like patterns", function()
    local doc = run_rewriter("email user@example.com here")
    local kinds = segment_kinds(doc)
    -- @example.com doesn't start with ./ or ../ so the pattern shouldn't match
    assert.equals(1, #kinds)
    assert.equals("text", kinds[1])
    assert.equals("email user@example.com here", doc.messages[1].segments[1].value)
  end)
end)
