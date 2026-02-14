--- Tests for tool execution approval flow
--- Covers: approval resolver registry, priority chain, flemma:pending marker,
--- awaiting execution detection

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

--- Helper: set config, clear resolvers, and run setup to register built-in resolvers.
--- Mirrors the real plugin flow: config is set, then approval.setup() converts it.
--- @param config table
local function set_config_and_setup(config)
  state.set_config(config)
  approval.clear()
  approval.setup()
end

-- ============================================================================
-- Approval Resolver Registry Tests
-- ============================================================================

describe("Approval Resolver Registry", function()
  after_each(function()
    approval.clear()
  end)

  describe("register and get", function()
    it("stores a resolver and retrieves it by name", function()
      approval.register("test-resolver", {
        resolve = function()
          return "approve"
        end,
        description = "Test resolver",
      })

      local entry = approval.get("test-resolver")
      assert.is_not_nil(entry)
      assert.equals("test-resolver", entry.name)
      assert.equals(50, entry.priority)
      assert.equals("Test resolver", entry.description)
    end)

    it("returns nil for unknown resolver", function()
      assert.is_nil(approval.get("nonexistent"))
    end)

    it("replaces resolver with same name", function()
      approval.register("my-resolver", {
        resolve = function()
          return "approve"
        end,
        priority = 10,
      })
      approval.register("my-resolver", {
        resolve = function()
          return "deny"
        end,
        priority = 90,
      })

      assert.equals(1, approval.count())
      local entry = approval.get("my-resolver")
      assert.equals(90, entry.priority)
    end)

    it("uses default priority of 50", function()
      approval.register("default-priority", {
        resolve = function()
          return nil
        end,
      })
      assert.equals(50, approval.get("default-priority").priority)
    end)

    it("uses custom priority", function()
      approval.register("custom-priority", {
        resolve = function()
          return nil
        end,
        priority = 200,
      })
      assert.equals(200, approval.get("custom-priority").priority)
    end)
  end)

  describe("unregister", function()
    it("removes an existing resolver", function()
      approval.register("to-remove", {
        resolve = function()
          return "approve"
        end,
      })
      assert.equals(1, approval.count())

      local removed = approval.unregister("to-remove")
      assert.is_true(removed)
      assert.equals(0, approval.count())
      assert.is_nil(approval.get("to-remove"))
    end)

    it("returns false for unknown resolver", function()
      assert.is_false(approval.unregister("nonexistent"))
    end)
  end)

  describe("get_all", function()
    it("returns resolvers sorted by priority descending", function()
      approval.register("low", { resolve = function() end, priority = 10 })
      approval.register("high", { resolve = function() end, priority = 100 })
      approval.register("mid", { resolve = function() end, priority = 50 })

      local all = approval.get_all()
      assert.equals(3, #all)
      assert.equals("high", all[1].name)
      assert.equals("mid", all[2].name)
      assert.equals("low", all[3].name)
    end)

    it("tie-breaks equal priority by name ascending", function()
      approval.register("beta", { resolve = function() end, priority = 50 })
      approval.register("alpha", { resolve = function() end, priority = 50 })
      approval.register("gamma", { resolve = function() end, priority = 50 })

      local all = approval.get_all()
      assert.equals("alpha", all[1].name)
      assert.equals("beta", all[2].name)
      assert.equals("gamma", all[3].name)
    end)

    it("returns empty list when no resolvers registered", function()
      assert.same({}, approval.get_all())
    end)
  end)

  describe("clear and count", function()
    it("clear removes all resolvers", function()
      approval.register("a", { resolve = function() end })
      approval.register("b", { resolve = function() end })
      assert.equals(2, approval.count())

      approval.clear()
      assert.equals(0, approval.count())
    end)
  end)
end)

-- ============================================================================
-- Priority Chain Evaluation Tests
-- ============================================================================

describe("Approval Priority Chain", function()
  after_each(function()
    approval.clear()
  end)

  it("higher priority resolver wins over lower", function()
    approval.register("low", {
      resolve = function()
        return "require_approval"
      end,
      priority = 10,
    })
    approval.register("high", {
      resolve = function()
        return "approve"
      end,
      priority = 100,
    })

    assert.equals("approve", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
  end)

  it("resolver returning nil passes to next", function()
    approval.register("pass-through", {
      resolve = function()
        return nil
      end,
      priority = 100,
    })
    approval.register("decider", {
      resolve = function()
        return "deny"
      end,
      priority = 50,
    })

    assert.equals("deny", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
  end)

  it("first non-nil result wins (stops chain)", function()
    local second_called = false
    approval.register("first", {
      resolve = function()
        return "approve"
      end,
      priority = 100,
    })
    approval.register("second", {
      resolve = function()
        second_called = true
        return "deny"
      end,
      priority = 50,
    })

    assert.equals("approve", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
    assert.is_false(second_called)
  end)

  it("defaults to require_approval when chain exhausts", function()
    approval.register("pass-through", {
      resolve = function()
        return nil
      end,
    })

    assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
  end)

  it("defaults to require_approval with empty chain", function()
    assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
  end)

  it("equal priority resolvers are tie-broken by name ascending", function()
    approval.register("beta", {
      resolve = function()
        return "deny"
      end,
      priority = 50,
    })
    approval.register("alpha", {
      resolve = function()
        return "approve"
      end,
      priority = 50,
    })

    -- "alpha" sorts before "beta" so it runs first
    assert.equals("approve", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
  end)

  it("resolver receives tool_name, input, and context", function()
    local captured = {}
    approval.register("capture", {
      resolve = function(tool_name, input, ctx)
        captured.tool_name = tool_name
        captured.input = input
        captured.context = ctx
        return "approve"
      end,
    })

    local input = { command = "echo hello" }
    local ctx = { bufnr = 42, tool_id = "toolu_abc" }
    approval.resolve("bash", input, ctx)

    assert.equals("bash", captured.tool_name)
    assert.same(input, captured.input)
    assert.same(ctx, captured.context)
  end)
end)

-- ============================================================================
-- Error Resilience Tests
-- ============================================================================

describe("Approval Error Resilience", function()
  after_each(function()
    approval.clear()
  end)

  it("skips throwing resolver and continues chain", function()
    approval.register("broken", {
      resolve = function()
        error("intentional test error")
      end,
      priority = 100,
    })
    approval.register("fallback", {
      resolve = function()
        return "approve"
      end,
      priority = 50,
    })

    assert.equals("approve", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
  end)

  it("skips resolver returning invalid value and continues chain", function()
    approval.register("invalid", {
      resolve = function()
        return 42
      end,
      priority = 100,
    })
    approval.register("valid", {
      resolve = function()
        return "deny"
      end,
      priority = 50,
    })

    assert.equals("deny", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
  end)

  it("defaults to require_approval when all resolvers error", function()
    approval.register("broken", {
      resolve = function()
        error("boom")
      end,
    })

    assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
  end)
end)

-- ============================================================================
-- Setup Integration Tests (config -> resolver conversion)
-- ============================================================================

describe("Approval Setup", function()
  after_each(function()
    approval.clear()
    state.set_config({})
  end)

  describe("with string list auto_approve", function()
    it("registers config:auto_approve resolver at priority 100", function()
      set_config_and_setup({ tools = { auto_approve = { "calculator", "read" } } })

      local entry = approval.get("config:auto_approve")
      assert.is_not_nil(entry)
      assert.equals(100, entry.priority)
    end)

    it("approves listed tools", function()
      set_config_and_setup({ tools = { auto_approve = { "calculator", "read" } } })

      assert.equals("approve", approval.resolve("calculator", {}, { bufnr = 1, tool_id = "t1" }))
      assert.equals("approve", approval.resolve("read", {}, { bufnr = 1, tool_id = "t2" }))
    end)

    it("passes on unlisted tools (defaults to require_approval)", function()
      set_config_and_setup({ tools = { auto_approve = { "calculator" } } })

      assert.equals(
        "require_approval",
        approval.resolve("bash", { command = "rm -rf /" }, { bufnr = 1, tool_id = "t1" })
      )
    end)

    it("empty list registers resolver that passes on everything", function()
      set_config_and_setup({ tools = { auto_approve = {} } })

      -- Resolver is registered but always returns nil, so default kicks in
      assert.equals("require_approval", approval.resolve("calculator", {}, { bufnr = 1, tool_id = "t1" }))
    end)
  end)

  describe("with function auto_approve", function()
    it("registers config:auto_approve resolver at priority 100", function()
      set_config_and_setup({
        tools = {
          auto_approve = function()
            return true
          end,
        },
      })

      local entry = approval.get("config:auto_approve")
      assert.is_not_nil(entry)
      assert.equals(100, entry.priority)
    end)

    it("maps true to approve", function()
      set_config_and_setup({
        tools = {
          auto_approve = function()
            return true
          end,
        },
      })

      assert.equals("approve", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
    end)

    it("maps false to require_approval", function()
      set_config_and_setup({
        tools = {
          auto_approve = function()
            return false
          end,
        },
      })

      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
    end)

    it("maps nil to pass-through (defaults to require_approval)", function()
      set_config_and_setup({
        tools = {
          auto_approve = function() end,
        },
      })

      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
    end)

    it("maps 'deny' to deny", function()
      set_config_and_setup({
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
      set_config_and_setup({
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
      set_config_and_setup({
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
      set_config_and_setup({
        tools = {
          auto_approve = function()
            error("intentional test error")
          end,
        },
      })

      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
    end)

    it("returns require_approval for unexpected return values", function()
      set_config_and_setup({
        tools = {
          auto_approve = function()
            return 42
          end,
        },
      })

      -- Function returns 42 which is not true/false/"deny"/nil
      -- The wrapper maps it to nil (pass), chain exhausts -> require_approval
      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
    end)
  end)

  describe("with no auto_approve configured", function()
    it("returns require_approval when auto_approve is nil", function()
      set_config_and_setup({ tools = { require_approval = true } })

      assert.equals("require_approval", approval.resolve("bash", { command = "ls" }, { bufnr = 1, tool_id = "t1" }))
    end)

    it("returns require_approval when tools config is empty", function()
      set_config_and_setup({ tools = {} })

      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
    end)

    it("returns require_approval when config is empty", function()
      set_config_and_setup({})

      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
    end)
  end)

  describe("with unexpected auto_approve type", function()
    it("returns require_approval for number", function()
      set_config_and_setup({ tools = { auto_approve = 42 } })

      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
    end)

    it("returns require_approval for string", function()
      set_config_and_setup({ tools = { auto_approve = "calculator" } })

      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
    end)
  end)

  describe("require_approval = false", function()
    it("registers catch-all approve resolver at priority 0", function()
      set_config_and_setup({ tools = { require_approval = false } })

      local entry = approval.get("config:catch_all_approve")
      assert.is_not_nil(entry)
      assert.equals(0, entry.priority)
    end)

    it("approves all tools when no other resolvers exist", function()
      set_config_and_setup({ tools = { require_approval = false } })

      assert.equals("approve", approval.resolve("bash", { command = "rm -rf /" }, { bufnr = 1, tool_id = "t1" }))
      assert.equals("approve", approval.resolve("calculator", {}, { bufnr = 1, tool_id = "t2" }))
    end)

    it("higher-priority resolver overrides catch-all", function()
      set_config_and_setup({ tools = { require_approval = false } })

      -- Add a higher-priority deny resolver
      approval.register("security", {
        resolve = function(tool_name)
          if tool_name == "bash" then
            return "deny"
          end
          return nil
        end,
        priority = 200,
      })

      assert.equals("deny", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
      assert.equals("approve", approval.resolve("calculator", {}, { bufnr = 1, tool_id = "t2" }))
    end)
  end)
end)

-- ============================================================================
-- Third-Party Composition Tests
-- ============================================================================

describe("Approval Third-Party Composition", function()
  after_each(function()
    approval.clear()
    state.set_config({})
  end)

  it("external resolver at high priority overrides built-in config", function()
    set_config_and_setup({ tools = { auto_approve = { "calculator" } } })

    -- Third-party adds a deny policy at higher priority
    approval.register("security-policy", {
      resolve = function(tool_name)
        if tool_name == "calculator" then
          return "deny"
        end
        return nil
      end,
      priority = 200,
    })

    -- Security policy (200) overrides auto_approve config (100)
    assert.equals("deny", approval.resolve("calculator", {}, { bufnr = 1, tool_id = "t1" }))
  end)

  it("external resolver at default priority is evaluated after config", function()
    set_config_and_setup({
      tools = {
        auto_approve = function(tool_name)
          if tool_name == "calculator" then
            return true
          end
          return nil
        end,
      },
    })

    -- Third-party at default priority (50) — lower than config (100)
    approval.register("extra-approver", {
      resolve = function(tool_name)
        if tool_name == "bash" then
          return "approve"
        end
        return nil
      end,
    })

    -- Config handles calculator at priority 100
    assert.equals("approve", approval.resolve("calculator", {}, { bufnr = 1, tool_id = "t1" }))
    -- Third-party handles bash at priority 50
    assert.equals("approve", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t2" }))
    -- Neither handles read -> default require_approval
    assert.equals("require_approval", approval.resolve("read", {}, { bufnr = 1, tool_id = "t3" }))
  end)

  it("multiple external resolvers chain correctly", function()
    approval.register("safe-bash", {
      resolve = function(tool_name, input)
        if tool_name == "bash" and input.command and input.command:match("^ls") then
          return "approve"
        end
        return nil
      end,
      priority = 75,
    })

    approval.register("deny-dangerous", {
      resolve = function(tool_name, input)
        if tool_name == "bash" and input.command and input.command:match("rm%s+%-rf") then
          return "deny"
        end
        return nil
      end,
      priority = 200,
    })

    -- deny-dangerous (200) catches rm -rf
    assert.equals("deny", approval.resolve("bash", { command = "rm -rf /" }, { bufnr = 1, tool_id = "t1" }))
    -- safe-bash (75) catches ls
    assert.equals("approve", approval.resolve("bash", { command = "ls -la" }, { bufnr = 1, tool_id = "t2" }))
    -- Neither catches echo -> default require_approval
    assert.equals(
      "require_approval",
      approval.resolve("bash", { command = "echo hello" }, { bufnr = 1, tool_id = "t3" })
    )
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

-- ============================================================================
-- Frontmatter Approval Resolver Tests
-- ============================================================================

describe("Frontmatter Approval Resolver", function()
  after_each(function()
    approval.clear()
    state.set_config({})
    vim.cmd("silent! %bdelete!")
  end)

  describe("string list auto_approve", function()
    it("approves listed tools from frontmatter", function()
      set_config_and_setup({})

      local bufnr = create_buffer({
        "```lua",
        'flemma.opt.tools.auto_approve = { "calculator", "read" }',
        "```",
        "@You: test",
      })

      assert.equals("approve", approval.resolve("calculator", {}, { bufnr = bufnr, tool_id = "t1" }))
      assert.equals("approve", approval.resolve("read", {}, { bufnr = bufnr, tool_id = "t2" }))
    end)

    it("passes on unlisted tools", function()
      set_config_and_setup({})

      local bufnr = create_buffer({
        "```lua",
        'flemma.opt.tools.auto_approve = { "calculator" }',
        "```",
        "@You: test",
      })

      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = bufnr, tool_id = "t1" }))
    end)

    it("empty list passes on everything", function()
      set_config_and_setup({})

      local bufnr = create_buffer({
        "```lua",
        "flemma.opt.tools.auto_approve = {}",
        "```",
        "@You: test",
      })

      assert.equals("require_approval", approval.resolve("calculator", {}, { bufnr = bufnr, tool_id = "t1" }))
    end)
  end)

  describe("function auto_approve", function()
    it("maps true/false/deny correctly", function()
      set_config_and_setup({})

      local bufnr = create_buffer({
        "```lua",
        "flemma.opt.tools.auto_approve = function(tool_name)",
        '  if tool_name == "calculator" then return true end',
        '  if tool_name == "bash" then return "deny" end',
        "  return false",
        "end",
        "```",
        "@You: test",
      })

      assert.equals("approve", approval.resolve("calculator", {}, { bufnr = bufnr, tool_id = "t1" }))
      assert.equals("deny", approval.resolve("bash", {}, { bufnr = bufnr, tool_id = "t2" }))
      assert.equals("require_approval", approval.resolve("read", {}, { bufnr = bufnr, tool_id = "t3" }))
    end)

    it("maps nil return to pass-through", function()
      set_config_and_setup({})

      local bufnr = create_buffer({
        "```lua",
        "flemma.opt.tools.auto_approve = function() end",
        "```",
        "@You: test",
      })

      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = bufnr, tool_id = "t1" }))
    end)

    it("skips on error and continues chain", function()
      set_config_and_setup({})

      local bufnr = create_buffer({
        "```lua",
        'flemma.opt.tools.auto_approve = function() error("boom") end',
        "```",
        "@You: test",
      })

      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = bufnr, tool_id = "t1" }))
    end)
  end)

  describe("no frontmatter or no auto_approve", function()
    it("passes when buffer has no frontmatter", function()
      set_config_and_setup({})

      local bufnr = create_buffer({
        "@You: test",
      })

      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = bufnr, tool_id = "t1" }))
    end)

    it("passes when frontmatter does not set auto_approve", function()
      set_config_and_setup({})

      local bufnr = create_buffer({
        "```lua",
        "x = 5",
        "```",
        "@You: test",
      })

      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = bufnr, tool_id = "t1" }))
    end)
  end)

  describe("priority ordering", function()
    it("frontmatter resolver is at priority 90", function()
      set_config_and_setup({})

      local entry = approval.get("frontmatter:auto_approve")
      assert.is_not_nil(entry)
      assert.equals(90, entry.priority)
    end)

    it("config auto_approve (100) overrides frontmatter (90)", function()
      set_config_and_setup({
        tools = {
          auto_approve = function(tool_name)
            if tool_name == "calculator" then
              return "deny"
            end
            return nil
          end,
        },
      })

      local bufnr = create_buffer({
        "```lua",
        'flemma.opt.tools.auto_approve = { "calculator" }',
        "```",
        "@You: test",
      })

      -- Config at 100 returns "deny" before frontmatter at 90 gets a chance
      assert.equals("deny", approval.resolve("calculator", {}, { bufnr = bufnr, tool_id = "t1" }))
    end)

    it("frontmatter (90) applies when config passes", function()
      set_config_and_setup({
        tools = {
          auto_approve = function(tool_name)
            if tool_name == "bash" then
              return true
            end
            return nil
          end,
        },
      })

      local bufnr = create_buffer({
        "```lua",
        'flemma.opt.tools.auto_approve = { "calculator" }',
        "```",
        "@You: test",
      })

      -- Config at 100 returns nil for calculator, frontmatter at 90 approves
      assert.equals("approve", approval.resolve("calculator", {}, { bufnr = bufnr, tool_id = "t1" }))
      -- Config at 100 handles bash itself
      assert.equals("approve", approval.resolve("bash", {}, { bufnr = bufnr, tool_id = "t2" }))
    end)
  end)
end)
