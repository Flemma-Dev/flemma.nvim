--- Tests for autopilot state machine and autonomous tool execution loop

-- Clear module caches for clean state
package.loaded["flemma.autopilot"] = nil
package.loaded["flemma.tools.context"] = nil
package.loaded["flemma.state"] = nil
package.loaded["flemma.parser"] = nil

local autopilot = require("flemma.autopilot")
local context = require("flemma.tools.context")
local state = require("flemma.state")
local parser = require("flemma.parser")

--- Helper: get pending non-error tool blocks awaiting execution
---@param bufnr integer
---@return flemma.tools.ToolBlockContext[]
local function get_awaiting_execution(bufnr)
  local groups = context.resolve_all_tool_blocks(bufnr)
  local pending = groups["pending"] or {}
  local awaiting = {}
  for _, ctx in ipairs(pending) do
    if not ctx.is_error then
      table.insert(awaiting, ctx)
    end
  end
  return awaiting
end

--- Helper: create a scratch buffer with given lines
---@param lines string[]
---@return integer bufnr
local function create_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

-- ============================================================================
-- State Machine Tests
-- ============================================================================

describe("Autopilot State Machine", function()
  after_each(function()
    vim.cmd("silent! %bdelete!")
    state.set_config({})
  end)

  describe("is_enabled", function()
    it("returns true when autopilot is true in config", function()
      local bufnr = create_buffer({ "@You: test" })
      state.set_config({ tools = { autopilot = { enabled = true } } })
      assert.is_true(autopilot.is_enabled(bufnr))
    end)

    it("returns false when autopilot is false in config", function()
      local bufnr = create_buffer({ "@You: test" })
      state.set_config({ tools = { autopilot = { enabled = false } } })
      assert.is_false(autopilot.is_enabled(bufnr))
    end)

    it("returns false when autopilot group is absent", function()
      local bufnr = create_buffer({ "@You: test" })
      state.set_config({ tools = {} })
      assert.is_false(autopilot.is_enabled(bufnr))
    end)

    it("returns true when enabled field is absent (defaults to true)", function()
      local bufnr = create_buffer({ "@You: test" })
      state.set_config({ tools = { autopilot = {} } })
      assert.is_true(autopilot.is_enabled(bufnr))
    end)

    it("returns false when tools config is missing", function()
      local bufnr = create_buffer({ "@You: test" })
      state.set_config({})
      assert.is_false(autopilot.is_enabled(bufnr))
    end)
  end)

  describe("arm and disarm", function()
    it("arm sets state to armed", function()
      local bufnr = create_buffer({ "@You: test" })
      autopilot.arm(bufnr)
      assert.equals("armed", autopilot.get_state(bufnr))
      autopilot.cleanup_buffer(bufnr)
    end)

    it("disarm resets state to idle", function()
      local bufnr = create_buffer({ "@You: test" })
      autopilot.arm(bufnr)
      autopilot.disarm(bufnr)
      assert.equals("idle", autopilot.get_state(bufnr))
      autopilot.cleanup_buffer(bufnr)
    end)

    it("get_state returns idle for new buffer", function()
      local bufnr = create_buffer({ "@You: test" })
      assert.equals("idle", autopilot.get_state(bufnr))
      autopilot.cleanup_buffer(bufnr)
    end)
  end)

  describe("cleanup_buffer", function()
    it("removes buffer tracking", function()
      local bufnr = create_buffer({ "@You: test" })
      autopilot.arm(bufnr)
      assert.equals("armed", autopilot.get_state(bufnr))
      autopilot.cleanup_buffer(bufnr)
      -- After cleanup, get_state should return idle (fresh state)
      assert.equals("idle", autopilot.get_state(bufnr))
      autopilot.cleanup_buffer(bufnr)
    end)
  end)
end)

-- ============================================================================
-- on_response_complete Tests
-- ============================================================================

-- State machine unit tests: validate autopilot state transitions by
-- calling on_response_complete directly on static buffers. These test
-- the state machine logic in isolation — see "Autopilot integration"
-- for full-chain coverage via register_fixture + Flemma send.
describe("Autopilot on_response_complete", function()
  before_each(function()
    package.loaded["flemma.autopilot"] = nil
    autopilot = require("flemma.autopilot")
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
    state.set_config({})
  end)

  it("arms when last assistant message has tool_use", function()
    state.set_config({ tools = { autopilot = { enabled = true } } })
    local bufnr = create_buffer({
      "@You: Run the calculator",
      "",
      "@Assistant: Sure, let me calculate.",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: ",
    })

    autopilot.on_response_complete(bufnr)
    assert.equals("armed", autopilot.get_state(bufnr))
    autopilot.cleanup_buffer(bufnr)
  end)

  it("stays idle when last assistant message has no tool_use", function()
    state.set_config({ tools = { autopilot = { enabled = true } } })
    local bufnr = create_buffer({
      "@You: Hello",
      "",
      "@Assistant: Hi there!",
      "",
      "@You: ",
    })

    autopilot.on_response_complete(bufnr)
    assert.equals("idle", autopilot.get_state(bufnr))
    autopilot.cleanup_buffer(bufnr)
  end)

  it("does nothing when autopilot is disabled", function()
    state.set_config({ tools = { autopilot = { enabled = false } } })
    local bufnr = create_buffer({
      "@You: Run",
      "",
      "@Assistant: tool call",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: ",
    })

    autopilot.on_response_complete(bufnr)
    assert.equals("idle", autopilot.get_state(bufnr))
    autopilot.cleanup_buffer(bufnr)
  end)

  -- NOTE: Calls on_response_complete multiple times on a static buffer.
  -- In production, each call is preceded by new assistant content. This
  -- tests the iteration counter logic, not the full response cycle.
  it("increments iteration counter", function()
    state.set_config({ tools = { autopilot = { enabled = true } } })
    local bufnr = create_buffer({
      "@You: Run",
      "",
      "@Assistant: tool call",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: ",
    })

    autopilot.on_response_complete(bufnr)
    assert.equals("armed", autopilot.get_state(bufnr))

    -- Second call
    autopilot.on_response_complete(bufnr)
    assert.equals("armed", autopilot.get_state(bufnr))
    autopilot.cleanup_buffer(bufnr)
  end)

  -- NOTE: Same caveat as above — static buffer, counter-only test.
  it("stops after exceeding max_turns", function()
    state.set_config({ tools = { autopilot = { enabled = true, max_turns = 2 } } })
    local bufnr = create_buffer({
      "@You: Run",
      "",
      "@Assistant: tool call",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: ",
    })

    -- First two calls should arm
    autopilot.on_response_complete(bufnr)
    assert.equals("armed", autopilot.get_state(bufnr))
    autopilot.on_response_complete(bufnr)
    assert.equals("armed", autopilot.get_state(bufnr))

    -- Third call should exceed limit and go idle
    autopilot.on_response_complete(bufnr)
    assert.equals("idle", autopilot.get_state(bufnr))
    autopilot.cleanup_buffer(bufnr)
  end)

  -- NOTE: Tests disarm's effect on iteration counter with static buffer.
  it("disarm resets iteration counter", function()
    state.set_config({ tools = { autopilot = { enabled = true, max_turns = 2 } } })
    local bufnr = create_buffer({
      "@You: Run",
      "",
      "@Assistant: tool call",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: ",
    })

    autopilot.on_response_complete(bufnr)
    autopilot.on_response_complete(bufnr)
    -- At iteration 2, next would exceed limit
    autopilot.disarm(bufnr)
    -- After disarm, counter is reset so we can arm again
    autopilot.on_response_complete(bufnr)
    assert.equals("armed", autopilot.get_state(bufnr))
    autopilot.cleanup_buffer(bufnr)
  end)
end)

-- ============================================================================
-- on_tools_complete Tests
-- ============================================================================

describe("Autopilot on_tools_complete", function()
  before_each(function()
    package.loaded["flemma.autopilot"] = nil
    autopilot = require("flemma.autopilot")
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
    state.set_config({})
  end)

  it("sets sending when no pending or awaiting remain", function()
    state.set_config({ tools = { autopilot = { enabled = true } } })
    local bufnr = create_buffer({
      "@You: Run the calculator",
      "",
      "@Assistant: Sure.",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```",
      "4",
      "```",
    })

    autopilot.arm(bufnr)
    autopilot.on_tools_complete(bufnr)
    assert.equals("sending", autopilot.get_state(bufnr))
    autopilot.cleanup_buffer(bufnr)
  end)

  it("pauses when flemma:tool status=pending blocks remain", function()
    state.set_config({ tools = { autopilot = { enabled = true } } })
    local bufnr = create_buffer({
      "@You: Run the calculator",
      "",
      "@Assistant: Sure.",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```flemma:tool status=pending",
      "```",
    })

    autopilot.arm(bufnr)
    autopilot.on_tools_complete(bufnr)
    assert.equals("paused", autopilot.get_state(bufnr))
    autopilot.cleanup_buffer(bufnr)
  end)

  it("schedules send when flemma:tool status=approved blocks remain", function()
    state.set_config({ tools = { autopilot = { enabled = true } } })
    local bufnr = create_buffer({
      "@You: Run the calculator",
      "",
      "@Assistant: Sure.",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```flemma:tool status=approved",
      "```",
    })

    autopilot.arm(bufnr)
    autopilot.on_tools_complete(bufnr)
    assert.equals("sending", autopilot.get_state(bufnr))
    autopilot.cleanup_buffer(bufnr)
  end)

  it("no-ops when not in armed state", function()
    state.set_config({ tools = { autopilot = { enabled = true } } })
    local bufnr = create_buffer({
      "@You: Run",
      "",
      "@Assistant: Sure.",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```",
      "4",
      "```",
    })

    -- State is idle, on_tools_complete should not change it
    autopilot.on_tools_complete(bufnr)
    assert.equals("idle", autopilot.get_state(bufnr))
    autopilot.cleanup_buffer(bufnr)
  end)

  it("waits when unprocessed tool_use blocks remain", function()
    state.set_config({ tools = { autopilot = { enabled = true } } })
    local bufnr = create_buffer({
      "@You: Run both",
      "",
      "@Assistant: Two tools.",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "**Tool Use:** `bash` (`toolu_02`)",
      "```json",
      '{ "command": "echo hi" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```",
      "4",
      "```",
    })
    -- toolu_02 has no tool_result at all → resolve_all_pending returns it

    autopilot.arm(bufnr)
    autopilot.on_tools_complete(bufnr)
    -- Should stay armed because there are still pending tool_uses
    assert.equals("armed", autopilot.get_state(bufnr))
    autopilot.cleanup_buffer(bufnr)
  end)
end)

-- ============================================================================
-- Conflict Detection (has_content) Tests
-- ============================================================================

describe("Autopilot conflict detection", function()
  after_each(function()
    vim.cmd("silent! %bdelete!")
    state.set_config({})
  end)

  it("parser sets content on flemma:tool with user-edited content", function()
    local bufnr = create_buffer({
      "@Assistant: Tool call.",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```flemma:tool status=pending",
      "User typed something here",
      "```",
    })

    local doc = parser.get_parsed_document(bufnr)
    local you_msg = doc.messages[2]
    assert.equals("You", you_msg.role)
    local seg = you_msg.segments[1]
    assert.equals("tool_result", seg.kind)
    assert.equals("pending", seg.status)
    assert.equals("User typed something here", seg.content)
  end)

  it("parser sets empty content on empty flemma:tool", function()
    local bufnr = create_buffer({
      "@Assistant: Tool call.",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```flemma:tool status=approved",
      "```",
    })

    local doc = parser.get_parsed_document(bufnr)
    local you_msg = doc.messages[2]
    local seg = you_msg.segments[1]
    assert.equals("tool_result", seg.kind)
    assert.equals("approved", seg.status)
    assert.equals("", seg.content)
  end)

  it("get_awaiting_execution excludes results with user content", function()
    local bufnr = create_buffer({
      "@Assistant: Two tools.",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "**Tool Use:** `bash` (`toolu_02`)",
      "```json",
      '{ "command": "echo hi" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```flemma:tool status=pending",
      "I edited this one",
      "```",
      "",
      "**Tool Result:** `toolu_02`",
      "",
      "```flemma:tool status=pending",
      "```",
    })

    local awaiting = get_awaiting_execution(bufnr)
    -- Only toolu_02 should be returned (toolu_01 has user content)
    assert.equals(1, #awaiting)
    assert.equals("toolu_02", awaiting[1].tool_id)
  end)

  it("get_awaiting_execution returns empty when all have user content", function()
    local bufnr = create_buffer({
      "@Assistant: Tool call.",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```flemma:tool status=pending",
      "Edited content",
      "```",
    })

    local awaiting = get_awaiting_execution(bufnr)
    assert.equals(0, #awaiting)
  end)
end)

-- ============================================================================
-- All-Denied Edge Case Tests
-- ============================================================================

describe("Autopilot all-denied edge case", function()
  before_each(function()
    package.loaded["flemma.autopilot"] = nil
    autopilot = require("flemma.autopilot")
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
    state.set_config({})
  end)

  it("on_tools_complete continues after all tools denied (results injected, no pending)", function()
    state.set_config({ tools = { autopilot = { enabled = true } } })
    -- Simulate buffer state after all tools were denied: tool_results are present
    -- with error content, no flemma:tool markers
    local bufnr = create_buffer({
      "@You: Run the calculator",
      "",
      "@Assistant: Sure.",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01` (error)",
      "",
      "```",
      "The tool was denied by a policy.",
      "```",
    })

    autopilot.arm(bufnr)
    autopilot.on_tools_complete(bufnr)
    -- Should set sending since there are no pending or awaiting results
    assert.equals("sending", autopilot.get_state(bufnr))
    autopilot.cleanup_buffer(bufnr)
  end)
end)

-- ============================================================================
-- Regression: on_tools_complete ignored when not armed
-- ============================================================================

describe("Autopilot on_tools_complete ignored when not armed", function()
  before_each(function()
    package.loaded["flemma.autopilot"] = nil
    autopilot = require("flemma.autopilot")
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
    state.set_config({})
  end)

  it("on_tools_complete does not advance from paused state", function()
    -- Regression: if autopilot is paused (e.g., pending tools shown to user)
    -- and a tool completion fires, it should not advance the state.
    state.set_config({ tools = { autopilot = { enabled = true } } })
    local bufnr = create_buffer({
      "@You: Run",
      "",
      "@Assistant: Sure.",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```",
      "4",
      "```",
    })

    -- Manually set paused state (as advance_phase2 would for pending blocks)
    autopilot.arm(bufnr)
    -- Simulate: on_tools_complete fires from a pending block, pauses
    -- Then we verify it stays paused
    -- First, create a scenario where on_tools_complete would be called from
    -- paused state (e.g., a lingering callback)
    -- Force paused via on_tools_complete seeing pending blocks
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You: Run",
      "",
      "@Assistant: Sure.",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```flemma:tool status=pending",
      "```",
    })
    autopilot.on_tools_complete(bufnr)
    assert.equals("paused", autopilot.get_state(bufnr))

    -- Now replace the buffer to have the tool resolved
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You: Run",
      "",
      "@Assistant: Sure.",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```",
      "4",
      "```",
    })

    -- on_tools_complete from paused state should be a no-op
    autopilot.on_tools_complete(bufnr)
    assert.equals("paused", autopilot.get_state(bufnr))
    autopilot.cleanup_buffer(bufnr)
  end)

  it("on_tools_complete advances from armed state after re-arm", function()
    -- Regression: after pausing on pending, user interacts (e.g., Alt+Enter),
    -- which re-arms autopilot. Now on_tools_complete should advance.
    state.set_config({ tools = { autopilot = { enabled = true } } })
    local bufnr = create_buffer({
      "@You: Run",
      "",
      "@Assistant: Sure.",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```",
      "4",
      "```",
    })

    -- Simulate: was paused, then re-armed by execute_at_cursor
    autopilot.arm(bufnr)
    autopilot.on_tools_complete(bufnr)
    -- All tools resolved → should set sending
    assert.equals("sending", autopilot.get_state(bufnr))
    autopilot.cleanup_buffer(bufnr)
  end)
end)

-- ============================================================================
-- Regression: all-sync tools leave autopilot stuck at armed (Bug 2)
-- ============================================================================

describe("Autopilot all-sync tool completion", function()
  -- Bug 2: When all approved tools are synchronous, they complete inline
  -- during the advance_phase2 loop. on_tools_complete fires before arm(),
  -- so it's ignored. After the loop, arm() sets state to "armed" but nothing
  -- ever calls on_tools_complete again → stuck.
  --
  -- Fix: advance_phase2 checks executor.has_pending() after arming. If false
  -- (all sync completed), it schedules on_tools_complete manually.

  before_each(function()
    package.loaded["flemma.autopilot"] = nil
    autopilot = require("flemma.autopilot")
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
    state.set_config({})
  end)

  it("on_tools_complete called before arm is ignored", function()
    state.set_config({ tools = { autopilot = { enabled = true } } })
    local bufnr = create_buffer({
      "@You: Run",
      "",
      "@Assistant: Sure.",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```",
      "4",
      "```",
    })

    -- State is idle (not armed) — on_tools_complete should be ignored
    autopilot.on_tools_complete(bufnr)
    assert.equals("idle", autopilot.get_state(bufnr))

    -- Now arm and verify on_tools_complete works
    autopilot.arm(bufnr)
    autopilot.on_tools_complete(bufnr)
    assert.equals("sending", autopilot.get_state(bufnr))
    autopilot.cleanup_buffer(bufnr)
  end)

  it("executor.has_pending returns false when no tools executing", function()
    package.loaded["flemma.tools.executor"] = nil
    local executor = require("flemma.tools.executor")
    local bufnr = create_buffer({ "@You: test" })
    -- No tools dispatched → has_pending should be false
    assert.is_false(executor.has_pending(bufnr))
  end)
end)

-- ============================================================================
-- Integration Tests (fixture-driven full chain)
-- ============================================================================

describe("Autopilot integration", function()
  local client = require("flemma.client")
  local flemma_mod

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.core.config.manager"] = nil
    package.loaded["flemma.provider.registry"] = nil
    package.loaded["flemma.models"] = nil
    package.loaded["flemma.autopilot"] = nil

    flemma_mod = require("flemma")
    require("flemma.core")
    autopilot = require("flemma.autopilot")

    flemma_mod.setup({
      parameters = { thinking = false },
      tools = { autopilot = { enabled = true } },
    })
  end)

  after_each(function()
    client.clear_fixtures()
    vim.cmd("silent! %bdelete!")
    state.set_config({})
  end)

  it("arms autopilot when LLM response contains tool_use via full chain", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You: Calculate 15 * 7" })

    client.register_fixture("api%.anthropic%.com", "tests/fixtures/tool_calling/anthropic_tool_use_streaming.txt")
    vim.cmd("Flemma send")

    -- Wait for response to complete (tool_use block appears + @You: prompt)
    vim.wait(2000, function()
      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for _, line in ipairs(buf_lines) do
        if line == "@You: " then
          return true
        end
      end
      return false
    end)

    local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(buf_lines, "\n")

    -- Buffer should contain tool_use block
    assert.truthy(content:match("%*%*Tool Use:%*%*"), "Should have tool_use in buffer")

    -- Autopilot should have been armed by on_response_complete
    local ap_state = autopilot.get_state(bufnr)
    assert.truthy(
      ap_state == "armed" or ap_state == "paused" or ap_state == "sending",
      "Autopilot should have advanced past idle, got: " .. ap_state
    )
  end)
end)
