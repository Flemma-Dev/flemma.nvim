--- Tests for flemma.preprocessor — rewriter factory and registry

local preprocessor
local registry

describe("flemma.preprocessor", function()
  before_each(function()
    package.loaded["flemma.preprocessor"] = nil
    package.loaded["flemma.preprocessor.registry"] = nil
    preprocessor = require("flemma.preprocessor")
    registry = require("flemma.preprocessor.registry")
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
end)
