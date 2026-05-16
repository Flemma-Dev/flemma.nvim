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
          job_id = "job_abc12",
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
          job_id = "job_xyz99",
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
          job_id = "job_abc12",
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
          job_id = "job_xyz99",
        },
      }
      local pending = executor.get_pending(bufnr)
      assert.equals(0, #pending)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("generate_job_id", function()
    it("returns a string starting with job_ followed by 8 alphanumeric chars", function()
      local executor = require("flemma.tools.executor")
      local id = executor.generate_job_id()
      assert.is_string(id)
      assert.truthy(id:match("^job_[a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]$"))
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

    it("avoids IDs present in the exclusion set", function()
      local executor = require("flemma.tools.executor")
      local original_uv_random = vim.uv.random
      local call_count = 0
      vim.uv.random = function(n) -- luacheck: ignore 122
        call_count = call_count + 1
        if call_count == 1 then
          return string.rep("\0", n)
        end
        return original_uv_random(n)
      end

      local colliding_id = "job_" .. string.rep("a", 8)
      local result = executor.generate_job_id({ [colliding_id] = true })

      vim.uv.random = original_uv_random -- luacheck: ignore 122

      assert.is_string(result)
      assert.are_not.equal(colliding_id, result)
      assert.truthy(result:match("^job_[a-z0-9]+$"))
    end)

    it("returns normally when exclusion set is nil", function()
      local executor = require("flemma.tools.executor")
      local id = executor.generate_job_id(nil)
      assert.is_string(id)
      assert.truthy(id:match("^job_[a-z0-9]+$"))
    end)

    it("returns normally when exclusion set is empty", function()
      local executor = require("flemma.tools.executor")
      local id = executor.generate_job_id({})
      assert.is_string(id)
      assert.truthy(id:match("^job_[a-z0-9]+$"))
    end)
  end)

  describe("collect_buffer_job_ids", function()
    it("collects job IDs from tool_result meta and job_result segments", function()
      local executor = require("flemma.tools.executor")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "Hello",
        "",
        "@Assistant:",
        "",
        "**Tool Use:** `bash` (`toolu_01AAA`)",
        "",
        "```json",
        '{"command":"ls","label":"listing","timeout":10,"background":true}',
        "```",
        "",
        "**Tool Use:** `bash` (`toolu_01BBB`)",
        "",
        "```json",
        '{"command":"pwd","label":"cwd","timeout":10,"background":true}',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01AAA` (job=job_alpha111)",
        "",
        "```",
        "Running as a background job `job_alpha111`.",
        "```",
        "",
        "**Tool Result:** `toolu_01BBB` (job=job_beta2222)",
        "",
        "```",
        "Running as a background job `job_beta2222`.",
        "```",
        "",
        "@You:",
        "",
        "**Job Result:** `job_alpha111`",
        "",
        "```",
        "file.txt",
        "```",
        "",
      })
      local ids = executor.collect_buffer_job_ids(bufnr)
      assert.is_true(ids["job_alpha111"])
      assert.is_true(ids["job_beta2222"])
      assert.is_nil(ids["job_nonexist"])
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("returns empty table for buffer with no jobs", function()
      local executor = require("flemma.tools.executor")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "Hello",
        "",
        "@Assistant:",
        "Hi there!",
      })
      local ids = executor.collect_buffer_job_ids(bufnr)
      assert.same({}, ids)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("completion queue", function()
    it("enqueues and dequeues background completions", function()
      local executor = require("flemma.tools.executor")
      local bufnr = vim.api.nvim_create_buf(false, true)

      assert.is_false(executor.has_job_completions(bufnr))

      executor.enqueue_job_completion(bufnr, {
        job_id = "job_abc12",
        tool_id = "tool_01",
        tool_name = "bash",
        result = { success = true, output = "hello" },
      })

      assert.is_true(executor.has_job_completions(bufnr))

      local items = executor.drain_job_completions(bufnr)
      assert.equals(1, #items)
      assert.equals("job_abc12", items[1].job_id)
      assert.equals("tool_01", items[1].tool_id)
      assert.is_true(items[1].result.success)

      assert.is_false(executor.has_job_completions(bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("preserves FIFO order", function()
      local executor = require("flemma.tools.executor")
      local bufnr = vim.api.nvim_create_buf(false, true)

      executor.enqueue_job_completion(bufnr, {
        job_id = "job_first",
        tool_id = "t1",
        tool_name = "bash",
        result = { success = true, output = "a" },
      })
      executor.enqueue_job_completion(bufnr, {
        job_id = "job_second",
        tool_id = "t2",
        tool_name = "bash",
        result = { success = true, output = "b" },
      })

      local items = executor.drain_job_completions(bufnr)
      assert.equals(2, #items)
      assert.equals("job_first", items[1].job_id)
      assert.equals("job_second", items[2].job_id)
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
        "**Tool Result:** `tool_01` (job=job_abc12)",
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
          job_id = "job_abc12",
        },
      }

      executor._test_complete_execution(bufnr, "tool_01", { success = true, output = "hello world" })

      assert.is_true(executor.has_job_completions(bufnr))
      local items = executor.drain_job_completions(bufnr)
      assert.equals(1, #items)
      assert.equals("job_abc12", items[1].job_id)
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
        "**Tool Result:** `tool_drain` (job=job_drain)",
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
          job_id = "job_drain",
        },
      }
      buffer_state.current_request = nil

      local drain_called_with = nil
      local original = bridge.drain_job_completions
      bridge.drain_job_completions = function(b)
        drain_called_with = b
      end

      executor._test_complete_execution(bufnr, "tool_drain", { success = true, output = "done" })

      vim.wait(100, function()
        return drain_called_with ~= nil
      end)

      assert.equals(bufnr, drain_called_with)

      bridge.drain_job_completions = original
      buffer_state.pending_executions = nil
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("execute with background option", function()
    it("allocates job_id and writes background placeholder", function()
      local executor = require("flemma.tools.executor")
      local registry = require("flemma.tools.registry")
      registry.clear()
      registry.register("test_job_tool", {
        name = "test_job_tool",
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
        "**Tool Use:** `test_job_tool` (`tool_job_01`)",
        "",
        "```json",
        '{"cmd": "long task"}',
        "```",
        "",
        "@You:",
        "**Tool Result:** `tool_job_01` (approved)",
        "",
        "```",
        "```",
      })
      vim.bo[bufnr].filetype = "chat"

      ---@type flemma.tools.ToolContext
      local context = {
        tool_id = "tool_job_01",
        tool_name = "test_job_tool",
        input = { cmd = "long task" },
        node = {
          kind = "tool_use",
          id = "tool_job_01",
          name = "test_job_tool",
          input = {},
          position = { start_line = 2, end_line = 6 },
        },
        start_line = 2,
        end_line = 6,
      }

      local ok, err = executor.execute(bufnr, context, { background = true })
      assert.is_true(ok, err)

      local buffer_state = state.get_buffer_state(bufnr)
      local entry = buffer_state.pending_executions["tool_job_01"]
      assert.truthy(entry)
      assert.truthy(entry.job_id)
      assert.truthy(entry.job_id:match("^job_"))

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local header_found = false
      for _, line in ipairs(lines) do
        if line:match("Tool Result.*tool_job_01.*job=") then
          header_found = true
          break
        end
      end
      assert.is_true(header_found, "Expected job= in tool_result header")

      local joined = table.concat(lines, "\n")
      assert.truthy(joined:match("Running as a background job%."))
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
      assert.truthy(joined:match("Running as a background job%."))

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
      local header_line = 8
      assert.truthy(extmarks[header_line], "indicator should be on the tool result header line")
      assert.truthy(extmarks[header_line]:match("Executing"), "backgrounded tool should still show Executing status")

      buffer_state.pending_executions = nil
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("does not double-schedule send_or_execute when autopilot is armed", function()
      local executor = require("flemma.tools.executor")
      local bridge = require("flemma.bridge")
      local autopilot = require("flemma.autopilot")
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "**Tool Use:** `bash` (`tool_bg`)",
        "",
        "```json",
        '{"command": "sleep 60"}',
        "```",
        "",
        "@You:",
        "**Tool Result:** `tool_bg`",
        "",
        "```",
        "```",
      })
      vim.bo[bufnr].filetype = "chat"

      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_bg"] = {
          tool_id = "tool_bg",
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

      autopilot.set_enabled(true)
      autopilot.arm(bufnr)

      local send_call_count = 0
      local original_send = bridge.send_or_execute
      bridge.send_or_execute = function(opts)
        if opts and opts.bufnr == bufnr then
          send_call_count = send_call_count + 1
        end
      end

      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 9, 0 })

      local ok, err = executor.background_at_cursor(bufnr)
      assert.is_true(ok, err)

      vim.wait(100, function()
        return send_call_count > 0
      end)

      assert.equals(1, send_call_count, "send_or_execute should be scheduled exactly once, got " .. send_call_count)

      bridge.send_or_execute = original_send
      autopilot.disarm(bufnr)
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

  describe("re-adopt background job on duplicate tool_id", function()
    local function make_readopt_buffer()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "**Tool Use:** `test_readopt_tool` (`tool_readopt`)",
        "",
        "```json",
        '{"cmd": "test"}',
        "```",
        "",
        "@You:",
        "**Tool Result:** `tool_readopt` (approved)",
        "",
        "```",
        "```",
      })
      vim.bo[bufnr].filetype = "chat"
      return bufnr
    end

    local function make_readopt_context()
      ---@type flemma.tools.ToolContext
      return {
        tool_id = "tool_readopt",
        tool_name = "test_readopt_tool",
        input = { cmd = "test" },
        node = {
          kind = "tool_use",
          id = "tool_readopt",
          name = "test_readopt_tool",
          input = {},
          position = { start_line = 2, end_line = 6 },
        },
        start_line = 2,
        end_line = 6,
      }
    end

    it("re-adopts existing background job instead of rejecting", function()
      local executor = require("flemma.tools.executor")
      local registry = require("flemma.tools.registry")
      registry.clear()
      registry.register("test_readopt_tool", {
        name = "test_readopt_tool",
        description = "Test tool for re-adopt",
        async = true,
        input_schema = { type = "object", properties = { cmd = { type = "string" } } },
        execute = function()
          return function() end
        end,
      })

      local bufnr = make_readopt_buffer()
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_readopt"] = {
          tool_id = "tool_readopt",
          tool_name = "test_readopt_tool",
          bufnr = bufnr,
          start_line = 2,
          end_line = 6,
          cancel_fn = nil,
          started_at = 1000,
          completed = false,
          placeholder_modified = true,
          job_id = "job_original",
        },
      }

      local context = make_readopt_context()
      local ok, err = executor.execute(bufnr, context, { background = true })
      assert.is_true(ok, "expected success, got error: " .. tostring(err))
      assert.is_nil(err)

      local entry = buffer_state.pending_executions["tool_readopt"]
      assert.truthy(entry)
      assert.equals("job_original", entry.job_id, "job_id must remain the original, not a new allocation")

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local header_line = lines[9]
      assert.truthy(header_line:match("job=job_original"), "header should reference original job: " .. header_line)
      assert.is_falsy(header_line:match("%(approved%)"), "approved status should be cleared: " .. header_line)

      buffer_state.pending_executions = nil
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("re-adopts completed background job whose result is queued", function()
      local executor = require("flemma.tools.executor")
      local registry = require("flemma.tools.registry")
      registry.clear()
      registry.register("test_readopt_tool", {
        name = "test_readopt_tool",
        description = "Test tool for re-adopt",
        async = true,
        input_schema = { type = "object", properties = { cmd = { type = "string" } } },
        execute = function()
          return function() end
        end,
      })

      local bufnr = make_readopt_buffer()
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_readopt"] = {
          tool_id = "tool_readopt",
          tool_name = "test_readopt_tool",
          bufnr = bufnr,
          start_line = 2,
          end_line = 6,
          cancel_fn = nil,
          started_at = 1000,
          completed = true,
          placeholder_modified = true,
          job_id = "job_completed",
        },
      }

      local context = make_readopt_context()
      local ok, err = executor.execute(bufnr, context, { background = true })
      assert.is_true(ok, "expected success for completed job, got error: " .. tostring(err))

      local entry = buffer_state.pending_executions["tool_readopt"]
      assert.truthy(entry)
      assert.equals("job_completed", entry.job_id, "job_id must remain the completed job's id")

      buffer_state.pending_executions = nil
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("rejects duplicate foreground execution", function()
      local executor = require("flemma.tools.executor")
      local registry = require("flemma.tools.registry")
      registry.clear()
      registry.register("test_readopt_tool", {
        name = "test_readopt_tool",
        description = "Test tool for re-adopt",
        async = true,
        input_schema = { type = "object", properties = { cmd = { type = "string" } } },
        execute = function()
          return function() end
        end,
      })

      local bufnr = make_readopt_buffer()
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_readopt"] = {
          tool_id = "tool_readopt",
          tool_name = "test_readopt_tool",
          bufnr = bufnr,
          start_line = 2,
          end_line = 6,
          cancel_fn = nil,
          started_at = 1000,
          completed = false,
          placeholder_modified = true,
        },
      }

      local context = make_readopt_context()
      local ok, err = executor.execute(bufnr, context, { background = true })
      assert.is_false(ok)
      assert.truthy(err:match("already executing"))

      buffer_state.pending_executions = nil
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
