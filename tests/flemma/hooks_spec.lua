package.loaded["flemma.hooks"] = nil

local hooks

describe("flemma.hooks", function()
  ---@type integer[]
  local autocmd_ids = {}

  before_each(function()
    package.loaded["flemma.hooks"] = nil
    hooks = require("flemma.hooks")
    autocmd_ids = {}
  end)

  after_each(function()
    for _, id in ipairs(autocmd_ids) do
      pcall(vim.api.nvim_del_autocmd, id)
    end
  end)

  ---Register an autocmd and track it for cleanup
  ---@param pattern string
  ---@param callback function
  ---@return integer autocmd_id
  local function track_autocmd(pattern, callback)
    local id = vim.api.nvim_create_autocmd("User", {
      pattern = pattern,
      callback = callback,
    })
    autocmd_ids[#autocmd_ids + 1] = id
    return id
  end

  describe("name_to_pattern()", function()
    -- Access private function via the test helper exposed on M
    it("transforms single-word domain and action", function()
      assert.equals("FlemmaRequestSending", hooks._name_to_pattern("request:sending"))
    end)

    it("transforms hyphenated words", function()
      assert.equals("FlemmaRequestCancellingAll", hooks._name_to_pattern("request:cancelling-all"))
    end)

    it("transforms multi-segment names", function()
      assert.equals("FlemmaBootComplete", hooks._name_to_pattern("boot:complete"))
      assert.equals("FlemmaSinkCreated", hooks._name_to_pattern("sink:created"))
      assert.equals("FlemmaToolCompleted", hooks._name_to_pattern("tool:completed"))
      assert.equals("FlemmaConfigUpdated", hooks._name_to_pattern("config:updated"))
      assert.equals("FlemmaUsageEstimated", hooks._name_to_pattern("usage:estimated"))
    end)
  end)

  describe("dispatch()", function()
    it("defers subscribers to the next event loop iteration by default", function()
      hooks._force_sync(false)
      local received = nil
      hooks.on("request:sending", function(data)
        received = data
      end)

      hooks.dispatch("request:sending", { bufnr = 42 })
      assert.is_nil(received)

      assert.is_true(vim.wait(200, function()
        return received ~= nil
      end))
      assert.equals(42, received.bufnr)
      hooks._force_sync(true)
    end)

    it("fires User autocmd with correct pattern and data", function()
      local received = nil
      track_autocmd("FlemmaRequestSending", function(ev)
        received = ev
      end)

      hooks.dispatch("request:sending", { bufnr = 42 })

      assert.is_not_nil(received)
      assert.equals(42, received.data.bufnr)
    end)

    it("passes empty table when data is nil", function()
      local received = nil
      track_autocmd("FlemmaBootComplete", function(ev)
        received = ev
      end)

      hooks.dispatch("boot:complete")

      assert.is_not_nil(received)
      assert.are.same({}, received.data)
    end)

    it("does not propagate errors from handlers", function()
      track_autocmd("FlemmaSinkCreated", function()
        error("handler exploded")
      end)

      -- Should not throw. silent! suppresses Nvim's "Error detected"
      -- stderr noise from the deliberately error-throwing autocmd callback.
      assert.has_no.errors(function()
        vim.cmd('silent! lua require("flemma.hooks").dispatch("sink:created", { bufnr = 1, name = "test" })')
      end)
    end)

    it("continues to fire autocmds after a handler error", function()
      local error_id = track_autocmd("FlemmaToolExecuting", function()
        error("boom")
      end)

      -- First dispatch triggers error. silent! suppresses Nvim's "Error detected"
      -- stderr noise from the deliberately error-throwing autocmd callback.
      vim.cmd(
        'silent! lua require("flemma.hooks").dispatch("tool:executing", { bufnr = 1, tool_name = "read", tool_id = "t1" })'
      )

      vim.api.nvim_del_autocmd(error_id)

      -- Second dispatch should work fine
      local received = nil
      track_autocmd("FlemmaToolExecuting", function(ev)
        received = ev
      end)

      hooks.dispatch("tool:executing", { bufnr = 2, tool_name = "write", tool_id = "t2" })
      assert.is_not_nil(received)
      assert.equals(2, received.data.bufnr)
    end)
  end)

  describe("on()", function()
    after_each(function()
      hooks._clear_subscribers()
    end)

    it("fires internal subscriber with payload", function()
      local received = nil
      hooks.on("request:sending", function(data)
        received = data
      end)

      hooks.dispatch("request:sending", { bufnr = 7 })

      assert.is_not_nil(received)
      assert.equals(7, received.bufnr)
    end)

    it("fires multiple subscribers in registration order", function()
      local order = {}
      hooks.on("tool:completed", function()
        order[#order + 1] = "first"
      end)
      hooks.on("tool:completed", function()
        order[#order + 1] = "second"
      end)

      hooks.dispatch("tool:completed", { bufnr = 1, tool_name = "x", tool_id = "t1", status = "success" })

      assert.are.same({ "first", "second" }, order)
    end)

    it("fires subscribers before autocmd handlers", function()
      local order = {}
      hooks.on("sink:created", function()
        order[#order + 1] = "subscriber"
      end)
      track_autocmd("FlemmaSinkCreated", function()
        order[#order + 1] = "autocmd"
      end)

      hooks.dispatch("sink:created", { bufnr = 1, name = "test" })

      assert.are.same({ "subscriber", "autocmd" }, order)
    end)

    it("isolates errors between subscribers", function()
      local second_called = false
      hooks.on("boot:complete", function()
        error("subscriber exploded")
      end)
      hooks.on("boot:complete", function()
        second_called = true
      end)

      vim.cmd('silent! lua require("flemma.hooks").dispatch("boot:complete")')

      assert.is_true(second_called)
    end)

    it("continues to fire autocmd after subscriber error", function()
      hooks.on("config:updated", function()
        error("subscriber exploded")
      end)

      local autocmd_called = false
      track_autocmd("FlemmaConfigUpdated", function()
        autocmd_called = true
      end)

      vim.cmd('silent! lua require("flemma.hooks").dispatch("config:updated")')

      assert.is_true(autocmd_called)
    end)

    it("returns subscription with off() for unsubscription", function()
      local call_count = 0
      local subscription = hooks.on("conversation:idle", function()
        call_count = call_count + 1
      end)

      hooks.dispatch("conversation:idle", { bufnr = 1 })
      assert.equals(1, call_count)

      subscription:off()

      hooks.dispatch("conversation:idle", { bufnr = 1 })
      assert.equals(1, call_count)
    end)

    it("off() is idempotent", function()
      local subscription = hooks.on("request:sending", function() end)
      subscription:off()
      assert.has_no.errors(function()
        subscription:off()
      end)
    end)
  end)

  describe("new hook name transforms", function()
    it("transforms job:submitted", function()
      assert.equals("FlemmaJobSubmitted", hooks._name_to_pattern("job:submitted"))
    end)

    it("transforms autopilot:resume-scheduled", function()
      assert.equals("FlemmaAutopilotResumeScheduled", hooks._name_to_pattern("autopilot:resume-scheduled"))
    end)

    it("transforms autopilot:resume-cancelled", function()
      assert.equals("FlemmaAutopilotResumeCancelled", hooks._name_to_pattern("autopilot:resume-cancelled"))
    end)

    it("transforms autopilot:resumed", function()
      assert.equals("FlemmaAutopilotResumed", hooks._name_to_pattern("autopilot:resumed"))
    end)

    it("transforms tool:approval-required", function()
      assert.equals("FlemmaToolApprovalRequired", hooks._name_to_pattern("tool:approval-required"))
    end)
  end)

  describe("tool:approval-required hook contract", function()
    after_each(function()
      hooks._clear_subscribers()
    end)

    it("delivers batched tool data to subscribers", function()
      local received = nil
      hooks.on("tool:approval-required", function(data)
        received = data
      end)

      hooks.dispatch("tool:approval-required", {
        bufnr = 42,
        tools = {
          { tool_id = "toolu_01", tool_name = "bash", input = { command = "ls" } },
          { tool_id = "toolu_02", tool_name = "read", input = { path = "/tmp/x" } },
        },
      })

      assert.is_not_nil(received)
      assert.equals(42, received.bufnr)
      assert.equals(2, #received.tools)
      assert.equals("toolu_01", received.tools[1].tool_id)
      assert.equals("bash", received.tools[1].tool_name)
      assert.equals("ls", received.tools[1].input.command)
      assert.equals("toolu_02", received.tools[2].tool_id)
      assert.equals("read", received.tools[2].tool_name)
    end)

    it("fires User autocmd with FlemmaToolApprovalRequired pattern", function()
      local autocmd_received = nil
      track_autocmd("FlemmaToolApprovalRequired", function(ev)
        autocmd_received = ev
      end)

      hooks.dispatch("tool:approval-required", {
        bufnr = 7,
        tools = { { tool_id = "t1", tool_name = "bash", input = {} } },
      })

      assert.is_not_nil(autocmd_received)
      assert.equals(7, autocmd_received.data.bufnr)
      assert.equals(1, #autocmd_received.data.tools)
    end)
  end)
end)
