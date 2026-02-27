-- Tests for per-buffer FIFO write queue with textlock retry
-- Verifies ordering, isolation, re-entrancy, E565 retry, and cleanup

describe("flemma.buffer.writequeue", function()
  local writequeue

  before_each(function()
    package.loaded["flemma.buffer.writequeue"] = nil
    writequeue = require("flemma.buffer.writequeue")
  end)

  describe("enqueue", function()
    it("executes an operation immediately when not textlocked", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local executed = false
      writequeue.enqueue(bufnr, function()
        executed = true
      end)
      assert.is_true(executed)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("preserves FIFO order across multiple enqueues", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local order = {}
      writequeue.enqueue(bufnr, function()
        table.insert(order, 1)
      end)
      writequeue.enqueue(bufnr, function()
        table.insert(order, 2)
      end)
      writequeue.enqueue(bufnr, function()
        table.insert(order, 3)
      end)
      assert.are.same({ 1, 2, 3 }, order)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("uses separate queues per buffer", function()
      local buf_a = vim.api.nvim_create_buf(false, true)
      local buf_b = vim.api.nvim_create_buf(false, true)
      local results = {}
      writequeue.enqueue(buf_a, function()
        table.insert(results, "a")
      end)
      writequeue.enqueue(buf_b, function()
        table.insert(results, "b")
      end)
      assert.are.same({ "a", "b" }, results)
      vim.api.nvim_buf_delete(buf_a, { force = true })
      vim.api.nvim_buf_delete(buf_b, { force = true })
    end)

    it("skips operations for invalid buffers", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_delete(bufnr, { force = true })
      local executed = false
      -- Should not error, should silently skip
      writequeue.enqueue(bufnr, function()
        executed = true
      end)
      assert.is_false(executed)
    end)

    it("handles re-entrant enqueue from within a queued operation", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local order = {}
      writequeue.enqueue(bufnr, function()
        table.insert(order, "first")
        -- Re-entrant enqueue from within a running operation
        writequeue.enqueue(bufnr, function()
          table.insert(order, "re-entrant")
        end)
      end)
      writequeue.enqueue(bufnr, function()
        table.insert(order, "second")
      end)
      -- Re-entrant item should execute after "second" (appended during drain)
      assert.are.same({ "first", "second", "re-entrant" }, order)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("textlock retry", function()
    it("retries on E565 and succeeds on next drain", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local call_count = 0
      local fake_textlock = true

      writequeue.enqueue(bufnr, function()
        call_count = call_count + 1
        if fake_textlock then
          fake_textlock = false
          error("Vim:E565: Not allowed to change text or change window")
        end
      end)

      -- First call raised E565, should have re-scheduled
      assert.are.equal(1, call_count)

      -- Simulate the vim.schedule firing by draining manually
      writequeue.drain(bufnr)
      assert.are.equal(2, call_count)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("preserves order when retrying — queued items wait behind the failed one", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local order = {}
      local fake_textlock = true

      writequeue.enqueue(bufnr, function()
        if fake_textlock then
          fake_textlock = false
          error("Vim:E565: Not allowed to change text or change window")
        end
        table.insert(order, "first")
      end)

      -- Second enqueue arrives while first is blocked by E565.
      -- drain() stopped after E565, so the queue is non-empty.
      -- enqueue sees non-empty queue and just appends (no recursive drain).
      writequeue.enqueue(bufnr, function()
        table.insert(order, "second")
      end)

      assert.are.same({}, order)

      -- Now drain — both should execute in order
      writequeue.drain(bufnr)
      assert.are.same({ "first", "second" }, order)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("restores vim.bo.modifiable on E565 failure", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.bo[bufnr].modifiable = false -- Locked state

      local fake_textlock = true
      writequeue.enqueue(bufnr, function()
        -- Simulates what on_content does: set modifiable, then hit E565
        vim.bo[bufnr].modifiable = true
        if fake_textlock then
          fake_textlock = false
          error("Vim:E565: Not allowed to change text or change window")
        end
      end)

      -- After E565, drain should have restored modifiable to false
      assert.is_false(vim.bo[bufnr].modifiable)

      -- On successful retry, the fn sets modifiable=true and it stays
      writequeue.drain(bufnr)
      assert.is_true(vim.bo[bufnr].modifiable)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("gives up after max retries and continues to next entry", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local call_count = 0
      local second_ran = false

      writequeue.enqueue(bufnr, function()
        call_count = call_count + 1
        error("Vim:E565: Not allowed to change text or change window")
      end)

      writequeue.enqueue(bufnr, function()
        second_ran = true
      end)

      -- Drain repeatedly past max retries
      for _ = 1, 20 do
        writequeue.drain(bufnr)
      end

      -- Should have stopped at MAX_RETRIES (10) + 1 initial = 11
      assert.is_true(call_count <= 11)
      -- Second entry should have run after the first was dropped
      assert.is_true(second_ran)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("discards non-E565 errors and continues draining", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local second_ran = false

      writequeue.enqueue(bufnr, function()
        error("some other error")
      end)

      writequeue.enqueue(bufnr, function()
        second_ran = true
      end)

      -- Non-E565 error is logged and discarded; queue continues
      assert.is_true(second_ran)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("clear", function()
    it("removes all pending operations for a buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local fake_textlock = true
      local executed = false

      writequeue.enqueue(bufnr, function()
        if fake_textlock then
          fake_textlock = false
          error("Vim:E565: Not allowed to change text or change window")
        end
        executed = true
      end)

      writequeue.clear(bufnr)
      writequeue.drain(bufnr)
      assert.is_false(executed)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
