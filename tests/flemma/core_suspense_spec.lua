local notify = require("flemma.notify")

describe("core.send_to_provider suspense handling", function()
  local readiness, state, secrets_cache

  ---@return string[]
  local function truncated_example_before_lines()
    local file = io.open("tests/fixtures/tool_calling/conversation_truncated_background_jobs.chat", "r")
    assert.is_not_nil(file, "truncated background jobs fixture should exist")
    ---@cast file file*
    local lines = {}
    for line in file:lines() do
      lines[#lines + 1] = line
    end
    file:close()
    return lines
  end

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.commands"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.tools.approval"] = nil
    package.loaded["flemma.tools.executor"] = nil
    package.loaded["flemma.tools.registry"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.readiness"] = nil
    package.loaded["flemma.secrets"] = nil
    package.loaded["flemma.secrets.cache"] = nil
    package.loaded["flemma.provider.normalize"] = nil
    package.loaded["flemma.provider.registry"] = nil

    local flemma = require("flemma")
    flemma.setup({ parameters = { thinking = false } })

    readiness = require("flemma.readiness")
    state = require("flemma.state")
    secrets_cache = require("flemma.secrets.cache")

    readiness._reset_for_tests()
    secrets_cache.invalidate_all()
  end)

  after_each(function()
    notify._reset_impl()
    require("flemma.client").clear_fixtures()
    vim.cmd("silent! %bdelete!")
  end)

  it("re-raises suspense from get_api_key past the prep pcall", function()
    local boundary = readiness.get_or_create_boundary("test:suspense", function(done)
      done()
    end)
    local raised = false
    local ok, err = pcall(function()
      local prep_ok, prep_result = pcall(function()
        error(readiness.Suspense.new("test", boundary))
      end)
      if not prep_ok then
        if readiness.is_suspense(prep_result) then
          raised = true
          error(prep_result)
        end
        error(prep_result)
      end
    end)
    assert.is_true(raised)
    assert.is_false(ok)
    assert.is_true(readiness.is_suspense(err))
  end)

  it("queues send behind suspense when credentials are uncached", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "Hello" })
    vim.bo[bufnr].filetype = "chat"

    notify._set_impl(function(n)
      return n
    end)

    require("flemma.core").send_to_provider()

    local buffer_state = state.get_buffer_state(bufnr)
    assert.is_not_nil(buffer_state.pending_send, "expected pending_send to be set after suspense")
    assert.is_not_nil(buffer_state.pending_send.subscription, "expected subscription on pending_send")
  end)

  it("cancels pending_send on Ctrl+C", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "Hello" })
    vim.bo[bufnr].filetype = "chat"

    notify._set_impl(function(n)
      return n
    end)
    require("flemma.core").send_to_provider()

    local buffer_state = state.get_buffer_state(bufnr)
    assert.is_not_nil(buffer_state.pending_send)
    local sub = buffer_state.pending_send.subscription

    require("flemma.core").cancel_request({ bufnr = bufnr })

    assert.is_nil(buffer_state.pending_send)
    assert.is_true(sub.cancelled)
    assert.is_false(buffer_state.locked)
  end)

  it("cleans up pending_send via cleanup_buffer_state", function()
    require("flemma.core")

    local bufnr = vim.api.nvim_create_buf(false, false)
    state.get_buffer_state(bufnr)

    local boundary = readiness.get_or_create_boundary("test:wipe", function() end)
    local sub = boundary:subscribe(function() end)
    local buffer_state = state.get_buffer_state(bufnr)
    buffer_state.pending_send = { subscription = sub, opts = {} }

    state.cleanup_buffer_state(bufnr)

    assert.is_true(sub.cancelled)
  end)

  it("queues Phase 2 behind tool-definition suspense for a truncated real chat buffer", function()
    local tools = require("flemma.tools")
    local registry = require("flemma.tools.registry")
    local approval = require("flemma.tools.approval")

    approval.register("test:auto-approve-all", {
      priority = 200,
      resolve = function()
        return "approve"
      end,
    })

    local async_done
    tools.register_async(function(_register, done)
      async_done = done
    end)

    registry.register("calculator_async", {
      name = "calculator_async",
      description = "Test calculator",
      async = false,
      input_schema = {
        type = "object",
        properties = {
          expression = { type = "string" },
          delay = { type = "number" },
        },
      },
      execute = function(input)
        local expression = input.expression
        if expression == "2 + 2" then
          return { success = true, output = "4" }
        end
        if expression == "4 + 4" then
          return { success = true, output = "8" }
        end
        return { success = false, error = "unexpected expression: " .. tostring(expression) }
      end,
    })

    registry.register("bash", {
      name = "bash",
      description = "Test bash",
      async = true,
      backgroundable = true,
      input_schema = {
        type = "object",
        properties = {
          label = { type = "string" },
          command = { type = "string" },
          timeout = { type = "number" },
        },
      },
      execute = function(_input, _ctx, callback)
        vim.schedule(function()
          callback({ success = true, output = "background output" })
        end)
        return function() end
      end,
    })

    notify._set_impl(function(n)
      return n
    end)

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, truncated_example_before_lines())
    vim.bo[bufnr].filetype = "chat"

    require("flemma.core").send_or_execute({ bufnr = bufnr })

    vim.wait(1000, function()
      return state.get_buffer_state(bufnr).pending_send ~= nil
    end)

    local buffer_state = state.get_buffer_state(bufnr)
    assert.is_not_nil(buffer_state.pending_send, "Phase 2 should queue behind tool-definition readiness")
    assert.is_nil(
      buffer_state.pending_executions and buffer_state.pending_executions["toolu_count_lua_modules"],
      "No job should be allocated before readiness is satisfied"
    )

    async_done()

    vim.wait(500, function()
      local pending = state.get_buffer_state(bufnr).pending_executions
      return pending ~= nil and pending["toolu_count_lua_modules"] ~= nil
    end)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local joined = table.concat(lines, "\n")
    assert.truthy(joined:match("%*%*Tool Result:%*%* `toolu_calc_2_plus_2`"))
    assert.truthy(joined:match("4"))
    assert.truthy(joined:match("%*%*Tool Result:%*%* `toolu_count_lua_modules` %(job=job_"))
    assert.truthy(joined:match("Running as a background job"))

    approval.unregister("test:auto-approve-all")
  end)

  -- Regression: without ensure_ready() in advance_phase2, tools provided
  -- exclusively by an async source get "Unknown tool" because tools.get()
  -- returns nil while sources are pending.
  it("waits for async source before executing tools only available from that source", function()
    local tools_mod = require("flemma.tools")
    local approval = require("flemma.tools.approval")

    approval.register("test:auto-approve-all", {
      priority = 200,
      resolve = function()
        return "approve"
      end,
    })

    local async_register, async_done
    tools_mod.register_async(function(register, done)
      async_register = register
      async_done = done
    end, { timeout = 2 })

    local error_messages = {}
    notify._set_impl(function(msg)
      table.insert(error_messages, msg)
    end)

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "Run the async tool please.",
      "",
      "@Assistant:",
      "",
      "**Tool Use:** `async_only_tool` (`toolu_async_1`)",
      "",
      "```json",
      '{"input":"hello"}',
      "```",
      "",
      "@You:",
      "",
      "**Tool Result:** `toolu_async_1` (approved)",
      "",
      "```",
      "```",
    })
    vim.bo[bufnr].filetype = "chat"

    require("flemma.core").send_or_execute({ bufnr = bufnr })

    -- Register the tool and resolve the async source immediately after.
    -- With the fix: Phase 2 suspenses via ensure_ready(), queues behind
    -- tools:loaded, then retries and executes successfully.
    -- Without the fix: Phase 2 already fired "Unknown tool" synchronously
    -- before we get here.
    async_register("async_only_tool", {
      name = "async_only_tool",
      description = "Only available after async resolution",
      input_schema = { type = "object", properties = { input = { type = "string" } } },
      execute = function()
        return { success = true, output = "async tool result" }
      end,
    })
    async_done()

    -- Let scheduled callbacks fire (suspense retry, notify dispatch)
    vim.wait(1000, function()
      return #error_messages > 0
        or table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"):match("async tool result") ~= nil
    end)

    -- Phase 2 should NOT have produced "Unknown tool" — ensure_ready() gates it
    local has_unknown_tool = false
    for _, msg in ipairs(error_messages) do
      local text = type(msg) == "table" and msg.message or tostring(msg)
      if text:match("Unknown tool") then
        has_unknown_tool = true
      end
    end
    assert.is_false(has_unknown_tool, "should not get 'Unknown tool' error while async sources are pending")

    approval.unregister("test:auto-approve-all")
  end)
end)
