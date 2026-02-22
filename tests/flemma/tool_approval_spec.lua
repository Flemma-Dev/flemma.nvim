--- Tests for tool execution approval flow
--- Covers: approval resolver registry, priority chain, flemma:tool status blocks,
--- awaiting execution detection

-- Clear module caches for clean state
package.loaded["flemma.tools.approval"] = nil
package.loaded["flemma.tools.presets"] = nil
package.loaded["flemma.tools.context"] = nil
package.loaded["flemma.tools.injector"] = nil
package.loaded["flemma.state"] = nil
package.loaded["flemma.parser"] = nil

local approval = require("flemma.tools.approval")
local context = require("flemma.tools.context")
local injector = require("flemma.tools.injector")
local state = require("flemma.state")
local parser = require("flemma.parser")
local processor = require("flemma.processor")

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

--- Helper: evaluate frontmatter and return frontmatter opts for a buffer.
--- @param bufnr integer
--- @return flemma.opt.FrontmatterOpts|nil
local function evaluate_opts(bufnr)
  return processor.evaluate_buffer_frontmatter(bufnr).context:get_opts()
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
    it("registers urn:flemma:approval:config resolver at priority 100", function()
      set_config_and_setup({ tools = { auto_approve = { "calculator", "read" } } })

      local entry = approval.get("urn:flemma:approval:config")
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
    it("registers urn:flemma:approval:config resolver at priority 100", function()
      set_config_and_setup({
        tools = {
          auto_approve = function()
            return true
          end,
        },
      })

      local entry = approval.get("urn:flemma:approval:config")
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

      local entry = approval.get("urn:flemma:approval:catch-all")
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
-- Parser: tool_result without flemma:tool (plain fenced blocks)
-- ============================================================================

describe("Parser plain tool_result support", function()
  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  it("does not set status on tool_result with plain empty fence", function()
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
    assert.is_nil(seg.status)
  end)

  it("does not set status on tool_result with content", function()
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
    assert.is_nil(seg.status)
  end)
end)

-- ============================================================================
-- Awaiting Execution Detection Tests
-- ============================================================================

describe("Awaiting Execution Resolver", function()
  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  it("finds tool_use with flemma:tool status=pending tool_result", function()
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
      "```flemma:tool status=pending",
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
      "```flemma:tool status=pending",
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
      "```flemma:tool status=pending",
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
      "```flemma:tool status=pending",
      "```",
      "",
      "**Tool Result:** `toolu_02`",
      "",
      "```flemma:tool status=pending",
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

  it("inject_placeholder with status=pending uses flemma:tool fence", function()
    local bufnr = create_buffer({
      "@Assistant: Here is the tool:",
      "",
      "**Tool Use:** `calculator` (`toolu_approval`)",
      "```json",
      '{ "expression": "5*5" }',
      "```",
    })

    local header_line, err = injector.inject_placeholder(bufnr, "toolu_approval", { status = "pending" })
    assert.is_nil(err)
    assert.is_not_nil(header_line)

    -- Verify the flemma:tool fence marker is in the buffer
    local lines = get_lines(bufnr)
    local found_tool = false
    for _, line in ipairs(lines) do
      if line == "```flemma:tool status=pending" then
        found_tool = true
        break
      end
    end
    assert.is_true(found_tool, "Expected ```flemma:tool status=pending in buffer")

    -- Verify resolve_all_pending no longer finds it (it has a tool_result now)
    local pending = context.resolve_all_pending(bufnr)
    assert.equals(0, #pending)

    -- Verify resolve_all_awaiting_execution finds it (pending status)
    local awaiting = context.resolve_all_awaiting_execution(bufnr)
    assert.equals(1, #awaiting)
    assert.equals("toolu_approval", awaiting[1].tool_id)
    assert.equals("calculator", awaiting[1].tool_name)
  end)

  it("inject_placeholder without status option uses plain fence", function()
    local bufnr = create_buffer({
      "@Assistant: Here is the tool:",
      "",
      "**Tool Use:** `calculator` (`toolu_plain`)",
      "```json",
      '{ "expression": "5*5" }',
      "```",
    })

    injector.inject_placeholder(bufnr, "toolu_plain")

    -- Verify no flemma:tool fence marker
    local lines = get_lines(bufnr)
    for _, line in ipairs(lines) do
      assert.is_falsy(line:match("^```flemma:"))
    end

    -- Should NOT be detected as awaiting (no status marker)
    local awaiting = context.resolve_all_awaiting_execution(bufnr)
    assert.equals(0, #awaiting)
  end)

  it("user overriding flemma:tool by editing the fence removes pending detection", function()
    local bufnr = create_buffer({
      "@Assistant: Here is the tool:",
      "",
      "**Tool Use:** `bash` (`toolu_manual`)",
      "```json",
      '{ "command": "rm -rf /" }',
      "```",
    })

    -- Inject pending placeholder
    injector.inject_placeholder(bufnr, "toolu_manual", { status = "pending" })

    -- Verify it's awaiting execution
    local awaiting = context.resolve_all_awaiting_execution(bufnr)
    assert.equals(1, #awaiting)

    -- Simulate user replacing the flemma:tool fence with plain content
    local lines = get_lines(bufnr)
    for i, line in ipairs(lines) do
      if line:match("^```flemma:tool") then
        -- Replace the tool fence + closing fence with user content
        vim.api.nvim_buf_set_lines(bufnr, i - 1, i + 1, false, { "```", "I refused to run this", "```" })
        break
      end
    end

    -- Now it should no longer be awaiting
    awaiting = context.resolve_all_awaiting_execution(bufnr)
    assert.equals(0, #awaiting)
  end)

  it("inject_result replaces flemma:tool marker with actual content", function()
    local bufnr = create_buffer({
      "@Assistant: Here is the tool:",
      "",
      "**Tool Use:** `calculator` (`toolu_exec`)",
      "```json",
      '{ "expression": "5*5" }',
      "```",
    })

    -- Inject pending placeholder
    injector.inject_placeholder(bufnr, "toolu_exec", { status = "pending" })

    -- Verify flemma:tool is present
    local lines = get_lines(bufnr)
    local found_tool = false
    for _, line in ipairs(lines) do
      if line:match("^```flemma:tool") then
        found_tool = true
        break
      end
    end
    assert.is_true(found_tool)

    -- Inject actual result (simulating what executor does after tool runs)
    injector.inject_result(bufnr, "toolu_exec", { success = true, output = "25" })

    -- Verify flemma:tool is gone
    lines = get_lines(bufnr)
    for _, line in ipairs(lines) do
      assert.is_falsy(line:match("^```flemma:tool"))
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
      error = "The tool was denied by a policy.",
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
  before_each(function()
    require("flemma.tools").register("extras.flemma.tools.calculator")
  end)

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
      local opts = evaluate_opts(bufnr)

      assert.equals("approve", approval.resolve("calculator", {}, { bufnr = bufnr, tool_id = "t1", opts = opts }))
      assert.equals("approve", approval.resolve("read", {}, { bufnr = bufnr, tool_id = "t2", opts = opts }))
    end)

    it("passes on unlisted tools", function()
      set_config_and_setup({})

      local bufnr = create_buffer({
        "```lua",
        'flemma.opt.tools.auto_approve = { "calculator" }',
        "```",
        "@You: test",
      })
      local opts = evaluate_opts(bufnr)

      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = bufnr, tool_id = "t1", opts = opts }))
    end)

    it("empty list passes on everything", function()
      set_config_and_setup({})

      local bufnr = create_buffer({
        "```lua",
        "flemma.opt.tools.auto_approve = {}",
        "```",
        "@You: test",
      })
      local opts = evaluate_opts(bufnr)

      assert.equals(
        "require_approval",
        approval.resolve("calculator", {}, { bufnr = bufnr, tool_id = "t1", opts = opts })
      )
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
      local opts = evaluate_opts(bufnr)

      assert.equals("approve", approval.resolve("calculator", {}, { bufnr = bufnr, tool_id = "t1", opts = opts }))
      assert.equals("deny", approval.resolve("bash", {}, { bufnr = bufnr, tool_id = "t2", opts = opts }))
      assert.equals("require_approval", approval.resolve("read", {}, { bufnr = bufnr, tool_id = "t3", opts = opts }))
    end)

    it("maps nil return to pass-through", function()
      set_config_and_setup({})

      local bufnr = create_buffer({
        "```lua",
        "flemma.opt.tools.auto_approve = function() end",
        "```",
        "@You: test",
      })
      local opts = evaluate_opts(bufnr)

      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = bufnr, tool_id = "t1", opts = opts }))
    end)

    it("skips on error and continues chain", function()
      set_config_and_setup({})

      local bufnr = create_buffer({
        "```lua",
        'flemma.opt.tools.auto_approve = function() error("boom") end',
        "```",
        "@You: test",
      })
      local opts = evaluate_opts(bufnr)

      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = bufnr, tool_id = "t1", opts = opts }))
    end)
  end)

  describe("no frontmatter or no auto_approve", function()
    it("passes when buffer has no frontmatter", function()
      set_config_and_setup({})

      local bufnr = create_buffer({
        "@You: test",
      })
      local opts = evaluate_opts(bufnr)

      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = bufnr, tool_id = "t1", opts = opts }))
    end)

    it("passes when frontmatter does not set auto_approve", function()
      set_config_and_setup({})

      local bufnr = create_buffer({
        "```lua",
        "x = 5",
        "```",
        "@You: test",
      })
      local opts = evaluate_opts(bufnr)

      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = bufnr, tool_id = "t1", opts = opts }))
    end)
  end)

  describe("priority ordering", function()
    it("frontmatter resolver is at priority 90", function()
      set_config_and_setup({})

      local entry = approval.get("urn:flemma:approval:frontmatter")
      assert.is_not_nil(entry)
      assert.equals(90, entry.priority)
    end)

    it("config defers to frontmatter when frontmatter sets auto_approve", function()
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
      local opts = evaluate_opts(bufnr)

      -- Config defers when frontmatter sets auto_approve; frontmatter approves calculator
      assert.equals("approve", approval.resolve("calculator", {}, { bufnr = bufnr, tool_id = "t1", opts = opts }))
    end)

    it("config applies when no frontmatter auto_approve is set", function()
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

      -- No frontmatter auto_approve, so config resolver runs normally
      assert.equals("approve", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
      assert.equals("require_approval", approval.resolve("calculator", {}, { bufnr = 1, tool_id = "t2" }))
    end)

    it("frontmatter fully controls approval when it sets auto_approve", function()
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
      local opts = evaluate_opts(bufnr)

      -- Frontmatter approves calculator
      assert.equals("approve", approval.resolve("calculator", {}, { bufnr = bufnr, tool_id = "t1", opts = opts }))
      -- Config function defers for bash (frontmatter doesn't list bash), falls through to require_approval
      assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = bufnr, tool_id = "t2", opts = opts }))
    end)
  end)

  describe("frontmatter with presets", function()
    before_each(function()
      require("flemma.tools.presets").setup(nil)
    end)

    after_each(function()
      require("flemma.tools.presets").clear()
    end)

    it("frontmatter can set auto_approve to a preset", function()
      set_config_and_setup({ tools = { auto_approve = { "$default" } } })

      local bufnr = create_buffer({
        "```lua",
        'flemma.opt.tools.auto_approve = { "$readonly" }',
        "```",
        "@You: test",
      })
      local opts = evaluate_opts(bufnr)

      -- Frontmatter overrides config; only $readonly active
      assert.equals("approve", approval.resolve("read", {}, { bufnr = bufnr, tool_id = "t1", opts = opts }))
      assert.equals("require_approval", approval.resolve("write", {}, { bufnr = bufnr, tool_id = "t2", opts = opts }))
    end)

    it("frontmatter can remove $default to disable auto-approval", function()
      set_config_and_setup({ tools = { auto_approve = { "$default" } } })

      local bufnr = create_buffer({
        "```lua",
        'flemma.opt.tools.auto_approve = { "$default" }',
        'flemma.opt.tools.auto_approve:remove("$default")',
        "```",
        "@You: test",
      })
      local opts = evaluate_opts(bufnr)

      assert.equals("require_approval", approval.resolve("read", {}, { bufnr = bufnr, tool_id = "t1", opts = opts }))
    end)

    it("frontmatter can exclude a tool from a preset", function()
      set_config_and_setup({ tools = { auto_approve = { "$default" } } })

      local bufnr = create_buffer({
        "```lua",
        'flemma.opt.tools.auto_approve = { "$default" }',
        'flemma.opt.tools.auto_approve:remove("write")',
        "```",
        "@You: test",
      })
      local opts = evaluate_opts(bufnr)

      assert.equals("approve", approval.resolve("read", {}, { bufnr = bufnr, tool_id = "t1", opts = opts }))
      assert.equals("require_approval", approval.resolve("write", {}, { bufnr = bufnr, tool_id = "t2", opts = opts }))
      assert.equals("approve", approval.resolve("edit", {}, { bufnr = bufnr, tool_id = "t3", opts = opts }))
    end)

    it("frontmatter can add bash on top of default", function()
      set_config_and_setup({ tools = { auto_approve = { "$default" } } })

      local bufnr = create_buffer({
        "```lua",
        'flemma.opt.tools.auto_approve = { "$default" }',
        'flemma.opt.tools.auto_approve:append("bash")',
        "```",
        "@You: test",
      })
      local opts = evaluate_opts(bufnr)

      assert.equals("approve", approval.resolve("read", {}, { bufnr = bufnr, tool_id = "t1", opts = opts }))
      assert.equals("approve", approval.resolve("bash", {}, { bufnr = bufnr, tool_id = "t2", opts = opts }))
    end)
  end)
end)

-- ============================================================================
-- Parser: flemma:tool Marker Tests
-- ============================================================================

describe("Parser flemma:tool support", function()
  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  it("parses status=pending from flemma:tool info string", function()
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
      "```flemma:tool status=pending",
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
    assert.equals("pending", seg.status)
    assert.equals("", seg.content)
    assert.is_false(seg.is_error)
  end)

  it("parses status=approved from flemma:tool info string", function()
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

  it("parses status=rejected with user content", function()
    local bufnr = create_buffer({
      "@Assistant: Running tool",
      "",
      "**Tool Use:** `bash` (`toolu_01`)",
      "```json",
      '{ "command": "rm -rf /" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```flemma:tool status=rejected",
      "I don't want to run this dangerous command.",
      "```",
    })

    local doc = parser.get_parsed_document(bufnr)
    local you_msg = doc.messages[2]
    local seg = you_msg.segments[1]
    assert.equals("tool_result", seg.kind)
    assert.equals("rejected", seg.status)
    assert.equals("I don't want to run this dangerous command.", seg.content)
  end)

  it("parses status=denied", function()
    local bufnr = create_buffer({
      "@Assistant: Running tool",
      "",
      "**Tool Use:** `bash` (`toolu_01`)",
      "```json",
      '{ "command": "rm -rf /" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```flemma:tool status=denied",
      "```",
    })

    local doc = parser.get_parsed_document(bufnr)
    local you_msg = doc.messages[2]
    local seg = you_msg.segments[1]
    assert.equals("tool_result", seg.kind)
    assert.equals("denied", seg.status)
    assert.equals("", seg.content)
  end)

  it("defaults to status=pending when no info string", function()
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
      "```flemma:tool",
      "```",
    })

    local doc = parser.get_parsed_document(bufnr)
    local you_msg = doc.messages[2]
    local seg = you_msg.segments[1]
    assert.equals("tool_result", seg.kind)
    assert.equals("pending", seg.status)
  end)

  it("falls back to pending for invalid status values", function()
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
      "```flemma:tool status=xyz",
      "```",
    })

    local doc = parser.get_parsed_document(bufnr)
    local you_msg = doc.messages[2]
    local seg = you_msg.segments[1]
    assert.equals("tool_result", seg.kind)
    assert.equals("pending", seg.status)
  end)

  it("coerces 'reject' to 'rejected'", function()
    local bufnr = create_buffer({
      "@Assistant: Running tool",
      "",
      "**Tool Use:** `bash` (`toolu_01`)",
      "```json",
      '{ "command": "rm -rf /" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```flemma:tool status=reject",
      "```",
    })

    local doc = parser.get_parsed_document(bufnr)
    local seg = doc.messages[2].segments[1]
    assert.equals("rejected", seg.status)
  end)

  it("coerces 'deny' to 'denied'", function()
    local bufnr = create_buffer({
      "@Assistant: Running tool",
      "",
      "**Tool Use:** `bash` (`toolu_01`)",
      "```json",
      '{ "command": "rm -rf /" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```flemma:tool status=deny",
      "```",
    })

    local doc = parser.get_parsed_document(bufnr)
    local seg = doc.messages[2].segments[1]
    assert.equals("denied", seg.status)
  end)
end)

-- ============================================================================
-- Pipeline: flemma:tool blocks not counted as resolved
-- ============================================================================

describe("Pipeline flemma:tool exclusion", function()
  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  it("flemma:tool blocks do not clear pending_tool_uses in validation", function()
    local lines = {
      "@Assistant: Running tool",
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
    }
    local doc = parser.parse_lines(lines)
    local pipeline = require("flemma.pipeline")
    local ctx = require("flemma.context")
    local prompt = pipeline.run(doc, ctx.from_file("test.chat"))

    -- The tool should still be in pending_tool_calls because flemma:tool is a placeholder
    assert.equals(1, #prompt.pending_tool_calls)
    assert.equals("toolu_01", prompt.pending_tool_calls[1].id)
  end)

  it("resolved tool_result clears pending_tool_calls", function()
    local lines = {
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
    }
    local doc = parser.parse_lines(lines)
    local pipeline = require("flemma.pipeline")
    local ctx = require("flemma.context")
    local prompt = pipeline.run(doc, ctx.from_file("test.chat"))

    assert.equals(0, #prompt.pending_tool_calls)
  end)
end)

-- ============================================================================
-- Processor: flemma:tool blocks excluded from API parts
-- ============================================================================

describe("Processor flemma:tool exclusion", function()
  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  it("flemma:tool blocks are not included in evaluated parts", function()
    local lines = {
      "@Assistant: Running tool",
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
    }
    local doc = parser.parse_lines(lines)
    local ctx = require("flemma.context")
    local evaluated = processor.evaluate(doc, ctx.from_file("test.chat"))

    -- Find the user message
    local you_msg = nil
    for _, msg in ipairs(evaluated.messages) do
      if msg.role == "You" then
        you_msg = msg
        break
      end
    end

    -- The flemma:tool block should not produce any tool_result parts
    assert.is_not_nil(you_msg)
    local tool_result_count = 0
    for _, part in ipairs(you_msg.parts) do
      if part.kind == "tool_result" then
        tool_result_count = tool_result_count + 1
      end
    end
    assert.equals(0, tool_result_count)
  end)
end)

-- ============================================================================
-- Context: resolve_all_tool_blocks() Tests
-- ============================================================================

describe("Context resolve_all_tool_blocks", function()
  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  it("groups tool blocks by status", function()
    local bufnr = create_buffer({
      "@Assistant: Three tools",
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
      "**Tool Use:** `read` (`toolu_03`)",
      "```json",
      '{ "path": "/tmp/x" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```flemma:tool status=approved",
      "```",
      "",
      "**Tool Result:** `toolu_02`",
      "",
      "```flemma:tool status=denied",
      "```",
      "",
      "**Tool Result:** `toolu_03`",
      "",
      "```flemma:tool status=pending",
      "```",
    })

    local groups = context.resolve_all_tool_blocks(bufnr)
    assert.equals(1, #(groups["approved"] or {}))
    assert.equals(1, #(groups["denied"] or {}))
    assert.equals(1, #(groups["pending"] or {}))
    assert.equals("toolu_01", groups["approved"][1].tool_id)
    assert.equals("toolu_02", groups["denied"][1].tool_id)
    assert.equals("toolu_03", groups["pending"][1].tool_id)
  end)

  it("returns empty table when no tool blocks exist", function()
    local bufnr = create_buffer({
      "@You: Hello",
      "",
      "@Assistant: Hi there!",
    })

    local groups = context.resolve_all_tool_blocks(bufnr)
    assert.same({}, groups)
  end)

  it("excludes approved blocks with user-edited content (content-overwrite protection)", function()
    local bufnr = create_buffer({
      "@Assistant: Tool call",
      "",
      "**Tool Use:** `calculator` (`toolu_01`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```flemma:tool status=approved",
      "User edited this content",
      "```",
    })

    local groups = context.resolve_all_tool_blocks(bufnr)
    -- Should be excluded from approved group due to content-overwrite protection
    assert.equals(0, #(groups["approved"] or {}))
  end)

  it("includes rejected blocks with user content (content for error message)", function()
    local bufnr = create_buffer({
      "@Assistant: Tool call",
      "",
      "**Tool Use:** `bash` (`toolu_01`)",
      "```json",
      '{ "command": "rm -rf /" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_01`",
      "",
      "```flemma:tool status=rejected",
      "I refuse to run this command.",
      "```",
    })

    local groups = context.resolve_all_tool_blocks(bufnr)
    assert.equals(1, #(groups["rejected"] or {}))
    assert.equals("I refuse to run this command.", groups["rejected"][1].content)
  end)

  it("tool_result.start_line reflects current buffer positions after re-resolve", function()
    -- Regression (Edge Case 1): When denied/rejected blocks above pending blocks
    -- are resolved (injecting error results that change line count), the pending
    -- block positions from the initial resolve_all_tool_blocks call become stale.
    -- advance_phase2 must re-resolve after injections to get fresh positions.
    --
    -- This test verifies that resolve_all_tool_blocks returns accurate positions
    -- for a pending block both before and after a denied block above it is replaced.
    local bufnr = create_buffer({
      "@Assistant: Two tools",
      "",
      "**Tool Use:** `bash` (`toolu_denied`)",
      "```json",
      '{ "command": "rm -rf /" }',
      "```",
      "",
      "**Tool Use:** `calculator` (`toolu_pending`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_denied`",
      "",
      "```flemma:tool status=denied",
      "```",
      "",
      "**Tool Result:** `toolu_pending`",
      "",
      "```flemma:tool status=pending",
      "```",
    })

    local groups = context.resolve_all_tool_blocks(bufnr)
    local pending_start_before = groups["pending"][1].tool_result.start_line

    -- tool_result.start_line points to the **Tool Result:** header line
    local lines_before = get_lines(bufnr)
    assert.is_truthy(
      lines_before[pending_start_before]:match("Tool Result"),
      "start_line should point to Tool Result header before injection"
    )

    -- Inject error result for denied tool (changes line count)
    injector.inject_result(bufnr, "toolu_denied", {
      success = false,
      error = "The tool was denied by a policy.",
    })

    -- Re-resolve to get fresh positions
    local fresh_groups = context.resolve_all_tool_blocks(bufnr)
    local pending_after = fresh_groups["pending"]
    assert.equals(1, #pending_after)

    local pending_start_after = pending_after[1].tool_result.start_line

    -- The re-resolved position should still point to a valid Tool Result header
    local lines_after = get_lines(bufnr)
    assert.is_truthy(
      lines_after[pending_start_after]:match("Tool Result"),
      "Re-resolved start_line should point to Tool Result header, got: " .. (lines_after[pending_start_after] or "nil")
    )

    -- Verify: if line count changed, the position must have shifted
    local line_count_before = 21
    local line_count_after = #lines_after
    if line_count_before ~= line_count_after then
      -- If line count changed, original position is stale — this is the bug
      -- we're protecting against in advance_phase2
      assert.is_not.equals(
        pending_start_before,
        pending_start_after,
        "Line count changed but positions didn't update — stale position bug"
      )
    end
  end)
end)

-- ============================================================================
-- Placeholder Injection with flemma:tool Tests
-- ============================================================================

describe("Approval Placeholder Injection with flemma:tool", function()
  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  it("inject_placeholder with status=pending uses flemma:tool fence", function()
    local bufnr = create_buffer({
      "@Assistant: Here is the tool:",
      "",
      "**Tool Use:** `calculator` (`toolu_approval`)",
      "```json",
      '{ "expression": "5*5" }',
      "```",
    })

    local header_line, err = injector.inject_placeholder(bufnr, "toolu_approval", { status = "pending" })
    assert.is_nil(err)
    assert.is_not_nil(header_line)

    -- Verify the flemma:tool fence marker is in the buffer
    local lines = get_lines(bufnr)
    local found_tool = false
    for _, line in ipairs(lines) do
      if line == "```flemma:tool status=pending" then
        found_tool = true
        break
      end
    end
    assert.is_true(found_tool, "Expected ```flemma:tool status=pending in buffer")
  end)

  it("inject_placeholder with status=approved uses flemma:tool fence", function()
    local bufnr = create_buffer({
      "@Assistant: Here is the tool:",
      "",
      "**Tool Use:** `calculator` (`toolu_auto`)",
      "```json",
      '{ "expression": "5*5" }',
      "```",
    })

    injector.inject_placeholder(bufnr, "toolu_auto", { status = "approved" })

    local lines = get_lines(bufnr)
    local found = false
    for _, line in ipairs(lines) do
      if line == "```flemma:tool status=approved" then
        found = true
        break
      end
    end
    assert.is_true(found, "Expected ```flemma:tool status=approved in buffer")
  end)

  it("inject_placeholder with status=denied uses flemma:tool fence", function()
    local bufnr = create_buffer({
      "@Assistant: Here is the tool:",
      "",
      "**Tool Use:** `bash` (`toolu_deny`)",
      "```json",
      '{ "command": "rm -rf /" }',
      "```",
    })

    injector.inject_placeholder(bufnr, "toolu_deny", { status = "denied" })

    local lines = get_lines(bufnr)
    local found = false
    for _, line in ipairs(lines) do
      if line == "```flemma:tool status=denied" then
        found = true
        break
      end
    end
    assert.is_true(found, "Expected ```flemma:tool status=denied in buffer")
  end)

  it("inject_result replaces flemma:tool marker with actual content", function()
    local bufnr = create_buffer({
      "@Assistant: Here is the tool:",
      "",
      "**Tool Use:** `calculator` (`toolu_exec`)",
      "```json",
      '{ "expression": "5*5" }',
      "```",
    })

    -- Inject approved placeholder
    injector.inject_placeholder(bufnr, "toolu_exec", { status = "approved" })

    -- Verify flemma:tool is present
    local lines = get_lines(bufnr)
    local found_tool = false
    for _, line in ipairs(lines) do
      if line:match("^```flemma:tool") then
        found_tool = true
        break
      end
    end
    assert.is_true(found_tool)

    -- Inject actual result
    injector.inject_result(bufnr, "toolu_exec", { success = true, output = "25" })

    -- Verify flemma:tool is gone
    lines = get_lines(bufnr)
    for _, line in ipairs(lines) do
      assert.is_false(line:match("^```flemma:tool") ~= nil, "flemma:tool fence should be replaced")
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
  end)
end)

-- ============================================================================
-- Codeblock parser: info string capture Tests
-- ============================================================================

describe("Codeblock info string parsing", function()
  local codeblock = require("flemma.codeblock")

  it("captures info string after language tag", function()
    local lines = {
      "```flemma:tool status=pending",
      "```",
    }
    local block, _ = codeblock.parse_fenced_block(lines, 1)
    assert.is_not_nil(block)
    assert.equals("flemma:tool", block.language)
    assert.equals("status=pending", block.info)
    assert.equals("", block.content)
  end)

  it("captures info string with multiple key-value pairs", function()
    local lines = {
      "```flemma:tool status=approved timeout=30",
      "```",
    }
    local block, _ = codeblock.parse_fenced_block(lines, 1)
    assert.is_not_nil(block)
    assert.equals("flemma:tool", block.language)
    assert.equals("status=approved timeout=30", block.info)
  end)

  it("returns nil info when no info string present", function()
    local lines = {
      "```json",
      '{ "x": 1 }',
      "```",
    }
    local block, _ = codeblock.parse_fenced_block(lines, 1)
    assert.is_not_nil(block)
    assert.equals("json", block.language)
    assert.is_nil(block.info)
  end)

  it("returns nil info for bare fence", function()
    local lines = {
      "```",
      "content",
      "```",
    }
    local block, _ = codeblock.parse_fenced_block(lines, 1)
    assert.is_not_nil(block)
    assert.is_nil(block.language)
    assert.is_nil(block.info)
  end)

  it("captures content inside flemma:tool block", function()
    local lines = {
      "```flemma:tool status=rejected",
      "User rejection message here",
      "```",
    }
    local block, _ = codeblock.parse_fenced_block(lines, 1)
    assert.is_not_nil(block)
    assert.equals("flemma:tool", block.language)
    assert.equals("status=rejected", block.info)
    assert.equals("User rejection message here", block.content)
  end)
end)

-- ============================================================================
-- Injector: resolve_error_message
-- ============================================================================

describe("Injector resolve_error_message", function()
  it("returns DENIED_MESSAGE for denied status", function()
    assert.equals(injector.DENIED_MESSAGE, injector.resolve_error_message("denied"))
  end)

  it("returns DENIED_MESSAGE for denied status even with content", function()
    assert.equals(injector.DENIED_MESSAGE, injector.resolve_error_message("denied", "user content"))
  end)

  it("returns REJECTED_MESSAGE for rejected status with no content", function()
    assert.equals(injector.REJECTED_MESSAGE, injector.resolve_error_message("rejected"))
  end)

  it("returns REJECTED_MESSAGE for rejected status with empty content", function()
    assert.equals(injector.REJECTED_MESSAGE, injector.resolve_error_message("rejected", ""))
  end)

  it("returns user content for rejected status with non-empty content", function()
    assert.equals("Do not run this.", injector.resolve_error_message("rejected", "Do not run this."))
  end)
end)

-- ============================================================================
-- Regression: advance_phase2 bails out when current_request is set
-- ============================================================================

describe("advance_phase2 current_request guard", function()
  -- Regression: If the user presses <C-]> between scheduled Phase 1 and the
  -- deferred Phase 2, a new send_or_execute → send_to_provider chain may set
  -- current_request. The original scheduled Phase 2 should bail out to avoid
  -- a double-send race.

  after_each(function()
    vim.cmd("silent! %bdelete!")
    local st = require("flemma.state")
    st.set_config({})
  end)

  -- NOTE: Race condition simulation test
  --
  -- This test simulates a race where <C-]> is pressed while a request is
  -- already in flight. It manually sets current_request to fake an active
  -- request because timing races cannot be reliably reproduced through the
  -- normal fixture-driven flow. The manual state setup is the correct
  -- approach here.

  it("does not execute approved tools when current_request is set", function()
    -- Clear core module so it picks up the same state module as the test
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.core.config.manager"] = nil

    local st = require("flemma.state")
    st.set_config({ tools = { autopilot = { enabled = false } } })

    local bufnr = create_buffer({
      "@Assistant: Tool call.",
      "",
      "**Tool Use:** `calculator` (`toolu_race_guard`)",
      "```json",
      '{ "expression": "2+2" }',
      "```",
      "",
      "@You: **Tool Result:** `toolu_race_guard`",
      "",
      "```flemma:tool status=approved",
      "```",
    })

    -- Simulate: a provider request is already in flight (set by a concurrent <C-]>)
    st.set_buffer_state(bufnr, "current_request", { id = "concurrent_req" })

    -- Call send_or_execute — Phase 1 has nothing to categorize (no unmatched tool_uses),
    -- so it goes directly to advance_phase2, which should bail out due to current_request.
    local core = require("flemma.core")
    core.send_or_execute({ bufnr = bufnr })

    -- The flemma:tool block should still be present — it was not executed.
    local lines = get_lines(bufnr)
    local found_tool_block = false
    for _, line in ipairs(lines) do
      if line:match("flemma:tool status=approved") then
        found_tool_block = true
        break
      end
    end
    assert.is_true(found_tool_block, "flemma:tool block should survive when current_request is set")

    -- Clean up
    st.set_buffer_state(bufnr, "current_request", nil)
  end)
end)

-- ============================================================================
-- Preset Expansion Tests
-- ============================================================================

describe("Approval Preset Expansion", function()
  before_each(function()
    require("flemma.tools.presets").setup(nil)
  end)

  after_each(function()
    approval.clear()
    state.set_config({})
    require("flemma.tools.presets").clear()
  end)

  it("expands $default preset in auto_approve", function()
    set_config_and_setup({ tools = { auto_approve = { "$default" } } })
    assert.equals("approve", approval.resolve("read", {}, { bufnr = 1, tool_id = "t1" }))
    assert.equals("approve", approval.resolve("write", {}, { bufnr = 1, tool_id = "t2" }))
    assert.equals("approve", approval.resolve("edit", {}, { bufnr = 1, tool_id = "t3" }))
    assert.equals("require_approval", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t4" }))
  end)

  it("expands $readonly preset", function()
    set_config_and_setup({ tools = { auto_approve = { "$readonly" } } })
    assert.equals("approve", approval.resolve("read", {}, { bufnr = 1, tool_id = "t1" }))
    assert.equals("require_approval", approval.resolve("write", {}, { bufnr = 1, tool_id = "t2" }))
  end)

  it("unions multiple presets", function()
    require("flemma.tools.presets").setup({ ["$extra"] = { approve = { "bash" } } })
    set_config_and_setup({ tools = { auto_approve = { "$default", "$extra" } } })
    assert.equals("approve", approval.resolve("read", {}, { bufnr = 1, tool_id = "t1" }))
    assert.equals("approve", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t2" }))
  end)

  it("mixes presets with plain tool names", function()
    set_config_and_setup({ tools = { auto_approve = { "$readonly", "bash" } } })
    assert.equals("approve", approval.resolve("read", {}, { bufnr = 1, tool_id = "t1" }))
    assert.equals("approve", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t2" }))
    assert.equals("require_approval", approval.resolve("write", {}, { bufnr = 1, tool_id = "t3" }))
  end)

  it("deny in preset overrides approve from other preset", function()
    require("flemma.tools.presets").setup({
      ["$no-bash"] = { deny = { "bash" } },
      ["$yolo"] = { approve = { "bash" } },
    })
    set_config_and_setup({ tools = { auto_approve = { "$yolo", "$no-bash" } } })
    assert.equals("deny", approval.resolve("bash", {}, { bufnr = 1, tool_id = "t1" }))
  end)

  it("unknown preset name is silently ignored", function()
    set_config_and_setup({ tools = { auto_approve = { "$nonexistent", "read" } } })
    assert.equals("approve", approval.resolve("read", {}, { bufnr = 1, tool_id = "t1" }))
    assert.equals("require_approval", approval.resolve("write", {}, { bufnr = 1, tool_id = "t2" }))
  end)

  it("applies exclusions from context", function()
    set_config_and_setup({ tools = { auto_approve = { "$default" } } })
    local ctx = {
      bufnr = 1,
      tool_id = "t1",
      opts = {
        auto_approve = { "$default" },
        auto_approve_exclusions = { read = true },
      },
    }
    assert.equals("approve", approval.resolve("write", {}, ctx))
    assert.equals("require_approval", approval.resolve("read", {}, ctx))
  end)
end)

-- ============================================================================
-- Config Resolver Defers to Frontmatter Tests
-- ============================================================================

describe("Config resolver defers to frontmatter", function()
  before_each(function()
    require("flemma.tools.presets").setup(nil)
  end)

  after_each(function()
    approval.clear()
    state.set_config({})
    require("flemma.tools.presets").clear()
  end)

  it("config resolver returns nil when frontmatter sets auto_approve", function()
    set_config_and_setup({ tools = { auto_approve = { "$default" } } })
    assert.equals("approve", approval.resolve("read", {}, { bufnr = 1, tool_id = "t1" }))
    local ctx = { bufnr = 1, tool_id = "t1", opts = { auto_approve = { "$readonly" } } }
    assert.equals("approve", approval.resolve("read", {}, ctx))
    assert.equals(
      "require_approval",
      approval.resolve("write", {}, { bufnr = 1, tool_id = "t2", opts = { auto_approve = { "$readonly" } } })
    )
  end)

  it("frontmatter can remove $default to disable all auto-approval", function()
    set_config_and_setup({ tools = { auto_approve = { "$default" } } })
    local ctx = { bufnr = 1, tool_id = "t1", opts = { auto_approve = {} } }
    assert.equals("require_approval", approval.resolve("read", {}, ctx))
    assert.equals("require_approval", approval.resolve("write", {}, ctx))
  end)
end)
