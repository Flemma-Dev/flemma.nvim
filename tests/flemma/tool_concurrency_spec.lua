--- Tests for tool execution concurrency limiting
--- Covers: count_running slot accounting, max_concurrent gating in advance_phase2

-- Clear module caches for clean state
package.loaded["flemma"] = nil
package.loaded["flemma.commands"] = nil
package.loaded["flemma.state"] = nil
package.loaded["flemma.tools"] = nil
package.loaded["flemma.tools.executor"] = nil
package.loaded["flemma.tools.registry"] = nil
package.loaded["flemma.core"] = nil
package.loaded["flemma.provider.normalize"] = nil
package.loaded["flemma.bridge"] = nil
package.loaded["flemma.provider.registry"] = nil
package.loaded["flemma.models"] = nil
package.loaded["flemma.autopilot"] = nil
package.loaded["flemma.config"] = nil
package.loaded["flemma.config.store"] = nil
package.loaded["flemma.config.proxy"] = nil
package.loaded["flemma.config.schema.definition"] = nil

local stub = require("luassert.stub")
local config_facade = require("flemma.config")
local schema = require("flemma.config.schema.definition")
local state = require("flemma.state")
local executor = require("flemma.tools.executor")
local tool_context = require("flemma.tools.context")
local registry = require("flemma.tools.registry")

--- Helper: create a scratch buffer with given lines
---@param lines string[]
---@return integer bufnr
local function create_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

--- Helper: count approved tool blocks remaining in a buffer
---@param bufnr integer
---@return integer
local function count_approved_blocks(bufnr)
  local groups = tool_context.resolve_all_tool_blocks(bufnr)
  return #(groups["approved"] or {})
end

--- Register a minimal sync calculator tool for testing
local function register_calculator()
  registry.register("calculator", {
    name = "calculator",
    description = "Evaluates a mathematical expression",
    input_schema = {
      type = "object",
      properties = {
        expression = { type = "string", description = "Math expression" },
      },
      required = { "expression" },
      additionalProperties = false,
    },
    execute = function(input)
      local fn, err = load("return " .. input.expression, "calc", "t", { math = math })
      if not fn then
        return { success = false, error = "Invalid expression: " .. err }
      end
      local ok, result = pcall(fn)
      if not ok then
        return { success = false, error = "Evaluation failed: " .. result }
      end
      return { success = true, output = tostring(result) }
    end,
  })
end

-- ============================================================================
-- count_running slot accounting
-- ============================================================================

describe("Tool concurrency count_running", function()
  after_each(function()
    vim.cmd("silent! %bdelete!")
    config_facade.init(schema)
  end)

  it("returns 0 when no tools are executing", function()
    local bufnr = create_buffer({ "@You:", "test" })
    assert.equals(0, executor.count_running(bufnr))
  end)

  it("counts entries in pending_executions", function()
    local bufnr = create_buffer({ "@You:", "test" })
    local buffer_state = state.get_buffer_state(bufnr)
    buffer_state.pending_executions = {
      ["toolu_01"] = { tool_id = "toolu_01", completed = false },
      ["toolu_02"] = { tool_id = "toolu_02", completed = false },
    }
    assert.equals(2, executor.count_running(bufnr))
  end)

  it("includes completed-but-not-cleaned-up entries", function()
    local bufnr = create_buffer({ "@You:", "test" })
    local buffer_state = state.get_buffer_state(bufnr)
    buffer_state.pending_executions = {
      ["toolu_01"] = { tool_id = "toolu_01", completed = true },
      ["toolu_02"] = { tool_id = "toolu_02", completed = false },
    }
    -- Both count — completed-but-not-cleaned-up still occupies a slot
    assert.equals(2, executor.count_running(bufnr))
  end)
end)

-- ============================================================================
-- Phase 2 concurrency gating
-- ============================================================================

-- These tests validate the concurrency gate by pre-populating
-- pending_executions to simulate already-running tools, then calling
-- send_or_execute on a buffer with approved tool blocks. The gate should
-- prevent execution when slots are full.
--
-- We register a minimal sync calculator tool because it completes inline —
-- this lets us verify execution happened by checking if the approved block
-- was replaced with a result.

describe("Tool concurrency gating in Phase 2", function()
  local core

  before_each(function()
    core = require("flemma.core")
    register_calculator()
    config_facade.init(schema)
    config_facade.apply(config_facade.LAYERS.SETUP, {
      parameters = { thinking = false },
      tools = {
        max_concurrent = 2,
        autopilot = { enabled = false },
      },
    })
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
    config_facade.init(schema)
  end)

  it("skips approved tools when running count reaches max_concurrent", function()
    -- Buffer has 1 approved block. Pre-populate 2 running tools to fill slots.
    local bufnr = create_buffer({
      "@Assistant:",
      "Running a tool.",
      "",
      "**Tool Use:** `calculator` (`toolu_03`)",
      "```json",
      '{ "expression": "1+1" }',
      "```",
      "",
      "@You:",
      "**Tool Result:** `toolu_03`",
      "",
      "```flemma:tool status=approved",
      "```",
    })

    -- Simulate 2 tools already running (fills max_concurrent=2)
    local buffer_state = state.get_buffer_state(bufnr)
    buffer_state.pending_executions = {
      ["toolu_01"] = {
        tool_id = "toolu_01",
        tool_name = "bash",
        bufnr = bufnr,
        completed = false,
        started_at = os.time(),
        placeholder_modified = false,
        start_line = 0,
        end_line = 0,
      },
      ["toolu_02"] = {
        tool_id = "toolu_02",
        tool_name = "bash",
        bufnr = bufnr,
        completed = false,
        started_at = os.time(),
        placeholder_modified = false,
        start_line = 0,
        end_line = 0,
      },
    }

    -- Phase 2 should skip toolu_03 because slots are full
    core.send_or_execute({ bufnr = bufnr })

    -- The approved block should still be approved (not executed)
    assert.equals(1, count_approved_blocks(bufnr))
  end)

  it("executes approved tools when slots are available", function()
    -- Buffer has 1 approved calculator block. No tools running. Should execute.
    local bufnr = create_buffer({
      "@Assistant:",
      "Running a tool.",
      "",
      "**Tool Use:** `calculator` (`toolu_03`)",
      "```json",
      '{ "expression": "1+1" }',
      "```",
      "",
      "@You:",
      "**Tool Result:** `toolu_03`",
      "",
      "```flemma:tool status=approved",
      "```",
    })

    core.send_or_execute({ bufnr = bufnr })

    -- Calculator is sync — approved block should be consumed (replaced with result)
    assert.equals(0, count_approved_blocks(bufnr))
  end)

  it("executes all approved tools when max_concurrent=0 (unlimited)", function()
    -- Override config to unlimited
    config_facade.apply(config_facade.LAYERS.SETUP, { tools = { max_concurrent = 0 } })

    -- Pre-populate 5 running tools — with unlimited, this shouldn't block anything
    local bufnr = create_buffer({
      "@Assistant:",
      "Running a tool.",
      "",
      "**Tool Use:** `calculator` (`toolu_06`)",
      "```json",
      '{ "expression": "3+3" }',
      "```",
      "",
      "@You:",
      "**Tool Result:** `toolu_06`",
      "",
      "```flemma:tool status=approved",
      "```",
    })

    local buffer_state = state.get_buffer_state(bufnr)
    buffer_state.pending_executions = {
      ["toolu_01"] = {
        tool_id = "toolu_01",
        tool_name = "bash",
        bufnr = bufnr,
        completed = false,
        started_at = os.time(),
        placeholder_modified = false,
        start_line = 0,
        end_line = 0,
      },
      ["toolu_02"] = {
        tool_id = "toolu_02",
        tool_name = "bash",
        bufnr = bufnr,
        completed = false,
        started_at = os.time(),
        placeholder_modified = false,
        start_line = 0,
        end_line = 0,
      },
      ["toolu_03"] = {
        tool_id = "toolu_03",
        tool_name = "bash",
        bufnr = bufnr,
        completed = false,
        started_at = os.time(),
        placeholder_modified = false,
        start_line = 0,
        end_line = 0,
      },
      ["toolu_04"] = {
        tool_id = "toolu_04",
        tool_name = "bash",
        bufnr = bufnr,
        completed = false,
        started_at = os.time(),
        placeholder_modified = false,
        start_line = 0,
        end_line = 0,
      },
      ["toolu_05"] = {
        tool_id = "toolu_05",
        tool_name = "bash",
        bufnr = bufnr,
        completed = false,
        started_at = os.time(),
        placeholder_modified = false,
        start_line = 0,
        end_line = 0,
      },
    }

    core.send_or_execute({ bufnr = bufnr })

    -- Calculator is sync — should execute despite 5 running tools
    assert.equals(0, count_approved_blocks(bufnr))
  end)

  it("stops mid-loop after consuming max_concurrent slots with 4 approved blocks", function()
    -- Register a blocking async tool whose callback is never invoked.
    -- Each execution adds a slot to pending_executions and never cleans it up,
    -- so count_running increments with each execution. After 2 executions
    -- count_running reaches max_concurrent=2 and the loop breaks, leaving the
    -- remaining 2 blocks with status=approved.
    registry.register("blocking", {
      name = "blocking",
      description = "Async tool that never completes (for concurrency testing)",
      async = true,
      input_schema = {
        type = "object",
        properties = {},
        additionalProperties = false,
      },
      execute = function(_input, _context, _callback)
        -- Intentionally never call _callback so the slot stays occupied
      end,
    })

    local bufnr = create_buffer({
      "@Assistant:",
      "Running tools.",
      "",
      "**Tool Use:** `blocking` (`toolu_11`)",
      "```json",
      "{}",
      "```",
      "",
      "**Tool Use:** `blocking` (`toolu_12`)",
      "```json",
      "{}",
      "```",
      "",
      "**Tool Use:** `blocking` (`toolu_13`)",
      "```json",
      "{}",
      "```",
      "",
      "**Tool Use:** `blocking` (`toolu_14`)",
      "```json",
      "{}",
      "```",
      "",
      "@You:",
      "**Tool Result:** `toolu_11`",
      "",
      "```flemma:tool status=approved",
      "```",
      "",
      "**Tool Result:** `toolu_12`",
      "",
      "```flemma:tool status=approved",
      "```",
      "",
      "**Tool Result:** `toolu_13`",
      "",
      "```flemma:tool status=approved",
      "```",
      "",
      "**Tool Result:** `toolu_14`",
      "",
      "```flemma:tool status=approved",
      "```",
    })

    core.send_or_execute({ bufnr = bufnr })

    -- After 2 async executions count_running equals max_concurrent=2 and the loop
    -- breaks. Exactly 2 slots are occupied (the two dispatched blocking tools).
    -- The remaining 2 tools were never dispatched — not present in pending_executions.
    assert.equals(2, executor.count_running(bufnr))
    local buffer_state = state.get_buffer_state(bufnr)
    assert.is_nil(buffer_state.pending_executions["toolu_13"], "toolu_13 should not have been dispatched")
    assert.is_nil(buffer_state.pending_executions["toolu_14"], "toolu_14 should not have been dispatched")
  end)

  it("notifies when throttled and user_initiated is true, silent otherwise", function()
    -- Scenario: 1 approved block, 2 slots pre-filled so the gate fires immediately
    -- (0 tools execute, 1 is throttled). With user_initiated=true a notification fires.

    local function make_throttled_buffer()
      local bufnr = create_buffer({
        "@Assistant:",
        "Running a tool.",
        "",
        "**Tool Use:** `calculator` (`toolu_21`)",
        "```json",
        '{ "expression": "5+5" }',
        "```",
        "",
        "@You:",
        "**Tool Result:** `toolu_21`",
        "",
        "```flemma:tool status=approved",
        "```",
      })
      -- Fill both concurrency slots so the gate fires on the very first approved block
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["toolu_31"] = {
          tool_id = "toolu_31",
          tool_name = "bash",
          bufnr = bufnr,
          completed = false,
          started_at = os.time(),
          placeholder_modified = false,
          start_line = 0,
          end_line = 0,
        },
        ["toolu_32"] = {
          tool_id = "toolu_32",
          tool_name = "bash",
          bufnr = bufnr,
          completed = false,
          started_at = os.time(),
          placeholder_modified = false,
          start_line = 0,
          end_line = 0,
        },
      }
      return bufnr
    end

    -- Case 1: user_initiated=true — expect a throttle notification
    local notify_spy = stub(vim, "notify")
    local bufnr_initiated = make_throttled_buffer()
    core.send_or_execute({ bufnr = bufnr_initiated, user_initiated = true })

    local throttle_seen = false
    for _, call in ipairs(notify_spy.calls) do
      local msg = call.refs[1]
      if msg and msg:match("Executing") and msg:match("max_concurrent") then
        throttle_seen = true
      end
    end
    assert.is_true(throttle_seen, "Expected throttle notification when user_initiated=true")
    notify_spy:revert()

    -- Case 2: user_initiated omitted — throttle notification must NOT fire
    local notify_spy2 = stub(vim, "notify")
    local bufnr_silent = make_throttled_buffer()
    core.send_or_execute({ bufnr = bufnr_silent })

    local throttle_seen_silent = false
    for _, call in ipairs(notify_spy2.calls) do
      local msg = call.refs[1]
      if msg and msg:match("Executing") and msg:match("max_concurrent") then
        throttle_seen_silent = true
      end
    end
    assert.is_false(throttle_seen_silent, "Expected no throttle notification when user_initiated is nil")
    notify_spy2:revert()
  end)
end)
