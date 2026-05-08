describe("job completion drain", function()
  local hooks_fired = {}

  before_each(function()
    hooks_fired = {}
    vim.api.nvim_create_autocmd("User", {
      pattern = "FlemmaConversationIdle",
      callback = function(ev)
        table.insert(hooks_fired, { name = "conversation:idle", data = ev.data })
      end,
    })
    vim.api.nvim_create_autocmd("User", {
      pattern = "FlemmaJobCompleted",
      callback = function(ev)
        table.insert(hooks_fired, { name = "job:completed", data = ev.data })
      end,
    })
  end)

  after_each(function()
    vim.api.nvim_clear_autocmds({ pattern = "FlemmaConversationIdle" })
    vim.api.nvim_clear_autocmds({ pattern = "FlemmaJobCompleted" })
  end)

  it("fires conversation:idle hook correctly", function()
    local hooks = require("flemma.hooks")
    hooks.dispatch("conversation:idle", { bufnr = 0 })
    assert.equals(1, #hooks_fired)
    assert.equals("conversation:idle", hooks_fired[1].name)
  end)

  it("fires job:completed hook correctly", function()
    local hooks = require("flemma.hooks")
    hooks.dispatch("job:completed", {
      bufnr = 0,
      job_id = "job_test1",
      tool_id = "tool_01",
      tool_name = "bash",
      success = true,
    })
    assert.equals(1, #hooks_fired)
    assert.equals("job:completed", hooks_fired[1].name)
    assert.equals("job_test1", hooks_fired[1].data.job_id)
  end)

  it("drain_and_inject_completions injects results into the buffer", function()
    package.loaded["flemma.tools.executor"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.state"] = nil
    local executor = require("flemma.tools.executor")

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@Assistant:",
      "Done.",
      "",
      "@You:",
      "",
    })
    vim.bo[bufnr].filetype = "chat"

    executor.enqueue_job_completion(bufnr, {
      job_id = "job_drain1",
      tool_id = "tool_01",
      tool_name = "bash",
      result = { success = true, output = "drain test output" },
    })

    assert.is_true(executor.has_job_completions(bufnr))

    local injector = require("flemma.tools.injector")
    local items = executor.drain_job_completions(bufnr)
    for _, item in ipairs(items) do
      injector.append_job_result(bufnr, item.job_id, item.result)
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local joined = table.concat(lines, "\n")
    assert.truthy(joined:match("%*%*Job Result:%*%*%s*`job_drain1`"))
    assert.truthy(joined:match("drain test output"))
    assert.is_false(executor.has_job_completions(bufnr))

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("drains multiple completions in FIFO order and injects all results", function()
    package.loaded["flemma.tools.executor"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.state"] = nil
    local executor = require("flemma.tools.executor")

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@Assistant:",
      "Done.",
      "",
      "@You:",
      "",
    })
    vim.bo[bufnr].filetype = "chat"

    executor.enqueue_job_completion(bufnr, {
      job_id = "job_first",
      tool_id = "tool_01",
      tool_name = "bash",
      result = { success = true, output = "first output" },
    })
    executor.enqueue_job_completion(bufnr, {
      job_id = "job_second",
      tool_id = "tool_02",
      tool_name = "bash",
      result = { success = false, output = "second failed" },
    })

    assert.is_true(executor.has_job_completions(bufnr))

    local injector = require("flemma.tools.injector")
    local items = executor.drain_job_completions(bufnr)
    assert.equals(2, #items)
    assert.equals("job_first", items[1].job_id)
    assert.equals("job_second", items[2].job_id)

    for _, item in ipairs(items) do
      injector.append_job_result(bufnr, item.job_id, item.result)
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local joined = table.concat(lines, "\n")
    assert.truthy(joined:match("%*%*Job Result:%*%*%s*`job_first`"))
    assert.truthy(joined:match("first output"))
    assert.truthy(joined:match("%*%*Job Result:%*%*%s*`job_second`%s*%(error%)"))
    assert.truthy(joined:match("second failed"))

    assert.is_false(executor.has_job_completions(bufnr))

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("fires job:completed hook for each drained item", function()
    local hooks = require("flemma.hooks")
    local fired = {}
    vim.api.nvim_create_autocmd("User", {
      pattern = "FlemmaJobCompleted",
      callback = function(ev)
        table.insert(fired, ev.data.job_id)
      end,
    })

    hooks.dispatch("job:completed", {
      bufnr = 0,
      job_id = "job_a",
      tool_id = "tool_01",
      tool_name = "bash",
      success = true,
    })
    hooks.dispatch("job:completed", {
      bufnr = 0,
      job_id = "job_b",
      tool_id = "tool_02",
      tool_name = "bash",
      success = false,
    })

    assert.equals(2, #fired)
    assert.equals("job_a", fired[1])
    assert.equals("job_b", fired[2])

    vim.api.nvim_clear_autocmds({ pattern = "FlemmaJobCompleted" })
  end)

  it("does not auto-continue when user is in insert mode in an empty @You block", function()
    -- Reproduces the E21 bug: user enters insert mode in the empty @You prompt,
    -- hasn't typed anything yet. A background job completes and gets injected
    -- as case 1 (empty @You). Without the insert-mode guard, safe=true and
    -- autopilot schedules send_or_execute, which locks the buffer while the
    -- user is still in insert mode → E21: Cannot make changes.
    package.loaded["flemma"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.tools.executor"] = nil
    package.loaded["flemma.tools.injector"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.bridge"] = nil
    package.loaded["flemma.autopilot"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.schema"] = nil
    package.loaded["flemma.ui"] = nil
    package.loaded["flemma.ui.folding"] = nil
    package.loaded["flemma.parser"] = nil

    local flemma = require("flemma")
    flemma.setup({ tools = { autopilot = { enabled = true } } })
    local executor = require("flemma.tools.executor")
    local bridge = require("flemma.bridge")

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@Assistant:",
      "Done.",
      "",
      "@You:",
      "",
    })
    vim.bo[bufnr].filetype = "chat"

    -- Display the buffer in a window so bufwinid() returns a valid window
    vim.cmd("new")
    vim.api.nvim_set_current_buf(bufnr)

    -- Enqueue a job completion
    executor.enqueue_job_completion(bufnr, {
      job_id = "job_insert1",
      tool_id = "tool_01",
      tool_name = "bash",
      result = { success = true, output = "hello world" },
    })

    -- Simulate insert mode. Plenary's headless runner cannot sustain real
    -- insert mode across Lua calls, so we stub vim.fn.mode() for the
    -- duration of the drain call.
    local real_mode = vim.fn.mode
    vim.fn.mode = function()
      return "i"
    end

    -- Intercept send_or_execute to detect if autopilot tried to auto-continue.
    local core = require("flemma.core")
    local send_called = false
    local real_send = core.send_or_execute
    core.send_or_execute = function(...)
      send_called = true
      return real_send(...)
    end

    -- Trigger drain — this is the real code path from executor → bridge → core
    bridge.drain_job_completions(bufnr)

    vim.fn.mode = real_mode

    -- The job result should be injected into the buffer
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local joined = table.concat(lines, "\n")
    assert.truthy(joined:match("%*%*Job Result:%*%*%s*`job_insert1`"), "Job result should be in the buffer")

    -- Allow any scheduled callbacks (the auto-continue vim.schedule) to fire
    vim.wait(50, function()
      return send_called
    end)

    -- Critical: send_or_execute must NOT have been called. If it was, the
    -- buffer would have been locked while the user was in insert mode → E21.
    assert.is_false(send_called, "Autopilot must not auto-continue when user is in insert mode")

    core.send_or_execute = real_send
  end)

  it("does not auto-continue when autopilot was disarmed (e.g., after Ctrl+C)", function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.tools.executor"] = nil
    package.loaded["flemma.tools.injector"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.bridge"] = nil
    package.loaded["flemma.autopilot"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.schema"] = nil
    package.loaded["flemma.ui"] = nil
    package.loaded["flemma.ui.folding"] = nil
    package.loaded["flemma.parser"] = nil

    local flemma = require("flemma")
    flemma.setup({ tools = { autopilot = { enabled = true } } })
    local executor = require("flemma.tools.executor")
    local ap = require("flemma.autopilot")
    local bridge = require("flemma.bridge")

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@Assistant:",
      "Done.",
      "",
      "@You:",
      "",
    })
    vim.bo[bufnr].filetype = "chat"

    vim.cmd("new")
    vim.api.nvim_set_current_buf(bufnr)

    -- Simulate: autopilot was armed, then user pressed Ctrl+C which disarmed it.
    ap.arm(bufnr)
    ap.disarm(bufnr)
    assert.equals("idle", ap.get_state(bufnr))

    executor.enqueue_job_completion(bufnr, {
      job_id = "job_disarm1",
      tool_id = "tool_01",
      tool_name = "bash",
      result = { success = true, output = "completed after cancel" },
    })

    local core = require("flemma.core")
    local send_called = false
    local real_send = core.send_or_execute
    core.send_or_execute = function(...)
      send_called = true
      return real_send(...)
    end

    bridge.drain_job_completions(bufnr)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local joined = table.concat(lines, "\n")
    assert.truthy(joined:match("%*%*Job Result:%*%*%s*`job_disarm1`"), "Job result should be in the buffer")

    vim.wait(50, function()
      return send_called
    end)

    assert.is_false(send_called, "Autopilot must not auto-continue after disarm (Ctrl+C)")

    core.send_or_execute = real_send
  end)

  it("auto-continues when autopilot went idle naturally and background jobs complete later", function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.tools.executor"] = nil
    package.loaded["flemma.tools.injector"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.bridge"] = nil
    package.loaded["flemma.autopilot"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.schema"] = nil
    package.loaded["flemma.ui"] = nil
    package.loaded["flemma.ui.folding"] = nil
    package.loaded["flemma.parser"] = nil

    local flemma = require("flemma")
    flemma.setup({ tools = { autopilot = { enabled = true, resume_delay = 0 } } })
    local executor = require("flemma.tools.executor")
    local ap = require("flemma.autopilot")
    local bridge = require("flemma.bridge")

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@Assistant:",
      "Your background jobs are running.",
      "",
      "@You:",
      "",
    })
    vim.bo[bufnr].filetype = "chat"

    vim.cmd("new")
    vim.api.nvim_set_current_buf(bufnr)

    -- Simulate the exact scenario from the bug:
    -- 1. Autopilot was armed (tool_use in response)
    -- 2. on_response_complete found no tool_use in the NEXT response → natural idle
    -- This is NOT a disarm — the model just didn't use tools this turn.
    ap.arm(bufnr)
    ap.on_response_complete(bufnr)
    assert.equals("idle", ap.get_state(bufnr))

    -- Background job completes after the response finished
    executor.enqueue_job_completion(bufnr, {
      job_id = "job_late1",
      tool_id = "tool_01",
      tool_name = "bash",
      result = { success = true, output = "late job output" },
    })

    local core = require("flemma.core")
    local send_called = false
    local real_send = core.send_or_execute
    core.send_or_execute = function()
      send_called = true
    end

    bridge.drain_job_completions(bufnr)

    -- The job result should be injected into the buffer
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local joined = table.concat(lines, "\n")
    assert.truthy(joined:match("%*%*Job Result:%*%*%s*`job_late1`"), "Job result should be in the buffer")

    -- Allow any scheduled callbacks to fire
    vim.wait(50, function()
      return send_called
    end)

    -- Critical: send_or_execute MUST be called — the background job result
    -- needs to be sent back to the model for it to see the output.
    assert.is_true(
      send_called,
      "Autopilot must auto-continue when idle naturally (not disarmed) and background jobs arrive"
    )

    core.send_or_execute = real_send
  end)

  it("debounces auto-continue with resume_delay when autopilot is idle", function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.tools.executor"] = nil
    package.loaded["flemma.tools.injector"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.bridge"] = nil
    package.loaded["flemma.autopilot"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.schema"] = nil
    package.loaded["flemma.ui"] = nil
    package.loaded["flemma.ui.folding"] = nil
    package.loaded["flemma.parser"] = nil

    local flemma = require("flemma")
    flemma.setup({ tools = { autopilot = { enabled = true, resume_delay = 200 } } })
    local executor = require("flemma.tools.executor")
    local ap = require("flemma.autopilot")
    local bridge = require("flemma.bridge")
    local st = require("flemma.state")

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@Assistant:",
      "Your background jobs are running.",
      "",
      "@You:",
      "",
    })
    vim.bo[bufnr].filetype = "chat"

    vim.cmd("new")
    vim.api.nvim_set_current_buf(bufnr)

    ap.arm(bufnr)
    ap.on_response_complete(bufnr)

    executor.enqueue_job_completion(bufnr, {
      job_id = "job_cool1",
      tool_id = "tool_01",
      tool_name = "bash",
      result = { success = true, output = "first job" },
    })

    local core = require("flemma.core")
    local send_count = 0
    local real_send = core.send_or_execute
    core.send_or_execute = function()
      send_count = send_count + 1
    end

    bridge.drain_job_completions(bufnr)

    -- Timer should be set but send should NOT have fired yet
    assert.truthy(st.get_buffer_state(bufnr).resume_delay_timer, "Resume delay timer should be active")
    assert.equals(0, send_count, "send_or_execute must not fire immediately during resume delay")

    -- Second job arrives before resume delay expires — timer should reset (debounce)
    executor.enqueue_job_completion(bufnr, {
      job_id = "job_cool2",
      tool_id = "tool_02",
      tool_name = "bash",
      result = { success = true, output = "second job" },
    })
    bridge.drain_job_completions(bufnr)
    assert.equals(0, send_count, "send_or_execute must not fire before resume delay expires")

    -- Wait for resume delay to expire
    vim.wait(400, function()
      return send_count > 0
    end)

    assert.equals(1, send_count, "send_or_execute should fire exactly once after debounce")
    assert.is_nil(st.get_buffer_state(bufnr).resume_delay_timer, "Timer should be cleaned up after firing")

    core.send_or_execute = real_send
  end)

  it("Ctrl+C cancels pending resume delay timer", function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.tools.executor"] = nil
    package.loaded["flemma.tools.injector"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.bridge"] = nil
    package.loaded["flemma.autopilot"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.schema"] = nil
    package.loaded["flemma.ui"] = nil
    package.loaded["flemma.ui.folding"] = nil
    package.loaded["flemma.parser"] = nil

    local flemma = require("flemma")
    flemma.setup({ tools = { autopilot = { enabled = true, resume_delay = 500 } } })
    local executor = require("flemma.tools.executor")
    local ap = require("flemma.autopilot")
    local bridge = require("flemma.bridge")
    local st = require("flemma.state")

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@Assistant:",
      "Done.",
      "",
      "@You:",
      "",
    })
    vim.bo[bufnr].filetype = "chat"

    vim.cmd("new")
    vim.api.nvim_set_current_buf(bufnr)

    ap.arm(bufnr)
    ap.on_response_complete(bufnr)

    executor.enqueue_job_completion(bufnr, {
      job_id = "job_cancel1",
      tool_id = "tool_01",
      tool_name = "bash",
      result = { success = true, output = "will be cancelled" },
    })

    local core = require("flemma.core")
    local send_called = false
    local real_send = core.send_or_execute
    core.send_or_execute = function()
      send_called = true
    end

    bridge.drain_job_completions(bufnr)
    assert.truthy(st.get_buffer_state(bufnr).resume_delay_timer, "Resume delay timer should be active")

    -- User presses Ctrl+C → cancel_request
    core.cancel_request({ bufnr = bufnr })
    assert.is_nil(st.get_buffer_state(bufnr).resume_delay_timer, "Timer should be cancelled by Ctrl+C")

    -- Wait past the resume delay — send should NOT fire
    vim.wait(700, function()
      return send_called
    end)

    assert.is_false(send_called, "send_or_execute must not fire after Ctrl+C cancels resume delay")

    core.send_or_execute = real_send
  end)

  it("does not auto-continue when user enters insert mode during resume delay", function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.tools.executor"] = nil
    package.loaded["flemma.tools.injector"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.bridge"] = nil
    package.loaded["flemma.autopilot"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.schema"] = nil
    package.loaded["flemma.ui"] = nil
    package.loaded["flemma.ui.folding"] = nil
    package.loaded["flemma.parser"] = nil

    local flemma = require("flemma")
    flemma.setup({ tools = { autopilot = { enabled = true, resume_delay = 200 } } })
    local executor = require("flemma.tools.executor")
    local ap = require("flemma.autopilot")
    local bridge = require("flemma.bridge")

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@Assistant:",
      "Done.",
      "",
      "@You:",
      "",
    })
    vim.bo[bufnr].filetype = "chat"

    vim.cmd("new")
    vim.api.nvim_set_current_buf(bufnr)

    ap.arm(bufnr)
    ap.on_response_complete(bufnr)

    executor.enqueue_job_completion(bufnr, {
      job_id = "job_insert_delay1",
      tool_id = "tool_01",
      tool_name = "bash",
      result = { success = true, output = "job finished" },
    })

    local core = require("flemma.core")
    local send_called = false
    local real_send = core.send_or_execute
    core.send_or_execute = function()
      send_called = true
    end

    -- Drain starts the timer (user was in normal mode at drain time)
    bridge.drain_job_completions(bufnr)

    -- User enters insert mode during the resume delay window
    local real_mode = vim.fn.mode
    vim.fn.mode = function()
      return "i"
    end

    -- Wait for the timer to fire
    vim.wait(400, function()
      return send_called
    end)

    vim.fn.mode = real_mode

    -- send_or_execute must NOT fire — user is in insert mode, locking the
    -- buffer would cause E21: Cannot make changes, 'modifiable' is off
    assert.is_false(send_called, "Autopilot must not auto-continue when user entered insert mode during resume delay")

    core.send_or_execute = real_send
  end)
end)
