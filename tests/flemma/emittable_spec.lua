local emittable = require("flemma.emittable")

describe("flemma.emittable", function()
  describe("is_emittable", function()
    it("returns true for tables with emit function", function()
      local obj = {
        emit = function() end,
      }
      assert.is_true(emittable.is_emittable(obj))
    end)

    it("returns false for tables without emit", function()
      assert.is_false(emittable.is_emittable({ foo = 1 }))
    end)

    it("returns false for non-tables", function()
      assert.is_false(emittable.is_emittable("hello"))
      assert.is_false(emittable.is_emittable(42))
      assert.is_false(emittable.is_emittable(nil))
      assert.is_false(emittable.is_emittable(true))
    end)

    it("returns false when emit is not a function", function()
      assert.is_false(emittable.is_emittable({ emit = "not a function" }))
    end)
  end)

  describe("EmitContext", function()
    it("text() produces TextPart", function()
      local ctx = emittable.EmitContext.new()
      ctx:text("hello")
      assert.equals(1, #ctx.parts)
      assert.equals("text", ctx.parts[1].kind)
      assert.equals("hello", ctx.parts[1].text)
    end)

    it("text() ignores empty strings", function()
      local ctx = emittable.EmitContext.new()
      ctx:text("")
      assert.equals(0, #ctx.parts)
    end)

    it("text() ignores nil", function()
      local ctx = emittable.EmitContext.new()
      ctx:text(nil)
      assert.equals(0, #ctx.parts)
    end)

    it("file() produces FilePart with position from context", function()
      local pos = { start_line = 5, start_col = 3 }
      local ctx = emittable.EmitContext.new({ position = pos })
      ctx:file("photo.png", "image/png", "binary_data")

      assert.equals(1, #ctx.parts)
      local part = ctx.parts[1]
      assert.equals("file", part.kind)
      assert.equals("photo.png", part.filename)
      assert.equals("image/png", part.mime_type)
      assert.equals("binary_data", part.data)
      assert.equals(5, part.position.start_line)
      assert.equals(3, part.position.start_col)
    end)

    it("emit() dispatches emittable objects", function()
      local ctx = emittable.EmitContext.new()
      local called = false
      local mock_emittable = {
        emit = function(self, emit_ctx)
          called = true
          emit_ctx:text("from emittable")
        end,
      }
      ctx:emit(mock_emittable)
      assert.is_true(called)
      assert.equals(1, #ctx.parts)
      assert.equals("from emittable", ctx.parts[1].text)
    end)

    it("emit() stringifies plain values", function()
      local ctx = emittable.EmitContext.new()
      ctx:emit(42)
      assert.equals(1, #ctx.parts)
      assert.equals("text", ctx.parts[1].kind)
      assert.equals("42", ctx.parts[1].text)
    end)

    it("emit() produces nothing for nil", function()
      local ctx = emittable.EmitContext.new()
      ctx:emit(nil)
      assert.equals(0, #ctx.parts)
    end)

    it("diagnostic() collects diagnostics", function()
      local diags = {}
      local ctx = emittable.EmitContext.new({ diagnostics = diags })
      ctx:diagnostic({ type = "file", severity = "warning", error = "test error" })
      assert.equals(1, #diags)
      assert.equals("test error", diags[1].error)
    end)

    it("diagnostic() is no-op when diagnostics is nil", function()
      local ctx = emittable.EmitContext.new()
      -- Should not error
      ctx:diagnostic({ type = "file", severity = "warning", error = "test" })
    end)

    it("handles nested emit correctly", function()
      local ctx = emittable.EmitContext.new()
      local inner = {
        emit = function(self, emit_ctx)
          emit_ctx:text("inner")
        end,
      }
      local outer = {
        emit = function(self, emit_ctx)
          emit_ctx:text("before ")
          emit_ctx:emit(inner)
          emit_ctx:text(" after")
        end,
      }
      ctx:emit(outer)
      assert.equals(3, #ctx.parts)
      assert.equals("before ", ctx.parts[1].text)
      assert.equals("inner", ctx.parts[2].text)
      assert.equals(" after", ctx.parts[3].text)
    end)
  end)

  describe("binary_include_part", function()
    it("emits a single file part", function()
      local part = emittable.binary_include_part("/path/to/image.png", "image/png", "PNG_DATA")
      assert.is_true(emittable.is_emittable(part))

      local ctx = emittable.EmitContext.new()
      part:emit(ctx)
      assert.equals(1, #ctx.parts)
      assert.equals("file", ctx.parts[1].kind)
      assert.equals("/path/to/image.png", ctx.parts[1].filename)
      assert.equals("image/png", ctx.parts[1].mime_type)
      assert.equals("PNG_DATA", ctx.parts[1].data)
    end)
  end)

  describe("composite_include_part", function()
    it("emits string children as text parts", function()
      local part = emittable.composite_include_part({ "hello ", "world" })
      assert.is_true(emittable.is_emittable(part))

      local ctx = emittable.EmitContext.new()
      part:emit(ctx)
      assert.equals(2, #ctx.parts)
      assert.equals("text", ctx.parts[1].kind)
      assert.equals("hello ", ctx.parts[1].text)
      assert.equals("text", ctx.parts[2].kind)
      assert.equals("world", ctx.parts[2].text)
    end)

    it("emits mixed children in order", function()
      local binary = emittable.binary_include_part("img.png", "image/png", "data")
      local part = emittable.composite_include_part({ "prefix ", binary, " suffix" })

      local ctx = emittable.EmitContext.new()
      part:emit(ctx)
      assert.equals(3, #ctx.parts)
      assert.equals("text", ctx.parts[1].kind)
      assert.equals("prefix ", ctx.parts[1].text)
      assert.equals("file", ctx.parts[2].kind)
      assert.equals("img.png", ctx.parts[2].filename)
      assert.equals("text", ctx.parts[3].kind)
      assert.equals(" suffix", ctx.parts[3].text)
    end)

    it("handles empty children array", function()
      local part = emittable.composite_include_part({})
      local ctx = emittable.EmitContext.new()
      part:emit(ctx)
      assert.equals(0, #ctx.parts)
    end)

    it("handles nested composite parts", function()
      local inner = emittable.composite_include_part({ "A", "B" })
      local outer = emittable.composite_include_part({ "start ", inner, " end" })

      local ctx = emittable.EmitContext.new()
      outer:emit(ctx)
      assert.equals(4, #ctx.parts)
      assert.equals("start ", ctx.parts[1].text)
      assert.equals("A", ctx.parts[2].text)
      assert.equals("B", ctx.parts[3].text)
      assert.equals(" end", ctx.parts[4].text)
    end)
  end)
end)
