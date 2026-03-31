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

    it("sanitizes label portion of category/label names", function()
      local sink = sink_module.create({ name = "http/https://api.anthropic.com/v1/messages" })
      sink:write("x\n")
      sink:_drain()
      local buf_name = vim.api.nvim_buf_get_name(sink._bufnr)
      local name_without_id = buf_name:gsub("#%d+$", "")
      assert.equals("flemma://sink/http/https:-api.anthropic.com-v1-messages", name_without_id)
      sink:destroy()
    end)

    it("collapses consecutive hyphens and trims edges", function()
      local sink = sink_module.create({ name = "bash/echo 'hello world' && ls" })
      sink:write("x\n")
      sink:_drain()
      local buf_name = vim.api.nvim_buf_get_name(sink._bufnr)
      local name_without_id = buf_name:gsub("#%d+$", "")
      assert.equals("flemma://sink/bash/echo-hello-world-ls", name_without_id)
      sink:destroy()
    end)

    it("leaves already-clean names unchanged", function()
      local sink = sink_module.create({ name = "anthropic/thinking" })
      sink:write("x\n")
      sink:_drain()
      local buf_name = vim.api.nvim_buf_get_name(sink._bufnr)
      local name_without_id = buf_name:gsub("#%d+$", "")
      assert.equals("flemma://sink/anthropic/thinking", name_without_id)
      sink:destroy()
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

    it("fires on_line for remaining partial", function()
      local lines_seen = {}
      local sink = sink_module.create({
        name = "test/flush-partial-online",
        on_line = function(line)
          table.insert(lines_seen, line)
        end,
      })
      sink:write("hello\npartial")
      assert.are.same({ "hello" }, lines_seen) -- only "hello" fired so far
      sink:flush()
      assert.are.same({ "hello", "partial" }, lines_seen) -- "partial" should fire on flush
      sink:destroy()
    end)

    it("fires on_line for remaining partial on destroy", function()
      local lines_seen = {}
      local sink = sink_module.create({
        name = "test/flush-partial-online-destroy",
        on_line = function(line)
          table.insert(lines_seen, line)
        end,
      })
      sink:write("hello\npartial")
      assert.are.same({ "hello" }, lines_seen)
      sink:destroy()
      assert.are.same({ "hello", "partial" }, lines_seen) -- destroy() calls flush(), should fire on_line
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
      sink:write("data\n") -- materialize the buffer
      vim.api.nvim_buf_delete(sink._bufnr, { force = true })
      sink:flush() -- triggers detection
      assert.has_no.errors(function()
        sink:write("more data")
      end)
    end)

    it("errors on read after external deletion", function()
      local sink = sink_module.create({ name = "test/bd-read" })
      sink:write("data\n") -- materialize the buffer
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

  describe("lazy materialization", function()
    it("does not create a buffer on create()", function()
      local buf_count_before = #vim.api.nvim_list_bufs()
      local sink = sink_module.create({ name = "test/lazy-no-buf" })
      local buf_count_after = #vim.api.nvim_list_bufs()
      assert.are.equal(buf_count_before, buf_count_after)
      sink:destroy()
    end)

    it("creates a buffer on first write()", function()
      local sink = sink_module.create({ name = "test/lazy-write" })
      local buf_count_before = #vim.api.nvim_list_bufs()
      sink:write("hello")
      local buf_count_after = #vim.api.nvim_list_bufs()
      assert.are.equal(buf_count_before + 1, buf_count_after)
      sink:destroy()
    end)

    it("creates a buffer on first write_lines()", function()
      local sink = sink_module.create({ name = "test/lazy-write-lines" })
      local buf_count_before = #vim.api.nvim_list_bufs()
      sink:write_lines({ "hello" })
      local buf_count_after = #vim.api.nvim_list_bufs()
      assert.are.equal(buf_count_before + 1, buf_count_after)
      sink:destroy()
    end)

    it("read() returns empty string before any writes", function()
      local sink = sink_module.create({ name = "test/lazy-read-empty" })
      assert.are.equal("", sink:read())
      sink:destroy()
    end)

    it("read_lines() returns empty table before any writes", function()
      local sink = sink_module.create({ name = "test/lazy-rl-empty" })
      assert.are.same({}, sink:read_lines())
      sink:destroy()
    end)

    it("destroy() before any writes does not error", function()
      local sink = sink_module.create({ name = "test/lazy-destroy" })
      assert.has_no.errors(function()
        sink:destroy()
      end)
      assert.is_true(sink:is_destroyed())
    end)

    it("write() after destroy is a no-op even if never materialized", function()
      local sink = sink_module.create({ name = "test/lazy-write-after-destroy" })
      sink:destroy()
      local buf_count_before = #vim.api.nvim_list_bufs()
      sink:write("hello")
      local buf_count_after = #vim.api.nvim_list_bufs()
      assert.are.equal(buf_count_before, buf_count_after)
    end)

    it("fires FlemmaSinkCreated on first write, not on create()", function()
      local created_events = {}
      local group = vim.api.nvim_create_augroup("TestSinkCreated", { clear = true })
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "FlemmaSinkCreated",
        callback = function(event)
          table.insert(created_events, event.data)
        end,
      })

      local sink = sink_module.create({ name = "test/lazy-autocmd" })
      assert.are.equal(0, #created_events)

      sink:write("data")
      assert.are.equal(1, #created_events)
      assert.are.equal("test/lazy-autocmd", created_events[1].name)

      -- Second write does not fire again
      sink:write("more")
      assert.are.equal(1, #created_events)

      sink:destroy()
      vim.api.nvim_del_augroup_by_id(group)
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

    it("defers buffer deletion when command-line window is active", function()
      local sink = sink_module.create({ name = "test/destroy-cmdwin" })
      sink:write("data\n")
      sink:_drain()
      local bufnr = sink._bufnr
      assert.is_true(vim.api.nvim_buf_is_valid(bufnr))

      -- Simulate being inside the command-line window (q:)
      local original_fn = vim.fn.getcmdwintype
      vim.fn.getcmdwintype = function()
        return ":"
      end

      sink:destroy()

      -- Restore before CmdwinLeave fires so the callback runs outside the mock
      vim.fn.getcmdwintype = original_fn

      -- Logically destroyed, but buffer deletion was deferred
      assert.is_true(sink:is_destroyed())
      assert.is_true(vim.api.nvim_buf_is_valid(bufnr))

      -- Simulate leaving the command-line window and let the scheduled cleanup fire
      vim.api.nvim_exec_autocmds("CmdwinLeave", {})
      vim.wait(100, function()
        return not vim.api.nvim_buf_is_valid(bufnr)
      end)

      assert.is_false(vim.api.nvim_buf_is_valid(bufnr))
    end)
  end)

  describe("writequeue integration", function()
    it("sets sink buffer as nomodifiable", function()
      local sink = sink_module.create({ name = "test/wq-nomod" })
      sink:write("data\n")
      assert.is_false(vim.bo[sink._bufnr].modifiable)
      sink:destroy()
    end)

    it("drain writes through nomodifiable buffer successfully", function()
      local sink = sink_module.create({ name = "test/wq-drain-nomod" })
      sink:write("hello\nworld\n")
      sink:_drain()
      local buf_lines = vim.api.nvim_buf_get_lines(sink._bufnr, 0, -1, false)
      assert.are.same({ "hello", "world" }, buf_lines)
      -- Buffer should still be nomodifiable after drain
      assert.is_false(vim.bo[sink._bufnr].modifiable)
      sink:destroy()
    end)

    it("flush writes through nomodifiable buffer successfully", function()
      local sink = sink_module.create({ name = "test/wq-flush-nomod" })
      sink:write("hello\npartial")
      sink:flush()
      assert.are.equal("hello\npartial", sink:read())
      assert.is_false(vim.bo[sink._bufnr].modifiable)
      sink:destroy()
    end)

    it("buffer stays nomodifiable after destroy with visible window", function()
      local sink = sink_module.create({ name = "test/wq-visible-nomod" })
      sink:write("data\n")
      sink:_drain()
      -- Open the sink buffer in a window (simulates external viewer)
      local win = vim.api.nvim_open_win(sink._bufnr, false, {
        split = "below",
        win = vim.api.nvim_get_current_win(),
        height = 3,
      })
      sink:destroy()
      -- Buffer should still be nomodifiable even when deferred via bufhidden=wipe
      if vim.api.nvim_buf_is_valid(sink._bufnr) then
        assert.is_false(vim.bo[sink._bufnr].modifiable)
      end
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end)

    it("destroy clears writequeue to prevent post-deletion writes", function()
      local sink = sink_module.create({ name = "test/wq-destroy-clear" })
      sink:write("data\n")
      -- Verify destroy doesn't error (writequeue.clear is called internally)
      assert.has_no.errors(function()
        sink:destroy()
      end)
    end)
  end)
end)
