--- Tests for flemma.preprocessor — rewriter factory, registry, and context

local preprocessor
local registry
local context_module

describe("flemma.preprocessor", function()
  before_each(function()
    package.loaded["flemma.preprocessor"] = nil
    package.loaded["flemma.preprocessor.registry"] = nil
    package.loaded["flemma.preprocessor.context"] = nil
    preprocessor = require("flemma.preprocessor")
    registry = require("flemma.preprocessor.registry")
    context_module = require("flemma.preprocessor.context")
  end)

  describe("create_rewriter()", function()
    it("creates a rewriter with default priority 500", function()
      local rewriter = preprocessor.create_rewriter("test_rewriter")
      assert.equals("test_rewriter", rewriter.name)
      assert.equals(500, rewriter.priority)
    end)

    it("accepts a custom priority", function()
      local rewriter = preprocessor.create_rewriter("early", { priority = 100 })
      assert.equals(100, rewriter.priority)
    end)

    it("initializes empty handler tables", function()
      local rewriter = preprocessor.create_rewriter("empty")
      assert.same({}, rewriter.text_handlers)
      assert.same({}, rewriter.segment_handlers)
    end)
  end)

  describe("Rewriter:on_text()", function()
    it("registers a text handler with pattern and function", function()
      local rewriter = preprocessor.create_rewriter("text_test")
      local handler = function() end
      rewriter:on_text("@%./[^%s]+", handler)

      assert.equals(1, #rewriter.text_handlers)
      assert.equals("@%./[^%s]+", rewriter.text_handlers[1].pattern)
      assert.equals(handler, rewriter.text_handlers[1].handler)
    end)

    it("registers multiple text handlers in order", function()
      local rewriter = preprocessor.create_rewriter("multi_text")
      local handler_a = function() end
      local handler_b = function() end
      rewriter:on_text("pattern_a", handler_a)
      rewriter:on_text("pattern_b", handler_b)

      assert.equals(2, #rewriter.text_handlers)
      assert.equals("pattern_a", rewriter.text_handlers[1].pattern)
      assert.equals("pattern_b", rewriter.text_handlers[2].pattern)
    end)
  end)

  describe("Rewriter:on()", function()
    it("registers a segment handler for a given kind", function()
      local rewriter = preprocessor.create_rewriter("seg_test")
      local handler = function() end
      rewriter:on("expression", handler)

      assert.equals(1, #rewriter.segment_handlers)
      assert.equals("expression", rewriter.segment_handlers[1].kind)
      assert.equals(handler, rewriter.segment_handlers[1].handler)
    end)

    it("registers multiple segment handlers in order", function()
      local rewriter = preprocessor.create_rewriter("multi_seg")
      local handler_a = function() end
      local handler_b = function() end
      rewriter:on("expression", handler_a)
      rewriter:on("file_reference", handler_b)

      assert.equals(2, #rewriter.segment_handlers)
      assert.equals("expression", rewriter.segment_handlers[1].kind)
      assert.equals("file_reference", rewriter.segment_handlers[2].kind)
    end)
  end)

  describe("registry", function()
    it("registers and retrieves a rewriter by name", function()
      local rewriter = preprocessor.create_rewriter("my_rewriter")
      preprocessor.register("my_rewriter", rewriter)

      assert.is_true(registry.has("my_rewriter"))
      local got = registry.get("my_rewriter")
      assert.is_not_nil(got)
      assert.equals("my_rewriter", got.name)
    end)

    it("returns nil for unknown rewriter", function()
      assert.is_nil(registry.get("nonexistent"))
    end)

    it("replaces duplicate registrations", function()
      local rewriter_a = preprocessor.create_rewriter("dup", { priority = 100 })
      local rewriter_b = preprocessor.create_rewriter("dup", { priority = 200 })

      preprocessor.register("dup", rewriter_a)
      preprocessor.register("dup", rewriter_b)

      local got = registry.get("dup")
      assert.equals(200, got.priority)
      assert.equals(1, registry.count())
    end)

    it("returns get_all sorted by priority ascending (lower first)", function()
      local low = preprocessor.create_rewriter("low", { priority = 100 })
      local mid = preprocessor.create_rewriter("mid", { priority = 500 })
      local high = preprocessor.create_rewriter("high", { priority = 900 })

      preprocessor.register("mid", mid)
      preprocessor.register("high", high)
      preprocessor.register("low", low)

      local all = preprocessor.get_all()
      assert.equals(3, #all)
      assert.equals("low", all[1].name)
      assert.equals("mid", all[2].name)
      assert.equals("high", all[3].name)
    end)

    it("unregisters a rewriter and returns true", function()
      local rewriter = preprocessor.create_rewriter("removable")
      preprocessor.register("removable", rewriter)

      assert.is_true(preprocessor.unregister("removable"))
      assert.is_false(registry.has("removable"))
      assert.equals(0, registry.count())
    end)

    it("returns false when unregistering nonexistent rewriter", function()
      assert.is_false(preprocessor.unregister("ghost"))
    end)

    it("rejects dotted names (module paths) as direct names", function()
      local rewriter = preprocessor.create_rewriter("bad")
      assert.has_error(function()
        preprocessor.register("flemma.bad.name", rewriter)
      end)
    end)

    it("registers a rewriter object directly (single-arg overload)", function()
      local rewriter = preprocessor.create_rewriter("direct_reg")
      preprocessor.register(rewriter)

      assert.is_true(registry.has("direct_reg"))
    end)
  end)

  describe("Context", function()
    describe("segment factories", function()
      it("creates a text emission", function()
        local ctx = context_module.new({})
        local emission = ctx:text("hello world")
        assert.equals("text", emission.type)
        assert.equals("hello world", emission.text)
      end)

      it("creates an expression emission", function()
        local ctx = context_module.new({})
        local emission = ctx:expression("os.date()")
        assert.equals("expression", emission.type)
        assert.equals("os.date()", emission.code)
      end)

      it("creates a remove emission", function()
        local ctx = context_module.new({})
        local emission = ctx:remove()
        assert.equals("remove", emission.type)
      end)

      it("creates a rewrite emission", function()
        local ctx = context_module.new({})
        local emission = ctx:rewrite("replacement text")
        assert.equals("rewrite", emission.type)
        assert.equals("replacement text", emission.text)
      end)
    end)

    describe("metadata", function()
      it("stores and retrieves metadata by key", function()
        local ctx = context_module.new({})
        ctx:set("my_key", "my_value")
        assert.equals("my_value", ctx:get("my_key"))
      end)

      it("returns nil for unset keys", function()
        local ctx = context_module.new({})
        assert.is_nil(ctx:get("nonexistent"))
      end)

      it("overwrites existing keys", function()
        local ctx = context_module.new({})
        ctx:set("key", "first")
        ctx:set("key", "second")
        assert.equals("second", ctx:get("key"))
      end)
    end)

    describe("diagnostics", function()
      it("creates a diagnostic with auto-filled fields", function()
        local ctx = context_module.new({
          position = { line = 5, col = 10 },
          _rewriter_name = "test_rewriter",
        })
        ctx:diagnostic(vim.diagnostic.severity.WARN, "something is wrong")

        local diagnostics = ctx:get_diagnostics()
        assert.equals(1, #diagnostics)
        assert.equals("rewriter", diagnostics[1].type)
        assert.equals("test_rewriter", diagnostics[1].rewriter_name)
        assert.equals(vim.diagnostic.severity.WARN, diagnostics[1].severity)
        assert.equals("something is wrong", diagnostics[1].message)
      end)

      it("includes optional position fields from opts", function()
        local ctx = context_module.new({
          position = { line = 5, col = 10 },
          _rewriter_name = "pos_test",
        })
        ctx:diagnostic(vim.diagnostic.severity.ERROR, "bad thing", {
          lnum = 3,
          col = 7,
          end_lnum = 3,
          end_col = 15,
        })

        local diagnostics = ctx:get_diagnostics()
        assert.equals(3, diagnostics[1].lnum)
        assert.equals(7, diagnostics[1].col)
        assert.equals(3, diagnostics[1].end_lnum)
        assert.equals(15, diagnostics[1].end_col)
      end)

      it("accumulates multiple diagnostics", function()
        local ctx = context_module.new({ _rewriter_name = "multi_diag" })
        ctx:diagnostic(vim.diagnostic.severity.WARN, "first")
        ctx:diagnostic(vim.diagnostic.severity.ERROR, "second")

        local diagnostics = ctx:get_diagnostics()
        assert.equals(2, #diagnostics)
        assert.equals("first", diagnostics[1].message)
        assert.equals("second", diagnostics[2].message)
      end)
    end)

    describe("constructor options", function()
      it("stores message, message_index, document fields", function()
        local message = { role = "user", segments = {} }
        local document = { frontmatter = nil, messages = {} }
        local ctx = context_module.new({
          message = message,
          message_index = 3,
          document = document,
          interactive = true,
          _bufnr = 42,
        })

        assert.equals(message, ctx.message)
        assert.equals(3, ctx.message_index)
        assert.equals(document, ctx.document)
        assert.is_true(ctx.interactive)
        assert.equals(42, ctx._bufnr)
      end)

      it("defaults interactive to false", function()
        local ctx = context_module.new({})
        assert.is_false(ctx.interactive)
      end)

      it("creates default SystemAccessor and FrontmatterAccessor when not provided", function()
        local ctx = context_module.new({})
        assert.is_not_nil(ctx.system)
        assert.is_not_nil(ctx.frontmatter)
      end)
    end)

    describe("SystemAccessor", function()
      it("stores prepend emissions with position capture", function()
        local accessor = context_module.SystemAccessor.new()
        local ctx = context_module.new({
          system = accessor,
          position = { line = 10, col = 5 },
        })
        accessor:set_context(ctx)

        local emission = ctx:text("prepended text")
        accessor:prepend(emission)

        local prepends = accessor:get_prepends()
        assert.equals(1, #prepends)
        assert.equals("text", prepends[1].emission.type)
        assert.equals("prepended text", prepends[1].emission.text)
        assert.same({ line = 10, col = 5 }, prepends[1].position)
      end)

      it("stores append emissions with position capture", function()
        local accessor = context_module.SystemAccessor.new()
        local ctx = context_module.new({
          system = accessor,
          position = { line = 20, col = 0 },
        })
        accessor:set_context(ctx)

        local emission = ctx:rewrite("appended instruction")
        accessor:append(emission)

        local appends = accessor:get_appends()
        assert.equals(1, #appends)
        assert.equals("rewrite", appends[1].emission.type)
        assert.equals("appended instruction", appends[1].emission.text)
        assert.same({ line = 20, col = 0 }, appends[1].position)
      end)

      it("accumulates multiple prepends and appends", function()
        local accessor = context_module.SystemAccessor.new()
        local ctx = context_module.new({
          system = accessor,
          position = { line = 1, col = 0 },
        })
        accessor:set_context(ctx)

        accessor:prepend(ctx:text("first"))
        accessor:prepend(ctx:text("second"))
        accessor:append(ctx:text("third"))

        assert.equals(2, #accessor:get_prepends())
        assert.equals(1, #accessor:get_appends())
      end)
    end)

    describe("FrontmatterAccessor", function()
      it("records set mutations", function()
        local accessor = context_module.FrontmatterAccessor.new()
        accessor:set("model", "claude-3-opus")

        local mutations = accessor:get_mutations()
        assert.equals(1, #mutations)
        assert.equals("set", mutations[1].action)
        assert.equals("model", mutations[1].key)
        assert.equals("claude-3-opus", mutations[1].value)
      end)

      it("records append mutations", function()
        local accessor = context_module.FrontmatterAccessor.new()
        accessor:append("temperature: 0.5")

        local mutations = accessor:get_mutations()
        assert.equals(1, #mutations)
        assert.equals("append", mutations[1].action)
        assert.equals("temperature: 0.5", mutations[1].line)
      end)

      it("records remove mutations", function()
        local accessor = context_module.FrontmatterAccessor.new()
        accessor:remove("max_tokens")

        local mutations = accessor:get_mutations()
        assert.equals(1, #mutations)
        assert.equals("remove", mutations[1].action)
        assert.equals("max_tokens", mutations[1].key)
      end)

      it("accumulates multiple mutations in order", function()
        local accessor = context_module.FrontmatterAccessor.new()
        accessor:set("model", "gpt-4")
        accessor:remove("temperature")
        accessor:append("tools: [bash]")

        local mutations = accessor:get_mutations()
        assert.equals(3, #mutations)
        assert.equals("set", mutations[1].action)
        assert.equals("remove", mutations[2].action)
        assert.equals("append", mutations[3].action)
      end)
    end)
  end)
end)
