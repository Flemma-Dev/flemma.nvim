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

  it("user-initiated send cancels pending resume delay timer", function()
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
    package.loaded["flemma.hooks"] = nil

    local flemma = require("flemma")
    flemma.setup({ tools = { autopilot = { enabled = true, resume_delay = 500 } } })
    local executor = require("flemma.tools.executor")
    local ap = require("flemma.autopilot")
    local bridge = require("flemma.bridge")
    local st = require("flemma.state")
    local hooks = require("flemma.hooks")

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
      job_id = "job_usersend1",
      tool_id = "tool_01",
      tool_name = "bash",
      result = { success = true, output = "done" },
    })

    local core = require("flemma.core")
    local timer_send_called = false
    local real_send = core.send_or_execute
    core.send_or_execute = function(opts)
      if opts and opts.user_initiated then
        real_send(opts)
        return
      end
      timer_send_called = true
    end

    bridge.drain_job_completions(bufnr)
    assert.truthy(st.get_buffer_state(bufnr).resume_delay_timer, "Resume delay timer should be active")

    local resume_cancelled = false
    hooks.on("autopilot:resume-cancelled", function()
      resume_cancelled = true
    end)

    -- User presses Ctrl+] (send) during resume countdown
    real_send({ bufnr = bufnr, user_initiated = true })
    assert.is_nil(st.get_buffer_state(bufnr).resume_delay_timer, "Timer should be cancelled by user send")
    assert.is_true(resume_cancelled, "autopilot:resume-cancelled hook should fire")

    -- Wait past the resume delay — timer send should NOT fire
    vim.wait(700, function()
      return timer_send_called
    end)

    assert.is_false(timer_send_called, "Timer-driven send_or_execute must not fire after user-initiated send")

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

  it("drops orphaned job result when tool_result placeholder was undone", function()
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
    flemma.setup({})
    local executor = require("flemma.tools.executor")
    local bridge = require("flemma.bridge")
    local st = require("flemma.state")

    -- Buffer does NOT contain a tool_result with job=job_orphan — simulates undo
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

    -- Stale pending entry that survived the undo (in-memory state is not reverted)
    local buffer_state = st.get_buffer_state(bufnr)
    buffer_state.pending_executions = {
      ["tool_01"] = {
        tool_id = "tool_01",
        tool_name = "bash",
        bufnr = bufnr,
        start_line = 2,
        end_line = 6,
        started_at = os.time(),
        completed = true,
        placeholder_modified = true,
        job_id = "job_orphan",
      },
    }

    executor.enqueue_job_completion(bufnr, {
      job_id = "job_orphan",
      tool_id = "tool_01",
      tool_name = "bash",
      result = { success = true, output = "orphaned output" },
    })

    bridge.drain_job_completions(bufnr)

    -- Result must NOT appear in the buffer — the placeholder was undone
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local joined = table.concat(lines, "\n")
    assert.is_falsy(
      joined:match("%*%*Job Result:%*%*%s*`job_orphan`"),
      "Orphaned job result must not be injected into the buffer"
    )
    assert.is_falsy(joined:match("orphaned output"), "Orphaned output must not appear in the buffer")

    -- Stale pending entry must be cleaned up
    assert.is_nil(
      buffer_state.pending_executions["tool_01"],
      "Stale pending_executions entry must be removed after orphaned drop"
    )
  end)

  it("injects job result normally when no pending entry exists", function()
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
    flemma.setup({})
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

    vim.cmd("new")
    vim.api.nvim_set_current_buf(bufnr)

    -- No pending_executions entry — backward-compatible direct enqueue path
    executor.enqueue_job_completion(bufnr, {
      job_id = "job_direct1",
      tool_id = "tool_01",
      tool_name = "bash",
      result = { success = true, output = "direct enqueue output" },
    })

    bridge.drain_job_completions(bufnr)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local joined = table.concat(lines, "\n")
    assert.truthy(
      joined:match("%*%*Job Result:%*%*%s*`job_direct1`"),
      "Job result must be injected when no pending entry exists"
    )
    assert.truthy(joined:match("direct enqueue output"), "Job output must appear in the buffer")
  end)
end)

describe("send_or_execute job completion drain", function()
  local flemma, core, executor, client
  local captured_notifications

  before_each(function()
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
    package.loaded["flemma.provider.normalize"] = nil
    package.loaded["flemma.provider.registry"] = nil

    flemma = require("flemma")
    -- Disable thinking for a predictable Anthropic request body. Disable the
    -- usage bar so real sends don't schedule bar updates that outlive this
    -- spec file (the closure crashes once later files reset module caches).
    flemma.setup({ parameters = { thinking = false }, ui = { usage = { enabled = false } } })
    core = require("flemma.core")
    executor = require("flemma.tools.executor")
    client = require("flemma.client")

    captured_notifications = {}
    local notify = require("flemma.notify")
    notify._set_impl(function(notification)
      table.insert(captured_notifications, notification)
      return notification
    end)
  end)

  after_each(function()
    require("flemma.notify")._reset_impl()
    client.clear_fixtures()
    vim.cmd("silent! %bdelete!")
  end)

  ---Create a .chat buffer with the given lines, shown in a window.
  ---@param lines string[]
  ---@return integer bufnr
  local function make_chat_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].filetype = "chat"
    vim.cmd("new")
    vim.api.nvim_set_current_buf(bufnr)
    return bufnr
  end

  ---Scan an Anthropic request body for a user text block containing `needle`.
  ---@param body table
  ---@param needle string Plain text to search for (not a Lua pattern)
  ---@return boolean
  local function request_has_user_text(body, needle)
    for _, msg in ipairs(body.messages or {}) do
      if msg.role == "user" then
        for _, block in ipairs(msg.content or {}) do
          if type(block) == "table" and block.type == "text" and block.text:find(needle, 1, true) then
            return true
          end
        end
      end
    end
    return false
  end

  it("drains queued job completions on a non-user-initiated send (autopilot)", function()
    client.register_fixture("api%.anthropic%.com", "tests/fixtures/anthropic_hello_success_stream.txt")

    local bufnr = make_chat_buffer({
      "@You:",
      "Check disk space in the background.",
      "",
      "@Assistant:",
      "",
      "**Tool Use:** `bash` (`tool_01`)",
      "```json",
      '{"command":"df -h"}',
      "```",
      "",
      "@You:",
      "",
      "**Tool Result:** `tool_01` (job=job_send1)",
      "```",
      "Running as a background job `job_send1`.",
      "```",
      "",
      "@Assistant:",
      "The job is running; results will be delivered automatically.",
      "",
      "@You:",
      "",
    })

    executor.enqueue_job_completion(bufnr, {
      job_id = "job_send1",
      tool_id = "tool_01",
      tool_name = "bash",
      result = { success = true, output = "Filesystem use 41%" },
    })

    -- Act: autopilot-style dispatch — no user_initiated flag. This is the
    -- bridge.send_or_execute({ bufnr }) call autopilot makes between cycles.
    core.send_or_execute({ bufnr = bufnr })

    -- The queued result must be in the buffer before the request goes out —
    -- not parked until the conversation reaches full idle.
    local joined = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    assert.truthy(
      joined:match("%*%*Job Result:%*%*%s*`job_send1`"),
      "Job result must be drained into the buffer by a non-user-initiated send"
    )
    assert.truthy(joined:find("Filesystem use 41%", 1, true), "Job output must appear in the buffer")

    -- And the outgoing request must carry it to the model.
    local body = core._get_last_request_body()
    assert.is_not_nil(body, "request body was not captured — send did not reach the provider")
    assert.is_true(
      request_has_user_text(body, "[Job result for bash (tool_01)]"),
      "outgoing request must include the drained job result"
    )
  end)

  it("delivers the job result alongside a foreground tool result in the same @You", function()
    -- The exact shape from the field report: the model polls job status, the
    -- status tool result lands in the trailing @You, and the completed job's
    -- result must ride along in the same outgoing request — with the protocol
    -- tool_result first and the job result as a text block after it.
    client.register_fixture("api%.anthropic%.com", "tests/fixtures/anthropic_hello_success_stream.txt")

    local bufnr = make_chat_buffer({
      "@You:",
      "Check disk space in the background.",
      "",
      "@Assistant:",
      "",
      "**Tool Use:** `bash` (`tool_01`)",
      "```json",
      '{"command":"df -h"}',
      "```",
      "",
      "@You:",
      "",
      "**Tool Result:** `tool_01` (job=job_mix1)",
      "```",
      "Running as a background job `job_mix1`.",
      "```",
      "",
      "@Assistant:",
      "",
      "**Tool Use:** `flemma.jobs.status` (`tool_02`)",
      "```json",
      '{"job_id":"job_mix1"}',
      "```",
      "",
      "@You:",
      "",
      "**Tool Result:** `tool_02`",
      "```",
      '{"status":"running","job_id":"job_mix1"}',
      "```",
    })

    executor.enqueue_job_completion(bufnr, {
      job_id = "job_mix1",
      tool_id = "tool_01",
      tool_name = "bash",
      result = { success = true, output = "Filesystem use 41%" },
    })

    core.send_or_execute({ bufnr = bufnr })

    local joined = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    assert.truthy(
      joined:match("%*%*Job Result:%*%*%s*`job_mix1`"),
      "Job result must be drained into the trailing @You holding the tool result"
    )

    local body = core._get_last_request_body()
    assert.is_not_nil(body, "request body was not captured — send did not reach the provider")

    -- The last user message carries both: the status tool_result first
    -- (provider adjacency requirement), then the job result as a text block.
    local last_message = body.messages[#body.messages]
    assert.equals("user", last_message.role)
    assert.equals("tool_result", last_message.content[1].type)
    assert.equals("tool_02", last_message.content[1].tool_use_id)
    local job_text_found = false
    for _, block in ipairs(last_message.content) do
      if
        type(block) == "table"
        and block.type == "text"
        and block.text:find("[Job result for bash (tool_01)]", 1, true)
      then
        job_text_found = true
      end
    end
    assert.is_true(job_text_found, "job result text block must follow the tool_result in the same user message")
  end)

  it("still drains queued job completions on user-initiated sends", function()
    client.register_fixture("api%.anthropic%.com", "tests/fixtures/anthropic_hello_success_stream.txt")

    local bufnr = make_chat_buffer({
      "@You:",
      "Check disk space in the background.",
      "",
      "@Assistant:",
      "",
      "**Tool Use:** `bash` (`tool_01`)",
      "```json",
      '{"command":"df -h"}',
      "```",
      "",
      "@You:",
      "",
      "**Tool Result:** `tool_01` (job=job_user1)",
      "```",
      "Running as a background job `job_user1`.",
      "```",
      "",
      "@Assistant:",
      "The job is running; results will be delivered automatically.",
      "",
      "@You:",
      "",
    })

    executor.enqueue_job_completion(bufnr, {
      job_id = "job_user1",
      tool_id = "tool_01",
      tool_name = "bash",
      result = { success = true, output = "Filesystem use 41%" },
    })

    core.send_or_execute({ bufnr = bufnr, user_initiated = true })

    local joined = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    assert.truthy(
      joined:match("%*%*Job Result:%*%*%s*`job_user1`"),
      "Job result must still be drained on user-initiated sends"
    )

    local body = core._get_last_request_body()
    assert.is_not_nil(body, "request body was not captured — send did not reach the provider")
    assert.is_true(
      request_has_user_text(body, "[Job result for bash (tool_01)]"),
      "outgoing request must include the drained job result"
    )
  end)
end)
