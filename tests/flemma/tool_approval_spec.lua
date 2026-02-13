--- Tests for tool execution approval flow
--- Covers: approval resolver, flemma:pending marker, awaiting execution detection

-- Clear module caches for clean state
package.loaded["flemma.tools.approval"] = nil
package.loaded["flemma.tools.context"] = nil
package.loaded["flemma.tools.injector"] = nil
package.loaded["flemma.state"] = nil
package.loaded["flemma.parser"] = nil

local approval = require("flemma.tools.approval")
local context = require("flemma.tools.context")
local injector = require("flemma.tools.injector")
local state = require("flemma.state")
local parser = require("flemma.parser")

--- Helper: create a scratch buffer with given lines
--- @param lines string[]
--- @return integer bufnr
local function create_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

--- Helper: get buffer lines as table
--- @param bufnr integer
--- @return string[]
local function get_lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

-- ============================================================================
-- Approval Resolver Tests
-- ============================================================================

describe("Approval Resolver", function()
  after_each(function()
    state.set_config({})
  end)

  describe("with no auto_approve configured", function()
    it("returns require_approval when auto_approve is nil", function()
      state.set_config({ tools = { require_approval = true } })
      local result = approval.resolve("bash", { command = "ls" }, { bufnr = 1, tool_id = "t1" })
      assert.equals("require_approval", result)
    end)

    it("returns require_approval when tools config is empty", function()
      state.set_config({ tools = {} })
      local result = approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" })
      assert.equals("require_approval", result)
    end)

    it("returns require_approval when config is empty", function()
      state.set_config({})
      local result = approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" })
      assert.equals("require_approval", result)
    end)
  end)

  describe("with string list auto_approve", function()
    it("returns approve for listed tools", function()
      state.set_config({ tools = { auto_approve = { "calculator", "read" } } })
      assert.equals("approve", approval.resolve("calculator", {}, { bufnr = 1, tool_id = "t1" }))
      assert.equals("approve", approval.resolve("read", {}, { bufnr = 1, tool_id = "t2" }))
    end)

    it("returns require_approval for unlisted tools", function()
      state.set_config({ tools = { auto_approve = { "calculator" } } })
      assert.equals(
        "require_approval",
        approval.resolve("bash", { command = "rm -rf /" }, { bufnr = 1, tool_id = "t1" })
      )
    end)

    it("returns require_approval for empty list", function()
      state.set_config({ tools = { auto_approve = {} } })
      assert.equals("require_approval", approval.resolve("calculator", {}, { bufnr = 1, tool_id = "t1" }))
    end)
  end)

  describe("with function auto_approve", function()
    it("returns approve when function returns true", function()
      state.set_config({
        tools = {
          auto_approve = function()
            return true
          end,
        },
      })
      assert.equals("approve", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
    end)

    it("returns require_approval when function returns false", function()
      state.set_config({
        tools = {
          auto_approve = function()
            return false
          end,
        },
      })
      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
    end)

    it("returns require_approval when function returns nil", function()
      state.set_config({
        tools = {
          auto_approve = function() end,
        },
      })
      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
    end)

    it("returns deny when function returns 'deny'", function()
      state.set_config({
        tools = {
          auto_approve = function()
            return "deny"
          end,
        },
      })
      assert.equals("deny", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
    end)

    it("passes tool_name, input, and context to function", function()
      local captured = {}
      state.set_config({
        tools = {
          auto_approve = function(tool_name, input, ctx)
            captured.tool_name = tool_name
            captured.input = input
            captured.context = ctx
            return false
          end,
        },
      })

      local input = { command = "echo hello" }
      local ctx = { bufnr = 42, tool_id = "toolu_abc" }
      approval.resolve("bash", input, ctx)

      assert.equals("bash", captured.tool_name)
      assert.same(input, captured.input)
      assert.same(ctx, captured.context)
    end)

    it("supports argument-based approval logic", function()
      state.set_config({
        tools = {
          auto_approve = function(tool_name, input)
            if tool_name == "calculator" then
              return true
            end
            if tool_name == "bash" and input.command and input.command:match("^ls") then
              return true
            end
            if tool_name == "bash" and input.command and input.command:match("rm%s+%-rf") then
              return "deny"
            end
            return false
          end,
        },
      })

      assert.equals("approve", approval.resolve("calculator", { expression = "2+2" }, { bufnr = 1, tool_id = "t1" }))
      assert.equals("approve", approval.resolve("bash", { command = "ls -la" }, { bufnr = 1, tool_id = "t2" }))
      assert.equals("deny", approval.resolve("bash", { command = "rm -rf /" }, { bufnr = 1, tool_id = "t3" }))
      assert.equals(
        "require_approval",
        approval.resolve("bash", { command = "echo hello" }, { bufnr = 1, tool_id = "t4" })
      )
    end)

    it("returns require_approval when function throws", function()
      state.set_config({
        tools = {
          auto_approve = function()
            error("intentional test error")
          end,
        },
      })
      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
    end)

    it("returns require_approval for unexpected return values", function()
      state.set_config({
        tools = {
          auto_approve = function()
            return 42
          end,
        },
      })
      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
    end)
  end)

  describe("with unexpected auto_approve type", function()
    it("returns require_approval for number", function()
      state.set_config({ tools = { auto_approve = 42 } })
      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
    end)

    it("returns require_approval for string", function()
      state.set_config({ tools = { auto_approve = "calculator" } })
      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
    end)
  end)
end)

-- ============================================================================
-- Parser: flemma:pending Marker Tests
-- ============================================================================

describe("Parser flemma:pending support", function()
  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  it("sets pending=true on tool_result with flemma:pending fence", function()
    local bufnr = create_buffer({
      "@Assistant: Running tool",
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
    assert.equals("You", you_msg.role)
    assert.equals(1, #you_msg.segments)

    local seg = you_msg.segments[1]
    assert.equals("tool_result", seg.kind)
    assert.equals("toolu_01", seg.tool_use_id)
    assert.equals("", seg.content)
    assert.is_true(seg.pending)
    assert.is_false(seg.is_error)
  end)

  it("does not set pending on tool_result with plain empty fence", function()
    local bufnr = create_buffer({
      "@Assistant: Running tool",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```",
      "```",
    })

    local doc = parser.get_parsed_document(bufnr)
    local you_msg = doc.messages[2]
    local seg = you_msg.segments[1]
    assert.equals("tool_result", seg.kind)
    assert.equals("", seg.content)
    assert.is_nil(seg.pending)
  end)

  it("does not set pending on tool_result with content", function()
    local bufnr = create_buffer({
      "@Assistant: Running tool",
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

    local doc = parser.get_parsed_document(bufnr)
    local you_msg = doc.messages[2]
    local seg = you_msg.segments[1]
    assert.equals("tool_result", seg.kind)
    assert.equals("4", seg.content)
    assert.is_nil(seg.pending)
  end)
end)

-- ============================================================================
-- Awaiting Execution Detection Tests
-- ============================================================================

describe("Awaiting Execution Resolver", function()
  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  it("finds tool_use with flemma:pending tool_result", function()
    local bufnr = create_buffer({
      "@Assistant: Running tool",
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

    local awaiting = context.resolve_all_awaiting_execution(bufnr)
    assert.equals(1, #awaiting)
    assert.equals("toolu_01", awaiting[1].tool_id)
    assert.equals("calculator", awaiting[1].tool_name)
    assert.same({ expression = "2+2" }, awaiting[1].input)
  end)

  it("does NOT detect plain empty tool_result as awaiting", function()
    local bufnr = create_buffer({
      "@Assistant: Running tool",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```",
      "```",
    })

    local awaiting = context.resolve_all_awaiting_execution(bufnr)
    assert.equals(0, #awaiting)
  end)

  it("ignores tool_result with content", function()
    local bufnr = create_buffer({
      "@Assistant: Running tool",
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

    local awaiting = context.resolve_all_awaiting_execution(bufnr)
    assert.equals(0, #awaiting)
  end)

  it("ignores error tool_result", function()
    local bufnr = create_buffer({
      "@Assistant: Running tool",
      "",
      "**Tool Use:** `bash` (`toolu_01`)",
      "```json",
      '{ "command": "fail" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01` (error)",
      "",
      "```flemma:pending",
      "```",
    })

    local awaiting = context.resolve_all_awaiting_execution(bufnr)
    assert.equals(0, #awaiting)
  end)

  it("handles mixed pending and user-overridden results", function()
    local bufnr = create_buffer({
      "@Assistant: Two tools",
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
      "```",
      "",
      "**Tool Result:** `toolu_02`",
      "",
      "```",
      "I don't want to run this",
      "```",
    })

    local awaiting = context.resolve_all_awaiting_execution(bufnr)
    assert.equals(1, #awaiting)
    assert.equals("toolu_01", awaiting[1].tool_id)
    assert.equals("calculator", awaiting[1].tool_name)
  end)

  it("returns empty when no tool_results exist at all", function()
    local bufnr = create_buffer({
      "@Assistant: Running tool",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
    })

    local awaiting = context.resolve_all_awaiting_execution(bufnr)
    assert.equals(0, #awaiting)
  end)

  it("returns empty when buffer has no tool_use at all", function()
    local bufnr = create_buffer({
      "@You: Hello",
      "",
      "@Assistant: Hi there!",
    })

    local awaiting = context.resolve_all_awaiting_execution(bufnr)
    assert.equals(0, #awaiting)
  end)

  it("handles multiple pending placeholders", function()
    local bufnr = create_buffer({
      "@Assistant: Two tools",
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
      "```",
      "",
      "**Tool Result:** `toolu_02`",
      "",
      "```flemma:pending",
      "```",
    })

    local awaiting = context.resolve_all_awaiting_execution(bufnr)
    assert.equals(2, #awaiting)
    assert.equals("toolu_01", awaiting[1].tool_id)
    assert.equals("toolu_02", awaiting[2].tool_id)
  end)
end)

-- ============================================================================
-- Placeholder Injection for Approval Tests
-- ============================================================================

describe("Approval Placeholder Injection", function()
  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  it("inject_placeholder with pending=true uses flemma:pending fence", function()
    local bufnr = create_buffer({
      "@Assistant: Here is the tool:",
      "",
      "**Tool Use:** `calculator` (`toolu_approval`)",
      "```json",
      '{ "expression": "5*5" }',
      "```",
    })

    local header_line, err = injector.inject_placeholder(bufnr, "toolu_approval", { pending = true })
    assert.is_nil(err)
    assert.is_not_nil(header_line)

    -- Verify the flemma:pending fence marker is in the buffer
    local lines = get_lines(bufnr)
    local found_pending = false
    for _, line in ipairs(lines) do
      if line == "```flemma:pending" then
        found_pending = true
        break
      end
    end
    assert.is_true(found_pending, "Expected ```flemma:pending in buffer")

    -- Verify resolve_all_pending no longer finds it (it has a tool_result now)
    local pending = context.resolve_all_pending(bufnr)
    assert.equals(0, #pending)

    -- Verify resolve_all_awaiting_execution finds it (pending marker)
    local awaiting = context.resolve_all_awaiting_execution(bufnr)
    assert.equals(1, #awaiting)
    assert.equals("toolu_approval", awaiting[1].tool_id)
    assert.equals("calculator", awaiting[1].tool_name)
  end)

  it("inject_placeholder without pending option uses plain fence", function()
    local bufnr = create_buffer({
      "@Assistant: Here is the tool:",
      "",
      "**Tool Use:** `calculator` (`toolu_plain`)",
      "```json",
      '{ "expression": "5*5" }',
      "```",
    })

    injector.inject_placeholder(bufnr, "toolu_plain")

    -- Verify no flemma:pending fence marker
    local lines = get_lines(bufnr)
    for _, line in ipairs(lines) do
      assert.is_not.equals("```flemma:pending", line)
    end

    -- Should NOT be detected as awaiting (no pending marker)
    local awaiting = context.resolve_all_awaiting_execution(bufnr)
    assert.equals(0, #awaiting)
  end)

  it("user overriding flemma:pending by editing the fence removes pending detection", function()
    local bufnr = create_buffer({
      "@Assistant: Here is the tool:",
      "",
      "**Tool Use:** `bash` (`toolu_manual`)",
      "```json",
      '{ "command": "rm -rf /" }',
      "```",
    })

    -- Inject pending placeholder
    injector.inject_placeholder(bufnr, "toolu_manual", { pending = true })

    -- Verify it's awaiting execution
    local awaiting = context.resolve_all_awaiting_execution(bufnr)
    assert.equals(1, #awaiting)

    -- Simulate user replacing the flemma:pending fence with content
    local lines = get_lines(bufnr)
    for i, line in ipairs(lines) do
      if line == "```flemma:pending" then
        -- Replace the pending fence + closing fence with user content
        vim.api.nvim_buf_set_lines(bufnr, i - 1, i + 1, false, { "```", "I refused to run this", "```" })
        break
      end
    end

    -- Now it should no longer be awaiting
    awaiting = context.resolve_all_awaiting_execution(bufnr)
    assert.equals(0, #awaiting)
  end)

  it("inject_result replaces flemma:pending marker with actual content", function()
    local bufnr = create_buffer({
      "@Assistant: Here is the tool:",
      "",
      "**Tool Use:** `calculator` (`toolu_exec`)",
      "```json",
      '{ "expression": "5*5" }',
      "```",
    })

    -- Inject pending placeholder
    injector.inject_placeholder(bufnr, "toolu_exec", { pending = true })

    -- Verify flemma:pending is present
    local lines = get_lines(bufnr)
    local found_pending = false
    for _, line in ipairs(lines) do
      if line == "```flemma:pending" then
        found_pending = true
        break
      end
    end
    assert.is_true(found_pending)

    -- Inject actual result (simulating what executor does after tool runs)
    injector.inject_result(bufnr, "toolu_exec", { success = true, output = "25" })

    -- Verify flemma:pending is gone
    lines = get_lines(bufnr)
    for _, line in ipairs(lines) do
      assert.is_not.equals("```flemma:pending", line)
    end

    -- Verify result content is present
    local found_result = false
    for _, line in ipairs(lines) do
      if line == "25" then
        found_result = true
        break
      end
    end
    assert.is_true(found_result, "Expected result '25' in buffer")

    -- No longer awaiting
    local awaiting = context.resolve_all_awaiting_execution(bufnr)
    assert.equals(0, #awaiting)
  end)

  it("denied tool result is not detected as awaiting", function()
    local bufnr = create_buffer({
      "@Assistant: Here is the tool:",
      "",
      "**Tool Use:** `bash` (`toolu_deny`)",
      "```json",
      '{ "command": "rm -rf /" }',
      "```",
    })

    -- Inject placeholder then inject error result (as denial flow would)
    injector.inject_placeholder(bufnr, "toolu_deny")
    injector.inject_result(bufnr, "toolu_deny", {
      success = false,
      error = "Denied by auto_approve policy",
    })

    -- Should not be pending
    local pending = context.resolve_all_pending(bufnr)
    assert.equals(0, #pending)

    -- Should not be awaiting (has error content)
    local awaiting = context.resolve_all_awaiting_execution(bufnr)
    assert.equals(0, #awaiting)

    -- Verify the error marker is present in the buffer
    local lines = get_lines(bufnr)
    local found_error = false
    for _, line in ipairs(lines) do
      if line:match("%(error%)") then
        found_error = true
        break
      end
    end
    assert.is_true(found_error, "Expected (error) marker in buffer")
  end)
end)
