--- Tests for flemma.preprocessor.runner — pipeline execution engine

local preprocessor
local registry
local runner
local ast

describe("flemma.preprocessor.runner", function()
  before_each(function()
    package.loaded["flemma.preprocessor"] = nil
    package.loaded["flemma.preprocessor.registry"] = nil
    package.loaded["flemma.preprocessor.runner"] = nil
    package.loaded["flemma.preprocessor.context"] = nil
    package.loaded["flemma.preprocessor.utilities"] = nil
    package.loaded["flemma.ast"] = nil
    package.loaded["flemma.ast.nodes"] = nil
    package.loaded["flemma.ast.query"] = nil
    package.loaded["flemma.state"] = nil
    preprocessor = require("flemma.preprocessor")
    registry = require("flemma.preprocessor.registry")
    runner = require("flemma.preprocessor.runner")
    ast = require("flemma.ast")
    registry.clear()
  end)

  ---Build a minimal document with a single user message containing the given segments.
  ---@param segments table[]
  ---@return flemma.ast.DocumentNode
  local function make_doc(segments)
    return ast.document(nil, {
      ast.message("You", segments, { start_line = 1, end_line = 10 }),
    }, {}, { start_line = 1, end_line = 10 })
  end

  ---Build RunOpts with a set of rewriters.
  ---@param rewriters table[]
  ---@param interactive? boolean
  ---@return flemma.preprocessor.RunOpts
  local function make_opts(rewriters, interactive)
    return {
      interactive = interactive or false,
      rewriters = rewriters,
    }
  end

  describe("text handler line scanning", function()
    it("simple match produces an expression emission", function()
      local rewriter = preprocessor.create_rewriter("date_macro")
      rewriter:on_text("{{DATE}}", function(_match, ctx)
        return ctx:expression("os.date('%Y-%m-%d')")
      end)

      local doc = make_doc({
        ast.text("Today is {{DATE}} ok", { start_line = 2 }),
      })

      local result_doc, diagnostics = runner.run_pipeline(doc, nil, make_opts({ rewriter }))
      assert.equals(0, #diagnostics)

      local segments = result_doc.messages[1].segments
      -- Expected: text("Today is "), expression("os.date('%Y-%m-%d')"), text(" ok")
      assert.equals(3, #segments)
      assert.equals("text", segments[1].kind)
      assert.equals("Today is ", segments[1].value)
      assert.equals("expression", segments[2].kind)
      assert.equals("os.date('%Y-%m-%d')", segments[2].code)
      assert.equals("text", segments[3].kind)
      assert.equals(" ok", segments[3].value)
    end)

    it("multiple matches on one line", function()
      local rewriter = preprocessor.create_rewriter("multi_match")
      rewriter:on_text("%((%w+)%)", function(match, ctx)
        return ctx:expression("var_" .. match.captures[1])
      end)

      local doc = make_doc({
        ast.text("a (foo) b (bar) c", { start_line = 1 }),
      })

      local result_doc, diagnostics = runner.run_pipeline(doc, nil, make_opts({ rewriter }))
      assert.equals(0, #diagnostics)

      local segments = result_doc.messages[1].segments
      -- Expected: text("a "), expr("var_foo"), text(" b "), expr("var_bar"), text(" c")
      assert.equals(5, #segments)
      assert.equals("text", segments[1].kind)
      assert.equals("a ", segments[1].value)
      assert.equals("expression", segments[2].kind)
      assert.equals("var_foo", segments[2].code)
      assert.equals("text", segments[3].kind)
      assert.equals(" b ", segments[3].value)
      assert.equals("expression", segments[4].kind)
      assert.equals("var_bar", segments[4].code)
      assert.equals("text", segments[5].kind)
      assert.equals(" c", segments[5].value)
    end)

    it("unmatched text passes through unchanged", function()
      local rewriter = preprocessor.create_rewriter("no_match")
      rewriter:on_text("WONTMATCH", function(_, ctx)
        return ctx:expression("nope")
      end)

      local doc = make_doc({
        ast.text("plain text here", { start_line = 1 }),
      })

      local result_doc, diagnostics = runner.run_pipeline(doc, nil, make_opts({ rewriter }))
      assert.equals(0, #diagnostics)

      local segments = result_doc.messages[1].segments
      assert.equals(1, #segments)
      assert.equals("text", segments[1].kind)
      assert.equals("plain text here", segments[1].value)
    end)

    it("ctx:remove() deletes matched text", function()
      local rewriter = preprocessor.create_rewriter("remover")
      rewriter:on_text("%[DRAFT%]", function(_, ctx)
        return ctx:remove()
      end)

      local doc = make_doc({
        ast.text("hello [DRAFT] world", { start_line = 1 }),
      })

      local result_doc, diagnostics = runner.run_pipeline(doc, nil, make_opts({ rewriter }))
      assert.equals(0, #diagnostics)

      local segments = result_doc.messages[1].segments
      -- Expected: text("hello "), text(" world") — [DRAFT] removed
      assert.equals(2, #segments)
      assert.equals("text", segments[1].kind)
      assert.equals("hello ", segments[1].value)
      assert.equals("text", segments[2].kind)
      assert.equals(" world", segments[2].value)
    end)

    it("multi-line TextSegments are processed line by line", function()
      local rewriter = preprocessor.create_rewriter("multiline")
      rewriter:on_text("TODO", function(_, ctx)
        return ctx:expression("'DONE'")
      end)

      local doc = make_doc({
        ast.text("line1 TODO\nline2\nline3 TODO end", { start_line = 5 }),
      })

      local result_doc, diagnostics = runner.run_pipeline(doc, nil, make_opts({ rewriter }))
      assert.equals(0, #diagnostics)

      local segments = result_doc.messages[1].segments
      -- line1: text("line1 "), expr("'DONE'"), newline
      -- line2: text("line2"), newline
      -- line3: text("line3 "), expr("'DONE'"), text(" end")
      -- Count: 3 + 2 + 3 = 8
      assert.equals(8, #segments)

      -- Line 1
      assert.equals("text", segments[1].kind)
      assert.equals("line1 ", segments[1].value)
      assert.equals("expression", segments[2].kind)
      assert.equals("'DONE'", segments[2].code)
      assert.equals("text", segments[3].kind)
      assert.equals("\n", segments[3].value)

      -- Line 2
      assert.equals("text", segments[4].kind)
      assert.equals("line2", segments[4].value)
      assert.equals("text", segments[5].kind)
      assert.equals("\n", segments[5].value)

      -- Line 3
      assert.equals("text", segments[6].kind)
      assert.equals("line3 ", segments[6].value)
      assert.equals("expression", segments[7].kind)
      assert.equals("'DONE'", segments[7].code)
      assert.equals("text", segments[8].kind)
      assert.equals(" end", segments[8].value)
    end)

    it("handler returning nil keeps original text", function()
      local rewriter = preprocessor.create_rewriter("nil_return")
      rewriter:on_text("KEEP", function()
        return nil
      end)

      local doc = make_doc({
        ast.text("before KEEP after", { start_line = 1 }),
      })

      local result_doc, diagnostics = runner.run_pipeline(doc, nil, make_opts({ rewriter }))
      assert.equals(0, #diagnostics)

      local segments = result_doc.messages[1].segments
      -- Expected: text("before "), text("KEEP"), text(" after")
      assert.equals(3, #segments)
      assert.equals("text", segments[1].kind)
      assert.equals("before ", segments[1].value)
      assert.equals("text", segments[2].kind)
      assert.equals("KEEP", segments[2].value)
      assert.equals("text", segments[3].kind)
      assert.equals(" after", segments[3].value)
    end)

    it("handler returning an emission list produces multiple segments", function()
      local rewriter = preprocessor.create_rewriter("list_return")
      rewriter:on_text("MACRO", function(_, ctx)
        return {
          ctx:text("prefix-"),
          ctx:expression("dynamic()"),
          ctx:text("-suffix"),
        }
      end)

      local doc = make_doc({
        ast.text("before MACRO after", { start_line = 1 }),
      })

      local result_doc, diagnostics = runner.run_pipeline(doc, nil, make_opts({ rewriter }))
      assert.equals(0, #diagnostics)

      local segments = result_doc.messages[1].segments
      -- Expected: text("before "), text("prefix-"), expr("dynamic()"), text("-suffix"), text(" after")
      assert.equals(5, #segments)
      assert.equals("text", segments[1].kind)
      assert.equals("before ", segments[1].value)
      assert.equals("text", segments[2].kind)
      assert.equals("prefix-", segments[2].value)
      assert.equals("expression", segments[3].kind)
      assert.equals("dynamic()", segments[3].code)
      assert.equals("text", segments[4].kind)
      assert.equals("-suffix", segments[4].value)
      assert.equals("text", segments[5].kind)
      assert.equals(" after", segments[5].value)
    end)

    it("non-text segments pass through text handlers unchanged", function()
      local rewriter = preprocessor.create_rewriter("skip_non_text")
      rewriter:on_text("anything", function(_, ctx)
        return ctx:remove()
      end)

      local expr_segment = ast.expression("1 + 1", { start_line = 1 })
      local doc = make_doc({ expr_segment })

      local result_doc, diagnostics = runner.run_pipeline(doc, nil, make_opts({ rewriter }))
      assert.equals(0, #diagnostics)

      local segments = result_doc.messages[1].segments
      assert.equals(1, #segments)
      assert.equals("expression", segments[1].kind)
      assert.equals("1 + 1", segments[1].code)
    end)
  end)

  describe("segment handlers (Phase 2)", function()
    it("on(kind) handler transforms expression segments", function()
      local rewriter = preprocessor.create_rewriter("expr_handler")
      rewriter:on("expression", function(segment, ctx)
        return ctx:expression("wrapped(" .. segment.code .. ")")
      end)

      local doc = make_doc({
        ast.expression("original()", { start_line = 1 }),
      })

      local result_doc, diagnostics = runner.run_pipeline(doc, nil, make_opts({ rewriter }))
      assert.equals(0, #diagnostics)

      local segments = result_doc.messages[1].segments
      assert.equals(1, #segments)
      assert.equals("expression", segments[1].kind)
      assert.equals("wrapped(original())", segments[1].code)
    end)

    it("on_text output feeds into on(kind) within same rewriter", function()
      local rewriter = preprocessor.create_rewriter("combined")
      -- Phase 1: text handler produces an expression
      rewriter:on_text("EVAL%((.-)%)", function(match, ctx)
        return ctx:expression(match.captures[1])
      end)
      -- Phase 2: expression handler wraps it
      rewriter:on("expression", function(segment, ctx)
        return ctx:expression("safe(" .. segment.code .. ")")
      end)

      local doc = make_doc({
        ast.text("result: EVAL(foo.bar)", { start_line = 1 }),
      })

      local result_doc, diagnostics = runner.run_pipeline(doc, nil, make_opts({ rewriter }))
      assert.equals(0, #diagnostics)

      local segments = result_doc.messages[1].segments
      assert.equals(2, #segments)
      assert.equals("text", segments[1].kind)
      assert.equals("result: ", segments[1].value)
      assert.equals("expression", segments[2].kind)
      assert.equals("safe(foo.bar)", segments[2].code)
    end)

    it("segment handler returning nil keeps segment unchanged", function()
      local rewriter = preprocessor.create_rewriter("seg_nil")
      rewriter:on("expression", function()
        return nil
      end)

      local doc = make_doc({
        ast.expression("keep_me()", { start_line = 1 }),
      })

      local result_doc, diagnostics = runner.run_pipeline(doc, nil, make_opts({ rewriter }))
      assert.equals(0, #diagnostics)

      local segments = result_doc.messages[1].segments
      assert.equals(1, #segments)
      assert.equals("expression", segments[1].kind)
      assert.equals("keep_me()", segments[1].code)
    end)
  end)

  describe("multi-rewriter ordering", function()
    it("runs rewriters in priority order, later sees output of earlier", function()
      local rewriter1 = preprocessor.create_rewriter("first", { priority = 100 })
      rewriter1:on_text("AAA", function(_, ctx)
        return ctx:text("BBB")
      end)

      local rewriter2 = preprocessor.create_rewriter("second", { priority = 200 })
      rewriter2:on_text("BBB", function(_, ctx)
        return ctx:text("CCC")
      end)

      local doc = make_doc({
        ast.text("start AAA end", { start_line = 1 }),
      })

      local result_doc, diagnostics = runner.run_pipeline(
        doc,
        nil,
        make_opts({ rewriter1, rewriter2 })
      )
      assert.equals(0, #diagnostics)

      local segments = result_doc.messages[1].segments
      -- rewriter1 transforms AAA -> BBB, then rewriter2 transforms BBB -> CCC
      -- Find the segment with CCC
      local found_ccc = false
      for _, seg in ipairs(segments) do
        if seg.kind == "text" and seg.value == "CCC" then
          found_ccc = true
        end
      end
      assert.is_true(found_ccc)
    end)
  end)

  describe("error handling", function()
    it("catches handler errors and records diagnostics", function()
      local rewriter = preprocessor.create_rewriter("error_handler")
      rewriter:on_text("BOOM", function()
        error("handler exploded")
      end)

      local doc = make_doc({
        ast.text("before BOOM after", { start_line = 1 }),
      })

      local result_doc, diagnostics = runner.run_pipeline(doc, nil, make_opts({ rewriter }))
      assert.equals(1, #diagnostics)
      assert.truthy(diagnostics[1].message:find("handler error"))
      assert.truthy(diagnostics[1].message:find("handler exploded"))

      -- Original text should be preserved
      local segments = result_doc.messages[1].segments
      local full_text = ""
      for _, seg in ipairs(segments) do
        if seg.kind == "text" then
          full_text = full_text .. seg.value
        end
      end
      assert.equals("before BOOM after", full_text)
    end)

    it("catches segment handler errors and records diagnostics", function()
      local rewriter = preprocessor.create_rewriter("seg_error")
      rewriter:on("expression", function()
        error("segment handler blew up")
      end)

      local doc = make_doc({
        ast.expression("some_code()", { start_line = 1 }),
      })

      local result_doc, diagnostics = runner.run_pipeline(doc, nil, make_opts({ rewriter }))
      assert.equals(1, #diagnostics)
      assert.truthy(diagnostics[1].message:find("segment handler error"))

      -- Original segment preserved
      local segments = result_doc.messages[1].segments
      assert.equals(1, #segments)
      assert.equals("expression", segments[1].kind)
      assert.equals("some_code()", segments[1].code)
    end)
  end)

  describe("position derivation", function()
    it("generated segments inherit match position", function()
      local rewriter = preprocessor.create_rewriter("pos_check")
      rewriter:on_text("MARKER", function(_, ctx)
        return ctx:expression("replaced()")
      end)

      local doc = make_doc({
        ast.text("pre MARKER post", { start_line = 5, start_col = 1 }),
      })

      local result_doc = runner.run_pipeline(doc, nil, make_opts({ rewriter }))

      local segments = result_doc.messages[1].segments
      -- The expression segment should have the match position
      local expr_seg = nil
      for _, seg in ipairs(segments) do
        if seg.kind == "expression" then
          expr_seg = seg
          break
        end
      end
      assert.is_not_nil(expr_seg)
      assert.equals(5, expr_seg.position.start_line)
      assert.equals(5, expr_seg.position.start_col)
    end)
  end)

  describe("system accessor mutations", function()
    it("applies system prepends and appends to the document", function()
      local rewriter = preprocessor.create_rewriter("sys_mutator")
      rewriter:on_text("TRIGGER", function(_, ctx)
        ctx.system:prepend(ctx:text("PREPENDED\n"))
        ctx.system:append(ctx:text("\nAPPENDED"))
        return ctx:remove()
      end)

      local doc = ast.document(nil, {
        ast.message("System", {
          ast.text("existing system text", { start_line = 2 }),
        }, { start_line = 1, end_line = 3 }),
        ast.message("You", {
          ast.text("hello TRIGGER world", { start_line = 5 }),
        }, { start_line = 4, end_line = 6 }),
      }, {}, { start_line = 1, end_line = 6 })

      local result_doc, diagnostics = runner.run_pipeline(doc, nil, make_opts({ rewriter }))
      assert.equals(0, #diagnostics)

      -- System message should have prepended and appended segments
      local sys_segments = result_doc.messages[1].segments
      assert.is_true(#sys_segments >= 3)

      -- First segment should be the prepended text
      assert.equals("text", sys_segments[1].kind)
      assert.equals("PREPENDED\n", sys_segments[1].value)

      -- Last segment should be the appended text
      assert.equals("text", sys_segments[#sys_segments].kind)
      assert.equals("\nAPPENDED", sys_segments[#sys_segments].value)
    end)

    it("creates a @System message if none exists", function()
      local rewriter = preprocessor.create_rewriter("sys_creator")
      rewriter:on_text("INJECT", function(_, ctx)
        ctx.system:append(ctx:text("injected system content"))
        return ctx:remove()
      end)

      local doc = ast.document(nil, {
        ast.message("You", {
          ast.text("hello INJECT world", { start_line = 1 }),
        }, { start_line = 1, end_line = 2 }),
      }, {}, { start_line = 1, end_line = 2 })

      local result_doc = runner.run_pipeline(doc, nil, make_opts({ rewriter }))

      -- Should now have 2 messages: System (created) + You
      assert.equals(2, #result_doc.messages)
      assert.equals("System", result_doc.messages[1].role)
      assert.equals(1, #result_doc.messages[1].segments)
      assert.equals("injected system content", result_doc.messages[1].segments[1].value)
    end)
  end)

  describe("frontmatter mutations", function()
    it("applies frontmatter set/append/remove mutations", function()
      local rewriter = preprocessor.create_rewriter("fm_mutator")
      rewriter:on_text("FMTRIGGER", function(_, ctx)
        ctx.frontmatter:set("model", "gpt-4")
        ctx.frontmatter:append("temperature: 0.7")
        ctx.frontmatter:remove("old_key")
        return ctx:remove()
      end)

      local doc = ast.document(
        ast.frontmatter("yaml", "old_key: old_value\nother: data", { start_line = 1, end_line = 3 }),
        {
          ast.message("You", {
            ast.text("hello FMTRIGGER world", { start_line = 5 }),
          }, { start_line = 4, end_line = 6 }),
        },
        {},
        { start_line = 1, end_line = 6 }
      )

      local result_doc = runner.run_pipeline(doc, nil, make_opts({ rewriter }))

      assert.is_not_nil(result_doc.frontmatter)
      local fm_code = result_doc.frontmatter.code
      -- old_key should be removed
      assert.is_nil(fm_code:match("old_key"))
      -- model should be set
      assert.truthy(fm_code:match("model: gpt%-4"))
      -- temperature should be appended
      assert.truthy(fm_code:match("temperature: 0%.7"))
      -- other should remain
      assert.truthy(fm_code:match("other: data"))
    end)

    it("creates frontmatter if none exists", function()
      local rewriter = preprocessor.create_rewriter("fm_creator")
      rewriter:on_text("NEED_FM", function(_, ctx)
        ctx.frontmatter:set("model", "claude")
        return ctx:remove()
      end)

      local doc = ast.document(nil, {
        ast.message("You", {
          ast.text("NEED_FM", { start_line = 1 }),
        }, { start_line = 1, end_line = 2 }),
      }, {}, { start_line = 1, end_line = 2 })

      local result_doc = runner.run_pipeline(doc, nil, make_opts({ rewriter }))

      assert.is_not_nil(result_doc.frontmatter)
      assert.truthy(result_doc.frontmatter.code:match("model: claude"))
    end)
  end)
end)
