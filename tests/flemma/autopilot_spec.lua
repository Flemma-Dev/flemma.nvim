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

  it("pauses when flemma:pending placeholders remain", function()
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
      "```flemma:pending",
      "```",
    })

    autopilot.arm(bufnr)
    autopilot.on_tools_complete(bufnr)
    assert.equals("paused", autopilot.get_state(bufnr))
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

  it("parser sets has_content on flemma:pending with content", function()
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
      "```flemma:pending",
      "User typed something here",
      "```",
    })

    local doc = parser.get_parsed_document(bufnr)
    local you_msg = doc.messages[2]
    assert.equals("You", you_msg.role)
    local seg = you_msg.segments[1]
    assert.equals("tool_result", seg.kind)
    assert.is_true(seg.pending)
    assert.is_true(seg.has_content)
  end)

  it("parser does not set has_content on empty flemma:pending", function()
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
      "```flemma:pending",
      "```",
    })

    local doc = parser.get_parsed_document(bufnr)
    local you_msg = doc.messages[2]
    local seg = you_msg.segments[1]
    assert.equals("tool_result", seg.kind)
    assert.is_true(seg.pending)
    assert.is_nil(seg.has_content)
  end)

  it("resolve_all_awaiting_execution excludes results with user content", function()
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
      "```flemma:pending",
      "I edited this one",
      "```",
      "",
      "**Tool Result:** `toolu_02`",
      "",
      "```flemma:pending",
      "```",
    })

    local awaiting = context.resolve_all_awaiting_execution(bufnr)
    -- Only toolu_02 should be returned (toolu_01 has user content)
    assert.equals(1, #awaiting)
    assert.equals("toolu_02", awaiting[1].tool_id)
  end)

  it("resolve_all_awaiting_execution returns empty when all have user content", function()
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
      "```flemma:pending",
      "Edited content",
      "```",
    })

    local awaiting = context.resolve_all_awaiting_execution(bufnr)
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
    -- with error content, no flemma:pending markers
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
      "Denied by auto_approve policy",
      "```",
    })

    autopilot.arm(bufnr)
    autopilot.on_tools_complete(bufnr)
    -- Should set sending since there are no pending or awaiting results
    assert.equals("sending", autopilot.get_state(bufnr))
    autopilot.cleanup_buffer(bufnr)
  end)
end)
