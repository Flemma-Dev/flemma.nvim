describe("background lifecycle", function()
  local executor
  local state

  before_each(function()
    package.loaded["flemma.tools.executor"] = nil
    package.loaded["flemma.state"] = nil
    executor = require("flemma.tools.executor")
    state = require("flemma.state")
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
        "**Tool Result:** `tool_01` (job=job_lost1)",
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
      assert.truthy(joined:match("%*%*Job Result:%*%*%s*`job_lost1`%s*%(error%)"))
      assert.truthy(joined:match("Job lost: session ended before completion"))
      assert.truthy(joined:match("%*%*Tool Result:%*%*%s*`tool_01`%s*%(error job=job_lost1%)"))
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
        "**Tool Result:** `tool_01` (job=job_done1)",
        "",
        "```",
        "Running in background.",
        "```",
        "",
        "@You:",
        "**Job Result:** `job_done1`",
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
        "**Tool Result:** `tool_01` (job=job_run1)",
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
          job_id = "job_run1",
        },
      }

      local count = executor.resolve_orphaned_jobs(bufnr)
      assert.equals(0, count)

      buffer_state.pending_executions = nil
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  -- ==========================================================================
  -- cancel_all tests
  -- ==========================================================================

  describe("cancel_all", function()
    -- cancel_all calls autopilot.disarm internally via the executor module's
    -- own captured require("flemma.autopilot"). To observe the state transition,
    -- clear all modules and reload executor last so its autopilot reference
    -- matches the instance the test asserts on.
    local autopilot
    local config_facade

    before_each(function()
      package.loaded["flemma.tools.executor"] = nil
      package.loaded["flemma.autopilot"] = nil
      package.loaded["flemma.state"] = nil
      package.loaded["flemma.config"] = nil
      package.loaded["flemma.config.store"] = nil
      package.loaded["flemma.config.proxy"] = nil
      package.loaded["flemma.config.schema"] = nil

      config_facade = require("flemma.config")
      local config_schema = require("flemma.config.schema")
      config_facade.init(config_schema)
      config_facade.apply(config_facade.LAYERS.SETUP, { tools = { autopilot = { enabled = true } } })

      -- Reload executor AFTER config/autopilot so its internal references are current
      autopilot = require("flemma.autopilot")
      state = require("flemma.state")
      executor = require("flemma.tools.executor")
    end)

    it("cancels foreground tools but skips completed entries", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "**Tool Use:** `bash` (`tool_active`)",
        "",
        "```json",
        '{"command": "sleep 10"}',
        "```",
        "",
        "**Tool Use:** `bash` (`tool_done`)",
        "",
        "```json",
        '{"command": "echo done"}',
        "```",
        "",
        "@You:",
        "**Tool Result:** `tool_active`",
        "",
        "```",
        "```",
        "",
        "**Tool Result:** `tool_done`",
        "",
        "```",
        "already finished",
        "```",
      })
      vim.bo[bufnr].filetype = "chat"

      local cancel_called = false
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_active"] = {
          tool_id = "tool_active",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 2,
          end_line = 6,
          started_at = 0,
          completed = false,
          placeholder_modified = false,
          cancel_fn = function()
            cancel_called = true
          end,
        },
        ["tool_done"] = {
          tool_id = "tool_done",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 8,
          end_line = 12,
          started_at = 0,
          completed = true,
          placeholder_modified = false,
        },
      }

      autopilot.arm(bufnr)
      assert.equals("armed", autopilot.get_state(bufnr))

      executor.cancel_all(bufnr)

      -- The active entry's cancel_fn should have been called
      assert.is_true(cancel_called, "cancel_fn should have been invoked for the active entry")

      -- Autopilot should be disarmed after cancel_all
      assert.equals("idle", autopilot.get_state(bufnr))

      autopilot.cleanup_buffer(bufnr)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("handles empty pending_executions gracefully", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "hello" })
      vim.bo[bufnr].filetype = "chat"

      -- No pending_executions set at all — cancel_all should not error
      assert.has_no.errors(function()
        executor.cancel_all(bufnr)
      end)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)

-- ============================================================================
-- Autopilot background awareness tests
-- ============================================================================

describe("autopilot background awareness", function()
  local autopilot
  local config_facade
  local config_schema
  local state

  before_each(function()
    package.loaded["flemma.tools.executor"] = nil
    package.loaded["flemma.autopilot"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.schema"] = nil
    package.loaded["flemma"] = nil

    config_facade = require("flemma.config")
    config_schema = require("flemma.config.schema")
    autopilot = require("flemma.autopilot")
    state = require("flemma.state")
    config_facade.init(config_schema)
    config_facade.apply(config_facade.LAYERS.SETUP, { tools = { autopilot = { enabled = true } } })
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  it("on_response_complete stays idle when only background tools are pending", function()
    -- Buffer: assistant message with NO tool_use segments (text-only reply).
    -- State has a background pending_execution (job_id present).
    -- Autopilot should stay idle — background tools do not trigger arming.
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "What is the status?",
      "",
      "@Assistant:",
      "Here is your answer.",
    })

    -- Seed a background pending_execution from a prior turn
    local buffer_state = state.get_buffer_state(bufnr)
    buffer_state.pending_executions = {
      ["tool_bg"] = {
        tool_id = "tool_bg",
        tool_name = "bash",
        bufnr = bufnr,
        start_line = 1,
        end_line = 5,
        started_at = 0,
        completed = false,
        placeholder_modified = false,
        job_id = "job_abc123",
      },
    }

    autopilot.on_response_complete(bufnr)
    assert.equals("idle", autopilot.get_state(bufnr))

    autopilot.cleanup_buffer(bufnr)
  end)

  it("on_response_complete transitions sending to idle when no tool_use in response", function()
    -- Buffer: assistant message with no tool_use.
    -- Autopilot state is "sending" (from a previous on_tools_complete).
    -- on_response_complete sees no tool_use → transitions to idle.
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "Hello",
      "",
      "@Assistant:",
      "Done! No more tools needed.",
    })

    -- Force autopilot into "sending" state as if on_tools_complete triggered a send
    local buffer_state = state.get_buffer_state(bufnr)
    buffer_state.autopilot = { state = "sending", iteration = 1 }

    autopilot.on_response_complete(bufnr)
    assert.equals("idle", autopilot.get_state(bufnr))

    autopilot.cleanup_buffer(bufnr)
  end)

  it("on_response_complete arms when tool_use present regardless of background entries", function()
    -- Buffer: assistant message WITH a tool_use segment.
    -- State has a background pending_execution.
    -- on_response_complete should arm — tool_use presence always triggers arming.
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "Do more work",
      "",
      "@Assistant:",
      "Let me run another tool.",
      "",
      "**Tool Use:** `calculator` (`toolu_fg`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You:",
      "",
    })

    -- Seed a background pending_execution from a prior turn
    local buffer_state = state.get_buffer_state(bufnr)
    buffer_state.pending_executions = {
      ["tool_bg"] = {
        tool_id = "tool_bg",
        tool_name = "bash",
        bufnr = bufnr,
        start_line = 1,
        end_line = 5,
        started_at = 0,
        completed = false,
        placeholder_modified = false,
        job_id = "job_xyz456",
      },
    }

    autopilot.on_response_complete(bufnr)
    assert.equals("armed", autopilot.get_state(bufnr))

    autopilot.cleanup_buffer(bufnr)
  end)
end)
