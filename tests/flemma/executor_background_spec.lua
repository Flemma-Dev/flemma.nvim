describe("executor background filtering", function()
  local state

  before_each(function()
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.tools.executor"] = nil
    state = require("flemma.state")
  end)

  describe("count_running", function()
    it("excludes entries with job_id", function()
      local executor = require("flemma.tools.executor")
      local bufnr = vim.api.nvim_create_buf(false, true)
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_01"] = {
          tool_id = "tool_01",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 1,
          end_line = 2,
          started_at = 0,
          completed = false,
          placeholder_modified = false,
        },
        ["tool_02"] = {
          tool_id = "tool_02",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 3,
          end_line = 4,
          started_at = 0,
          completed = false,
          placeholder_modified = false,
          job_id = "bg_abc12",
        },
        ["tool_03"] = {
          tool_id = "tool_03",
          tool_name = "read",
          bufnr = bufnr,
          start_line = 5,
          end_line = 6,
          started_at = 0,
          completed = false,
          placeholder_modified = false,
        },
      }
      assert.equals(2, executor.count_running(bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("returns 0 when only background entries remain", function()
      local executor = require("flemma.tools.executor")
      local bufnr = vim.api.nvim_create_buf(false, true)
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_01"] = {
          tool_id = "tool_01",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 1,
          end_line = 2,
          started_at = 0,
          completed = false,
          placeholder_modified = false,
          job_id = "bg_xyz99",
        },
      }
      assert.equals(0, executor.count_running(bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("get_pending", function()
    it("excludes entries with job_id", function()
      local executor = require("flemma.tools.executor")
      local bufnr = vim.api.nvim_create_buf(false, true)
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_01"] = {
          tool_id = "tool_01",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 1,
          end_line = 2,
          started_at = 0,
          completed = false,
          placeholder_modified = false,
        },
        ["tool_02"] = {
          tool_id = "tool_02",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 3,
          end_line = 4,
          started_at = 0,
          completed = false,
          placeholder_modified = false,
          job_id = "bg_abc12",
        },
      }
      local pending = executor.get_pending(bufnr)
      assert.equals(1, #pending)
      assert.equals("tool_01", pending[1].tool_id)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("returns empty when only background entries exist", function()
      local executor = require("flemma.tools.executor")
      local bufnr = vim.api.nvim_create_buf(false, true)
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_01"] = {
          tool_id = "tool_01",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 1,
          end_line = 2,
          started_at = 0,
          completed = false,
          placeholder_modified = false,
          job_id = "bg_xyz99",
        },
      }
      local pending = executor.get_pending(bufnr)
      assert.equals(0, #pending)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("generate_job_id", function()
    it("returns a string starting with bg_ followed by 5 alphanumeric chars", function()
      local executor = require("flemma.tools.executor")
      local id = executor.generate_job_id()
      assert.is_string(id)
      assert.truthy(id:match("^bg_[a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]$"))
    end)

    it("generates unique IDs", function()
      local executor = require("flemma.tools.executor")
      local ids = {}
      for _ = 1, 50 do
        local id = executor.generate_job_id()
        assert.is_nil(ids[id], "duplicate job_id: " .. id)
        ids[id] = true
      end
    end)
  end)

  describe("completion queue", function()
    it("enqueues and dequeues background completions", function()
      local executor = require("flemma.tools.executor")
      local bufnr = vim.api.nvim_create_buf(false, true)

      assert.is_false(executor.has_background_completions(bufnr))

      executor.enqueue_background_completion(bufnr, {
        job_id = "bg_abc12",
        tool_id = "tool_01",
        tool_name = "bash",
        result = { success = true, output = "hello" },
      })

      assert.is_true(executor.has_background_completions(bufnr))

      local items = executor.drain_background_completions(bufnr)
      assert.equals(1, #items)
      assert.equals("bg_abc12", items[1].job_id)
      assert.equals("tool_01", items[1].tool_id)
      assert.is_true(items[1].result.success)

      assert.is_false(executor.has_background_completions(bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("preserves FIFO order", function()
      local executor = require("flemma.tools.executor")
      local bufnr = vim.api.nvim_create_buf(false, true)

      executor.enqueue_background_completion(bufnr, {
        job_id = "bg_first",
        tool_id = "t1",
        tool_name = "bash",
        result = { success = true, output = "a" },
      })
      executor.enqueue_background_completion(bufnr, {
        job_id = "bg_second",
        tool_id = "t2",
        tool_name = "bash",
        result = { success = true, output = "b" },
      })

      local items = executor.drain_background_completions(bufnr)
      assert.equals(2, #items)
      assert.equals("bg_first", items[1].job_id)
      assert.equals("bg_second", items[2].job_id)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
