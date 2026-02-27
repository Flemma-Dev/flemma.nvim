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

  describe("write_lines", function()
    it("errors when passed a non-table", function()
      local sink = sink_module.create({ name = "test/wl-type" })
      assert.has_error(function()
        sink:write_lines("not a table")
      end)
      sink:destroy()
    end)

    it("is a silent no-op after destroy", function()
      local sink = sink_module.create({ name = "test/wl-destroyed" })
      sink:destroy()
      assert.has_no.errors(function()
        sink:write_lines({ "data" })
      end)
    end)

    it("appends complete lines to pending", function()
      local lines_seen = {}
      local sink = sink_module.create({
        name = "test/wl-basic",
        on_line = function(line)
          table.insert(lines_seen, line)
        end,
      })
      sink:write_lines({ "alpha", "beta" })
      assert.are.same({ "alpha", "beta" }, lines_seen)
      sink:destroy()
    end)

    it("flushes pending partial before appending lines", function()
      local lines_seen = {}
      local sink = sink_module.create({
        name = "test/wl-partial-flush",
        on_line = function(line)
          table.insert(lines_seen, line)
        end,
      })
      sink:write("partial")
      sink:write_lines({ "next" })
      assert.are.same({ "partial", "next" }, lines_seen)
      sink:destroy()
    end)

    it("handles empty table as a no-op", function()
      local sink = sink_module.create({ name = "test/wl-empty" })
      assert.has_no.errors(function()
        sink:write_lines({})
      end)
      sink:destroy()
    end)
  end)

  describe("read", function()
    it("returns full content as a string", function()
      local sink = sink_module.create({ name = "test/read-basic" })
      sink:write("hello\nworld\n")
      assert.are.equal("hello\nworld", sink:read())
      sink:destroy()
    end)

    it("includes unflushed pending and partial data", function()
      local sink = sink_module.create({ name = "test/read-unflushed" })
      sink:write("line one\npartial")
      local result = sink:read()
      assert.are.equal("line one\npartial", result)
      sink:destroy()
    end)

    it("errors after destroy", function()
      local sink = sink_module.create({ name = "test/read-destroyed" })
      sink:write("data\n")
      sink:destroy()
      assert.has_error(function()
        sink:read()
      end, "sink already destroyed")
    end)

    it("returns empty string for a fresh sink", function()
      local sink = sink_module.create({ name = "test/read-empty" })
      assert.are.equal("", sink:read())
      sink:destroy()
    end)
  end)

  describe("read_lines", function()
    it("returns full content as a lines table", function()
      local sink = sink_module.create({ name = "test/rl-basic" })
      sink:write("hello\nworld\n")
      assert.are.same({ "hello", "world" }, sink:read_lines())
      sink:destroy()
    end)

    it("includes partial as last element", function()
      local sink = sink_module.create({ name = "test/rl-partial" })
      sink:write("hello\npartial")
      assert.are.same({ "hello", "partial" }, sink:read_lines())
      sink:destroy()
    end)

    it("errors after destroy", function()
      local sink = sink_module.create({ name = "test/rl-destroyed" })
      sink:destroy()
      assert.has_error(function()
        sink:read_lines()
      end, "sink already destroyed")
    end)

    it("returns empty table for a fresh sink", function()
      local sink = sink_module.create({ name = "test/rl-empty" })
      assert.are.same({}, sink:read_lines())
      sink:destroy()
    end)

    it("works with write_lines input", function()
      local sink = sink_module.create({ name = "test/rl-write-lines" })
      sink:write_lines({ "a", "b", "c" })
      assert.are.same({ "a", "b", "c" }, sink:read_lines())
      sink:destroy()
    end)
  end)

  describe("flush", function()
    it("pushes pending lines to the backing buffer", function()
      local sink = sink_module.create({ name = "test/flush-basic" })
      sink:write("hello\nworld\n")
      sink:flush()
      -- After flush, read should still work (data now in buffer, pending cleared)
      assert.are.equal("hello\nworld", sink:read())
      sink:destroy()
    end)

    it("includes partial in flush", function()
      local sink = sink_module.create({ name = "test/flush-partial" })
      sink:write("hello\npartial")
      sink:flush()
      assert.are.equal("hello\npartial", sink:read())
      sink:destroy()
    end)

    it("is a no-op when nothing is pending", function()
      local sink = sink_module.create({ name = "test/flush-noop" })
      assert.has_no.errors(function()
        sink:flush()
      end)
      sink:destroy()
    end)

    it("handles first drain replacing empty first line", function()
      local sink = sink_module.create({ name = "test/flush-first" })
      sink:write("first line\n")
      sink:flush()
      assert.are.equal("first line", sink:read())
      sink:destroy()
    end)
  end)

  describe("external buffer deletion", function()
    it("transitions to destroyed when buffer is deleted externally", function()
      local sink = sink_module.create({ name = "test/bd-external" })
      sink:write("data\n")

      -- Simulate user running :bd!
      -- Access _bufnr for testing only
      vim.api.nvim_buf_delete(sink._bufnr, { force = true })

      -- Trigger drain (which detects invalid buffer)
      sink:flush()

      assert.is_true(sink:is_destroyed())
    end)

    it("silently drops writes after external deletion", function()
      local sink = sink_module.create({ name = "test/bd-write" })
      vim.api.nvim_buf_delete(sink._bufnr, { force = true })
      sink:flush() -- triggers detection
      assert.has_no.errors(function()
        sink:write("more data")
      end)
    end)

    it("errors on read after external deletion", function()
      local sink = sink_module.create({ name = "test/bd-read" })
      vim.api.nvim_buf_delete(sink._bufnr, { force = true })
      sink:flush() -- triggers detection
      assert.has_error(function()
        sink:read()
      end, "sink already destroyed")
    end)
  end)

  describe("streaming buffer display", function()
    it("shows partial data in the buffer after drain", function()
      local sink = sink_module.create({ name = "test/char-partial-drain" })
      sink:write("hel")
      -- Trigger internal drain (not flush — flush commits partial as complete line)
      sink:_drain()
      local buf_lines = vim.api.nvim_buf_get_lines(sink._bufnr, 0, -1, false)
      assert.are.same({ "hel" }, buf_lines)
      sink:destroy()
    end)

    it("updates partial in buffer as more data arrives", function()
      local sink = sink_module.create({ name = "test/char-partial-update" })
      sink:write("hel")
      sink:_drain()
      sink:write("lo")
      sink:_drain()
      local buf_lines = vim.api.nvim_buf_get_lines(sink._bufnr, 0, -1, false)
      assert.are.same({ "hello" }, buf_lines)
      sink:destroy()
    end)

    it("completes partial into full line when newline arrives", function()
      local sink = sink_module.create({ name = "test/char-complete" })
      sink:write("hel")
      sink:_drain()
      sink:write("lo\nwor")
      sink:_drain()
      local buf_lines = vim.api.nvim_buf_get_lines(sink._bufnr, 0, -1, false)
      assert.are.same({ "hello", "wor" }, buf_lines)
      sink:destroy()
    end)

    it("read() returns correct content regardless of drain state", function()
      local sink = sink_module.create({ name = "test/char-read-consistency" })
      sink:write("hel")
      assert.are.equal("hel", sink:read())
      sink:_drain()
      assert.are.equal("hel", sink:read())
      sink:write("lo\nwor")
      assert.are.equal("hello\nwor", sink:read())
      sink:_drain()
      assert.are.equal("hello\nwor", sink:read())
      sink:destroy()
    end)

    it("on_line still only fires for complete lines", function()
      local lines_seen = {}
      local sink = sink_module.create({
        name = "test/char-online",
        on_line = function(line)
          table.insert(lines_seen, line)
        end,
      })
      sink:write("hel")
      sink:_drain()
      assert.are.same({}, lines_seen)
      sink:write("lo\nwor")
      assert.are.same({ "hello" }, lines_seen)
      sink:_drain()
      assert.are.same({ "hello" }, lines_seen) -- "wor" is partial, no callback
      sink:destroy()
    end)

    it("handles multiple complete lines plus trailing partial", function()
      local sink = sink_module.create({ name = "test/char-multi-lines" })
      sink:write("line1\nline2\npart")
      sink:_drain()
      local buf_lines = vim.api.nvim_buf_get_lines(sink._bufnr, 0, -1, false)
      assert.are.same({ "line1", "line2", "part" }, buf_lines)
      sink:destroy()
    end)

    it("clears buffer partial when line completes without new partial", function()
      local sink = sink_module.create({ name = "test/char-clear-partial" })
      sink:write("hel")
      sink:_drain()
      sink:write("lo\n")
      sink:_drain()
      local buf_lines = vim.api.nvim_buf_get_lines(sink._bufnr, 0, -1, false)
      assert.are.same({ "hello" }, buf_lines)
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
