describe("flemma.sink", function()
  local sink_module

  before_each(function()
    package.loaded["flemma.sink"] = nil
    sink_module = require("flemma.sink")
  end)

  describe("create", function()
    it("creates a sink with a hidden scratch buffer", function()
      local sink = sink_module.create({ name = "test/basic" })
      assert.is_not_nil(sink)
      assert.is_false(sink:is_destroyed())
      sink:destroy()
    end)

    it("errors when name is missing", function()
      assert.has_error(function()
        sink_module.create({})
      end)
    end)
  end)

  describe("write", function()
    it("errors when passed a non-string", function()
      local sink = sink_module.create({ name = "test/write-type" })
      assert.has_error(function()
        sink:write(42)
      end)
      sink:destroy()
    end)

    it("is a silent no-op after destroy", function()
      local sink = sink_module.create({ name = "test/write-destroyed" })
      sink:destroy()
      assert.has_no.errors(function()
        sink:write("data")
      end)
    end)

    it("accumulates partial lines without firing on_line", function()
      local lines_seen = {}
      local sink = sink_module.create({
        name = "test/write-partial",
        on_line = function(line)
          table.insert(lines_seen, line)
        end,
      })
      sink:write("hello wor")
      assert.are.same({}, lines_seen)
      sink:destroy()
    end)

    it("fires on_line for each complete line", function()
      local lines_seen = {}
      local sink = sink_module.create({
        name = "test/write-online",
        on_line = function(line)
          table.insert(lines_seen, line)
        end,
      })
      sink:write("hello\nworld\n")
      assert.are.same({ "hello", "world" }, lines_seen)
      sink:destroy()
    end)

    it("frames lines across multiple chunks", function()
      local lines_seen = {}
      local sink = sink_module.create({
        name = "test/write-chunks",
        on_line = function(line)
          table.insert(lines_seen, line)
        end,
      })
      sink:write("hel")
      sink:write("lo\nwor")
      sink:write("ld\n")
      assert.are.same({ "hello", "world" }, lines_seen)
      sink:destroy()
    end)

    it("isolates on_line errors via pcall", function()
      local call_count = 0
      local sink = sink_module.create({
        name = "test/write-error-isolation",
        on_line = function(_)
          call_count = call_count + 1
          if call_count == 1 then
            error("boom")
          end
        end,
      })
      assert.has_no.errors(function()
        sink:write("first\nsecond\n")
      end)
      assert.are.equal(2, call_count)
      sink:destroy()
    end)

    it("handles empty string as a no-op", function()
      local sink = sink_module.create({ name = "test/write-empty" })
      assert.has_no.errors(function()
        sink:write("")
      end)
      sink:destroy()
    end)
  end)

  describe("destroy", function()
    it("marks the sink as destroyed", function()
      local sink = sink_module.create({ name = "test/destroy" })
      sink:destroy()
      assert.is_true(sink:is_destroyed())
    end)

    it("is a no-op when called twice", function()
      local sink = sink_module.create({ name = "test/double-destroy" })
      sink:destroy()
      assert.has_no.errors(function()
        sink:destroy()
      end)
      assert.is_true(sink:is_destroyed())
    end)
  end)
end)
