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

      local result_doc, diagnostics = runner.run_pipeline(doc, nil, make_opts({ rewriter1, rewriter2 }))
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

  describe("segment handlers — extended (Phase 2)", function()
    it("on(text) handler processes text segments produced by on_text", function()
      local rewriter = preprocessor.create_rewriter("text_phase2")
      -- Phase 1: text handler produces a text emission with different content
      rewriter:on_text("OLD", function(_, ctx)
        return ctx:text("NEW")
      end)
      -- Phase 2: text segment handler wraps all text segments
      rewriter:on("text", function(segment, ctx)
        return ctx:text("[" .. segment.value .. "]")
      end)

      local doc = make_doc({
        ast.text("x OLD y", { start_line = 1 }),
      })

      local result_doc, diagnostics = runner.run_pipeline(doc, nil, make_opts({ rewriter }))
      assert.equals(0, #diagnostics)

      -- Phase 1 produces: text("x "), text("NEW"), text(" y")
      -- Phase 2 wraps each text segment: text("[x ]"), text("[NEW]"), text("[  y]")
      -- (note: actual text depends on Phase 1 output)
      local segments = result_doc.messages[1].segments
      for _, seg in ipairs(segments) do
        if seg.kind == "text" then
          assert.truthy(seg.value:match("^%[.+%]$"), "expected text wrapped in brackets: " .. seg.value)
        end
      end
    end)

    it("on(kind) handler does not match segments of other kinds", function()
      local rewriter = preprocessor.create_rewriter("kind_filter")
      local call_count = 0
      rewriter:on("expression", function(_, ctx)
        call_count = call_count + 1
        return ctx:expression("handled")
      end)

      local doc = make_doc({
        ast.text("just text", { start_line = 1 }),
      })

      runner.run_pipeline(doc, nil, make_opts({ rewriter }))
      assert.equals(0, call_count)
    end)
  end)

  describe("multi-rewriter ordering — extended", function()
    it("second rewriter's segment handler sees expressions from first rewriter", function()
      local rewriter1 = preprocessor.create_rewriter("first_text", { priority = 100 })
      rewriter1:on_text("EXPAND", function(_, ctx)
        return ctx:expression("expanded()")
      end)

      local rewriter2 = preprocessor.create_rewriter("second_seg", { priority = 200 })
      rewriter2:on("expression", function(segment, ctx)
        return ctx:expression("wrapped(" .. segment.code .. ")")
      end)

      local doc = make_doc({
        ast.text("do EXPAND now", { start_line = 1 }),
      })

      local result_doc, diagnostics = runner.run_pipeline(doc, nil, make_opts({ rewriter1, rewriter2 }))
      assert.equals(0, #diagnostics)

      local segments = result_doc.messages[1].segments
      local found_wrapped = false
      for _, seg in ipairs(segments) do
        if seg.kind == "expression" and seg.code == "wrapped(expanded())" then
          found_wrapped = true
        end
      end
      assert.is_true(found_wrapped)
    end)

    it("processes all messages in a document", function()
      local rewriter = preprocessor.create_rewriter("all_msgs")
      rewriter:on_text("X", function(_, ctx)
        return ctx:text("Y")
      end)

      local doc = ast.document(nil, {
        ast.message("System", {
          ast.text("sys X", { start_line = 1 }),
        }, { start_line = 1, end_line = 2 }),
        ast.message("You", {
          ast.text("user X", { start_line = 3 }),
        }, { start_line = 3, end_line = 4 }),
        ast.message("Assistant", {
          ast.text("asst X", { start_line = 5 }),
        }, { start_line = 5, end_line = 6 }),
      }, {}, { start_line = 1, end_line = 6 })

      local result_doc = runner.run_pipeline(doc, nil, make_opts({ rewriter }))

      for _, msg in ipairs(result_doc.messages) do
        local text_parts = {}
        for _, seg in ipairs(msg.segments) do
          if seg.kind == "text" then
            table.insert(text_parts, seg.value)
          end
        end
        local full = table.concat(text_parts)
        assert.is_nil(full:find("X"), "expected X replaced in " .. msg.role .. " message: " .. full)
        assert.truthy(full:find("Y"), "expected Y in " .. msg.role .. " message: " .. full)
      end
    end)
  end)

  describe("error handling — extended", function()
    it("includes rewriter name in diagnostics", function()
      local rewriter = preprocessor.create_rewriter("named_rewriter")
      rewriter:on_text("FAIL", function()
        error("intentional failure")
      end)

      local doc = make_doc({
        ast.text("FAIL here", { start_line = 3 }),
      })

      local _, diagnostics = runner.run_pipeline(doc, nil, make_opts({ rewriter }))
      assert.equals(1, #diagnostics)
      assert.equals("named_rewriter", diagnostics[1].rewriter_name)
      assert.equals("rewriter", diagnostics[1].type)
    end)

    it("continues processing after a handler error", function()
      local rewriter = preprocessor.create_rewriter("recover")
      local call_count = 0
      rewriter:on_text("(%u+)", function(match, ctx)
        call_count = call_count + 1
        if match.full == "BOOM" then
          error("boom!")
        end
        return ctx:text(match.full:lower())
      end)

      local doc = make_doc({
        ast.text("AAA BOOM ZZZ", { start_line = 1 }),
      })

      local result_doc, diagnostics = runner.run_pipeline(doc, nil, make_opts({ rewriter }))
      assert.equals(1, #diagnostics)
      assert.equals(3, call_count)

      -- AAA should be lowered, BOOM should be preserved, ZZZ should be lowered
      local segments = result_doc.messages[1].segments
      local full_text = ""
      for _, seg in ipairs(segments) do
        if seg.kind == "text" then
          full_text = full_text .. seg.value
        end
      end
      assert.truthy(full_text:find("aaa"))
      assert.truthy(full_text:find("BOOM"))
      assert.truthy(full_text:find("zzz"))
    end)
  end)

  describe("position derivation — extended", function()
    it("multi-line segment tracks line numbers for each line's matches", function()
      local positions_seen = {}
      local rewriter = preprocessor.create_rewriter("multiline_pos")
      rewriter:on_text("MARK", function(match, _ctx)
        table.insert(positions_seen, {
          line = match._line,
          col = match.start_col,
        })
        return nil -- keep original
      end)

      local doc = make_doc({
        ast.text("no match\nMARK here\nmore\nMARK again", { start_line = 10 }),
      })

      runner.run_pipeline(doc, nil, make_opts({ rewriter }))

      -- MARK on line 2 of segment (base_line 10, so line 11) at col 1
      -- MARK on line 4 of segment (base_line 10, so line 13) at col 1
      assert.equals(2, #positions_seen)
      assert.equals(11, positions_seen[1].line)
      assert.equals(1, positions_seen[1].col)
      assert.equals(13, positions_seen[2].line)
      assert.equals(1, positions_seen[2].col)
    end)

    it("column position reflects match offset within the line", function()
      local rewriter = preprocessor.create_rewriter("col_pos")
      rewriter:on_text("TARGET", function(_, ctx)
        return ctx:expression("found()")
      end)

      local doc = make_doc({
        ast.text("abc TARGET xyz", { start_line = 1 }),
      })

      local result_doc = runner.run_pipeline(doc, nil, make_opts({ rewriter }))

      local segments = result_doc.messages[1].segments
      local expr_seg = nil
      for _, seg in ipairs(segments) do
        if seg.kind == "expression" then
          expr_seg = seg
        end
      end
      assert.is_not_nil(expr_seg)
      -- "TARGET" starts at column 5 (1-indexed)
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

  describe("preprocessor.run() suspension handling", function()
    it("catches Confirmation and returns nil in interactive mode", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local rewriter = preprocessor.create_rewriter("confirmer")
      rewriter:on_text("ASK", function(_, ctx)
        ctx:confirm("ask_id", "Proceed?")
        return ctx:remove()
      end)
      preprocessor.register(rewriter)

      local doc = make_doc({
        ast.text("do ASK now", { start_line = 1 }),
      })

      local result_doc, diagnostics = preprocessor.run(doc, bufnr, { interactive = true })
      assert.is_nil(result_doc)
      assert.is_nil(diagnostics)

      -- Verify that the pending confirmation was stored in buffer state
      local flemma_state = require("flemma.state")
      local buffer_state = flemma_state.get_buffer_state(bufnr)
      assert.is_not_nil(buffer_state._pending_confirmation)
      assert.equals("ask_id", buffer_state._pending_confirmation.id)
    end)

    it("returns stored answer on re-run after confirmation", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local flemma_state = require("flemma.state")

      local rewriter = preprocessor.create_rewriter("confirmer_rerun")
      rewriter:on_text("ASK", function(_, ctx)
        local answer = ctx:confirm("rerun_id", "Proceed?")
        if answer then
          return ctx:text("YES")
        end
        return ctx:remove()
      end)
      preprocessor.register(rewriter)

      -- Simulate stored answer from UI
      local buffer_state = flemma_state.get_buffer_state(bufnr)
      buffer_state.confirmation_answers = { rerun_id = true }

      local doc = make_doc({
        ast.text("do ASK now", { start_line = 1 }),
      })

      local result_doc, diagnostics = preprocessor.run(doc, bufnr, { interactive = true })
      assert.is_not_nil(result_doc)
      assert.equals(0, #diagnostics)

      -- The "ASK" match should be replaced with "YES"
      local segments = result_doc.messages[1].segments
      local found_yes = false
      for _, seg in ipairs(segments) do
        if seg.kind == "text" and seg.value == "YES" then
          found_yes = true
        end
      end
      assert.is_true(found_yes)
    end)

    it("returns doc unchanged when no rewriters are registered", function()
      -- registry is already cleared in before_each
      local doc = make_doc({
        ast.text("hello world", { start_line = 1 }),
      })

      local result_doc, diagnostics = preprocessor.run(doc, nil)
      assert.equals(doc, result_doc)
      assert.equals(0, #diagnostics)
    end)
  end)

  describe("ctx:rewrite() buffer edits", function()
    it("queues and applies buffer edits in interactive mode", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      -- Set up buffer content matching the AST
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "before OLD after" })

      local rewriter = preprocessor.create_rewriter("rewrite_test")
      rewriter:on_text("OLD", function(_, ctx)
        return ctx:rewrite("NEW")
      end)

      local doc = ast.document(nil, {
        ast.message("You", {
          ast.text("before OLD after", { start_line = 1 }),
        }, { start_line = 1, end_line = 1 }),
      }, {}, { start_line = 1, end_line = 1 })

      local result_doc = runner.run_pipeline(doc, bufnr, {
        interactive = true,
        rewriters = { rewriter },
        bufnr = bufnr,
      })

      -- AST should have the rewritten text
      local segments = result_doc.messages[1].segments
      local found_new = false
      for _, seg in ipairs(segments) do
        if seg.kind == "text" and seg.value == "NEW" then
          found_new = true
        end
      end
      assert.is_true(found_new)

      -- Buffer should have the rewritten text
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.truthy(lines[1]:find("NEW"), "expected buffer to contain NEW: " .. lines[1])
    end)

    it("does NOT apply buffer edits in non-interactive mode", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "before OLD after" })

      local rewriter = preprocessor.create_rewriter("no_edit")
      rewriter:on_text("OLD", function(_, ctx)
        return ctx:rewrite("NEW")
      end)

      local doc = ast.document(nil, {
        ast.message("You", {
          ast.text("before OLD after", { start_line = 1 }),
        }, { start_line = 1, end_line = 1 }),
      }, {}, { start_line = 1, end_line = 1 })

      local result_doc = runner.run_pipeline(doc, bufnr, {
        interactive = false,
        rewriters = { rewriter },
        bufnr = bufnr,
      })

      -- AST should still have the rewritten text
      local segments = result_doc.messages[1].segments
      local found_new = false
      for _, seg in ipairs(segments) do
        if seg.kind == "text" and seg.value == "NEW" then
          found_new = true
        end
      end
      assert.is_true(found_new)

      -- Buffer should NOT have been modified
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals("before OLD after", lines[1])
    end)
  end)

  describe("parser post-parse hook and raw_ast_cache", function()
    local parser_mod

    before_each(function()
      package.loaded["flemma.parser"] = nil
      parser_mod = require("flemma.parser")
    end)

    after_each(function()
      parser_mod.set_post_parse_hook(nil)
    end)

    it("set_post_parse_hook is called during get_parsed_document", function()
      local hook_called = false
      parser_mod.set_post_parse_hook(function(doc, _bufnr)
        hook_called = true
        return doc
      end)

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "Hello world" })

      parser_mod.get_parsed_document(bufnr)
      assert.is_true(hook_called)
    end)

    it("get_raw_document returns the pre-hook document", function()
      -- Hook that empties all segments
      parser_mod.set_post_parse_hook(function(doc, _bufnr)
        for _, msg in ipairs(doc.messages) do
          msg.segments = {}
        end
        return doc
      end)

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "Hello world" })

      -- get_parsed_document returns the post-hook (empty segments) version
      local parsed_doc = parser_mod.get_parsed_document(bufnr)
      assert.equals(0, #parsed_doc.messages[1].segments)

      -- get_raw_document returns the pre-hook version with original segments
      local raw_doc = parser_mod.get_raw_document(bufnr)
      assert.is_true(#raw_doc.messages[1].segments > 0)
    end)
  end)
end)
