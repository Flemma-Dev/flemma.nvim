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
end)
