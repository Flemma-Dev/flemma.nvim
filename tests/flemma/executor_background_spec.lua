describe("executor background filtering", function()
  local state
  local tool_exec_ns = vim.api.nvim_create_namespace("flemma_tool_execution")

  ---@param bufnr integer
  ---@return table<integer, string>
  local function get_tool_extmarks(bufnr)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, tool_exec_ns, 0, -1, { details = true })
    local result = {}
    for _, mark in ipairs(marks) do
      local line_idx = mark[2]
      local details = mark[4]
      local text = ""
      if details.virt_text then
        for _, chunk in ipairs(details.virt_text) do
          text = text .. chunk[1]
        end
      end
      if result[line_idx] then
        result[line_idx] = result[line_idx] .. text
      else
        result[line_idx] = text
      end
    end
    return result
  end

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

  describe("do_completion routing", function()
    it("routes background completion to queue instead of injecting", function()
      local executor = require("flemma.tools.executor")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "**Tool Use:** `bash` (`tool_01`)",
        "",
        "```json",
        '{"command": "sleep 10"}',
        "```",
        "",
        "@You:",
        "**Tool Result:** `tool_01` (job=bg_abc12)",
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
          placeholder_modified = true,
          job_id = "bg_abc12",
        },
      }

      executor._test_do_completion(bufnr, "tool_01", { success = true, output = "hello world" })

      assert.is_true(executor.has_background_completions(bufnr))
      local items = executor.drain_background_completions(bufnr)
      assert.equals(1, #items)
      assert.equals("bg_abc12", items[1].job_id)
      assert.is_true(items[1].result.success)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local joined = table.concat(lines, "\n")
      assert.truthy(joined:match("Running in background"))
      assert.is_falsy(joined:match("hello world"))

      assert.truthy(buffer_state.pending_executions["tool_01"])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("schedules drain via bridge when conversation is idle", function()
      local executor = require("flemma.tools.executor")
      local bridge = require("flemma.bridge")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "**Tool Use:** `bash` (`tool_drain`)",
        "",
        "```json",
        '{"command": "sleep 30"}',
        "```",
        "",
        "@You:",
        "**Tool Result:** `tool_drain` (job=bg_drain)",
        "",
        "```",
        "Running in background.",
        "```",
      })
      vim.bo[bufnr].filetype = "chat"

      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_drain"] = {
          tool_id = "tool_drain",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 2,
          end_line = 6,
          started_at = 0,
          completed = false,
          placeholder_modified = true,
          job_id = "bg_drain",
        },
      }
      buffer_state.current_request = nil

      local drain_called_with = nil
      local original = bridge.drain_background_completions
      bridge.drain_background_completions = function(b)
        drain_called_with = b
      end

      executor._test_do_completion(bufnr, "tool_drain", { success = true, output = "done" })

      vim.wait(100, function()
        return drain_called_with ~= nil
      end)

      assert.equals(bufnr, drain_called_with)

      bridge.drain_background_completions = original
      buffer_state.pending_executions = nil
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("execute with background option", function()
    it("allocates job_id and writes background placeholder", function()
      local executor = require("flemma.tools.executor")
      local registry = require("flemma.tools.registry")
      registry.clear()
      registry.register("test_bg_tool", {
        name = "test_bg_tool",
        description = "Test tool",
        async = true,
        input_schema = { type = "object", properties = { cmd = { type = "string" } } },
        execute = function()
          return function() end
        end,
      })

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "**Tool Use:** `test_bg_tool` (`tool_bg_01`)",
        "",
        "```json",
        '{"cmd": "long task"}',
        "```",
        "",
        "@You:",
        "**Tool Result:** `tool_bg_01` (approved)",
        "",
        "```",
        "```",
      })
      vim.bo[bufnr].filetype = "chat"

      ---@type flemma.tools.ToolContext
      local context = {
        tool_id = "tool_bg_01",
        tool_name = "test_bg_tool",
        input = { cmd = "long task" },
        node = {
          kind = "tool_use",
          id = "tool_bg_01",
          name = "test_bg_tool",
          input = {},
          position = { start_line = 2, end_line = 6 },
        },
        start_line = 2,
        end_line = 6,
      }

      local ok, err = executor.execute(bufnr, context, { background = true })
      assert.is_true(ok, err)

      local buffer_state = state.get_buffer_state(bufnr)
      local entry = buffer_state.pending_executions["tool_bg_01"]
      assert.truthy(entry)
      assert.truthy(entry.job_id)
      assert.truthy(entry.job_id:match("^bg_"))

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local header_found = false
      for _, line in ipairs(lines) do
        if line:match("Tool Result.*tool_bg_01.*job=") then
          header_found = true
          break
        end
      end
      assert.is_true(header_found, "Expected job= in tool_result header")

      local joined = table.concat(lines, "\n")
      assert.truthy(joined:match("Running in background%."))
      local extmarks = get_tool_extmarks(bufnr)
      assert.truthy(next(extmarks), "background execution should keep the spinner indicator visible")
      assert.truthy(extmarks[8]:match("Executing"), "background execution should show Executing status")

      if entry.cancel_fn then
        pcall(entry.cancel_fn)
      end
      buffer_state.pending_executions = nil
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("background_at_cursor", function()
    it("returns error when tool is not running", function()
      local executor = require("flemma.tools.executor")
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
        "**Tool Result:** `tool_01`",
        "",
        "```",
        "done",
        "```",
      })
      vim.bo[bufnr].filetype = "chat"

      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 9, 0 })
      local ok, err = executor.background_at_cursor(bufnr)
      assert.is_false(ok)
      assert.truthy(err)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("backgrounds a running foreground tool", function()
      local executor = require("flemma.tools.executor")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "**Tool Use:** `bash` (`tool_mid`)",
        "",
        "```json",
        '{"command": "sleep 60"}',
        "```",
        "",
        "@You:",
        "**Tool Result:** `tool_mid`",
        "",
        "```",
        "```",
      })
      vim.bo[bufnr].filetype = "chat"

      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_mid"] = {
          tool_id = "tool_mid",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 2,
          end_line = 6,
          cancel_fn = function() end,
          started_at = 0,
          completed = false,
          placeholder_modified = true,
        },
      }
      buffer_state.locked = true

      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 9, 0 })

      local ok, err = executor.background_at_cursor(bufnr)
      assert.is_true(ok, err)

      local entry = buffer_state.pending_executions["tool_mid"]
      assert.truthy(entry.job_id)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local header_line = lines[9]
      assert.truthy(header_line:match("job="), "Expected job= in header: " .. header_line)

      local joined = table.concat(lines, "\n")
      assert.truthy(joined:match("Running in background%."))

      assert.is_false(buffer_state.locked)
      assert.same({}, get_tool_extmarks(bufnr))

      buffer_state.pending_executions = nil
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("keeps an existing execution indicator when backgrounding mid-flight", function()
      local executor = require("flemma.tools.executor")
      local indicators = require("flemma.ui.indicators")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "**Tool Use:** `bash` (`tool_mid`)",
        "",
        "```json",
        '{"command": "sleep 60"}',
        "```",
        "",
        "@You:",
        "**Tool Result:** `tool_mid`",
        "",
        "```",
        "```",
      })
      vim.bo[bufnr].filetype = "chat"

      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_mid"] = {
          tool_id = "tool_mid",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 2,
          end_line = 6,
          cancel_fn = function() end,
          started_at = 0,
          completed = false,
          placeholder_modified = true,
        },
      }
      indicators.show_tool_indicator(bufnr, "tool_mid", 9)
      assert.truthy(next(get_tool_extmarks(bufnr)))

      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 9, 0 })

      local ok, err = executor.background_at_cursor(bufnr)
      assert.is_true(ok, err)
      local extmarks = get_tool_extmarks(bufnr)
      assert.truthy(next(extmarks), "backgrounding should keep the spinner indicator visible")
      assert.truthy(extmarks[13]:match("Executing"), "backgrounded tool should still show Executing status")

      buffer_state.pending_executions = nil
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("rolls back header metadata when content update fails", function()
      local executor = require("flemma.tools.executor")
      local injector = require("flemma.tools.injector")
      local original_set_fence_content = injector.set_fence_content
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "**Tool Use:** `bash` (`tool_mid`)",
        "",
        "```json",
        '{"command": "sleep 60"}',
        "```",
        "",
        "@You:",
        "**Tool Result:** `tool_mid`",
        "",
        "```",
        "```",
      })
      vim.bo[bufnr].filetype = "chat"

      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_mid"] = {
          tool_id = "tool_mid",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 2,
          end_line = 6,
          cancel_fn = function() end,
          started_at = 0,
          completed = false,
          placeholder_modified = true,
        },
      }

      injector.set_fence_content = function()
        return false, "forced failure"
      end

      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 9, 0 })

      local ok, err = executor.background_at_cursor(bufnr)
      injector.set_fence_content = original_set_fence_content

      assert.is_false(ok)
      assert.truthy(err:match("forced failure"))
      assert.is_nil(buffer_state.pending_executions["tool_mid"].job_id)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals("**Tool Result:** `tool_mid`", lines[9])

      buffer_state.pending_executions = nil
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
