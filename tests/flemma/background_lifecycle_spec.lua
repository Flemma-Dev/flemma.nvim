describe("background lifecycle", function()
  local executor

  before_each(function()
    package.loaded["flemma.tools.executor"] = nil
    package.loaded["flemma.state"] = nil
    executor = require("flemma.tools.executor")
  end)

  describe("resolve_orphaned_jobs", function()
    it("detects orphaned job tool_result and injects error completion", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "**Tool Use:** `bash` (`tool_01`)",
        "",
        "```json",
        '{"command": "sleep 999"}',
        "```",
        "",
        "@You:",
        "**Tool Result:** `tool_01` (job=bg_lost1)",
        "",
        "```",
        "Running in background.",
        "```",
      })
      vim.bo[bufnr].filetype = "chat"

      local count = executor.resolve_orphaned_jobs(bufnr)
      assert.equals(1, count)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local joined = table.concat(lines, "\n")
      assert.truthy(joined:match("%*%*Job Result:%*%*%s*`bg_lost1`%s*%(error%)"))
      assert.truthy(joined:match("Job lost: session ended before completion"))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("skips tool_results that already have a completion block", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "**Tool Use:** `bash` (`tool_01`)",
        "",
        "```json",
        '{"command": "ls"}',
        "```",
        "",
        "@You:",
        "**Tool Result:** `tool_01` (job=bg_done1)",
        "",
        "```",
        "Running in background.",
        "```",
        "",
        "@You:",
        "**Job Result:** `bg_done1`",
        "",
        "```",
        "file1.txt file2.txt",
        "```",
      })
      vim.bo[bufnr].filetype = "chat"

      local count = executor.resolve_orphaned_jobs(bufnr)
      assert.equals(0, count)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("skips tool_results that have an active pending_execution", function()
      local state = require("flemma.state")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "**Tool Use:** `bash` (`tool_01`)",
        "",
        "```json",
        '{"command": "ls"}',
        "```",
        "",
        "@You:",
        "**Tool Result:** `tool_01` (job=bg_run1)",
        "",
        "```",
        "Running in background.",
        "```",
      })
      vim.bo[bufnr].filetype = "chat"

      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_01"] = {
          tool_id = "tool_01",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 2,
          end_line = 6,
          started_at = 0,
          completed = false,
          placeholder_modified = false,
          job_id = "bg_run1",
        },
      }

      local count = executor.resolve_orphaned_jobs(bufnr)
      assert.equals(0, count)

      buffer_state.pending_executions = nil
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
