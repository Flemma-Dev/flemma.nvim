--- Tests that frontmatter is evaluated exactly once per send_or_execute dispatch cycle.
--- Uses spy.on(processor, "evaluate_frontmatter") to count evaluations.
--- E2E scenarios are driven through core.send_or_execute() (the <C-]> / autopilot
--- entry point) with HTTP fixtures. The :Flemma send command uses send_to_provider()
--- directly which is a separate path tested via pipeline backward compat tests below.

local spy = require("luassert.spy")

describe("Frontmatter evaluation caching", function()
  local client = require("flemma.client")
  local flemma, state, core, processor

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.core.config.manager"] = nil
    package.loaded["flemma.provider.registry"] = nil
    package.loaded["flemma.models"] = nil
    package.loaded["flemma.autopilot"] = nil
    package.loaded["flemma.processor"] = nil
    package.loaded["flemma.pipeline"] = nil

    flemma = require("flemma")
    state = require("flemma.state")
    core = require("flemma.core")
    processor = require("flemma.processor")

    flemma.setup({
      parameters = { thinking = false },
      tools = { autopilot = { enabled = true } },
    })
    require("flemma.tools").register("extras.flemma.tools.calculator")
  end)

  after_each(function()
    client.clear_fixtures()
    vim.cmd("silent! %bdelete!")
  end)

  -- =========================================================================
  -- Simple send via send_or_execute (no frontmatter, no tool calls)
  -- =========================================================================

  it("evaluates frontmatter exactly once for a simple send without frontmatter", function()
    local eval_spy = spy.on(processor, "evaluate_frontmatter")

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You: Hello" })

    client.register_fixture("api%.anthropic%.com", "tests/fixtures/anthropic_hello_success_stream.txt")
    core.send_or_execute({ bufnr = bufnr })

    vim.wait(2000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for _, line in ipairs(lines) do
        if line == "@You: " then
          return true
        end
      end
      return false
    end)

    -- Exactly one evaluation: from send_or_execute → pipeline reuses the result
    assert.spy(eval_spy).was_called(1)
    eval_spy:revert()
  end)

  -- =========================================================================
  -- Send with Lua frontmatter via send_or_execute (no tool calls)
  -- =========================================================================

  it("evaluates frontmatter exactly once for a send with Lua frontmatter", function()
    local eval_spy = spy.on(processor, "evaluate_frontmatter")

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```lua",
      "return { parameters = { temperature = 0.5 } }",
      "```",
      "",
      "@You: Hello",
    })

    client.register_fixture("api%.anthropic%.com", "tests/fixtures/anthropic_hello_success_stream.txt")
    core.send_or_execute({ bufnr = bufnr })

    vim.wait(2000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for _, line in ipairs(lines) do
        if line == "@You: " then
          return true
        end
      end
      return false
    end)

    -- Exactly one evaluation: from send_or_execute (pipeline.run reuses the result)
    assert.spy(eval_spy).was_called(1)
    eval_spy:revert()
  end)

  -- =========================================================================
  -- Send with JSON frontmatter via send_or_execute
  -- =========================================================================

  it("evaluates JSON frontmatter exactly once per dispatch", function()
    local eval_spy = spy.on(processor, "evaluate_frontmatter")

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```json",
      '{ "parameters": { "temperature": 0.3 } }',
      "```",
      "",
      "@You: Hello",
    })

    client.register_fixture("api%.anthropic%.com", "tests/fixtures/anthropic_hello_success_stream.txt")
    core.send_or_execute({ bufnr = bufnr })

    vim.wait(2000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for _, line in ipairs(lines) do
        if line == "@You: " then
          return true
        end
      end
      return false
    end)

    assert.spy(eval_spy).was_called(1)
    eval_spy:revert()
  end)

  -- =========================================================================
  -- Autopilot override from frontmatter
  -- =========================================================================

  it("sets autopilot_override from frontmatter on dispatch", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```lua",
      "flemma.opt.tools.autopilot = false",
      "```",
      "",
      "@You: Hello",
    })

    client.register_fixture("api%.anthropic%.com", "tests/fixtures/anthropic_hello_success_stream.txt")
    core.send_or_execute({ bufnr = bufnr })

    vim.wait(2000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for _, line in ipairs(lines) do
        if line == "@You: " then
          return true
        end
      end
      return false
    end)

    -- Verify the buffer-local override was set from frontmatter
    local buffer_state = state.get_buffer_state(bufnr)
    assert.equals(false, buffer_state.autopilot_override)
  end)

  it("clears autopilot_override when frontmatter has no autopilot key", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)

    -- First, set an override manually to simulate a previous dispatch with autopilot=false
    local buffer_state = state.get_buffer_state(bufnr)
    buffer_state.autopilot_override = false

    -- Frontmatter without autopilot key
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```lua",
      "return { parameters = { temperature = 0.5 } }",
      "```",
      "",
      "@You: Hello",
    })

    client.register_fixture("api%.anthropic%.com", "tests/fixtures/anthropic_hello_success_stream.txt")
    core.send_or_execute({ bufnr = bufnr })

    vim.wait(2000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for _, line in ipairs(lines) do
        if line == "@You: " then
          return true
        end
      end
      return false
    end)

    -- autopilot_override should be nil (cleared), falling back to global config
    buffer_state = state.get_buffer_state(bufnr)
    assert.is_nil(buffer_state.autopilot_override)
  end)

  it("sets autopilot_override=true from frontmatter, overriding global disabled config", function()
    -- Setup: config has autopilot disabled globally
    flemma.setup({
      parameters = { thinking = false },
      tools = { autopilot = { enabled = false } },
    })

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```lua",
      "flemma.opt.tools.autopilot = true",
      "```",
      "",
      "@You: Hello",
    })

    client.register_fixture("api%.anthropic%.com", "tests/fixtures/anthropic_hello_success_stream.txt")
    core.send_or_execute({ bufnr = bufnr })

    vim.wait(2000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for _, line in ipairs(lines) do
        if line == "@You: " then
          return true
        end
      end
      return false
    end)

    -- autopilot_override should be true (from frontmatter), overriding global config
    local buffer_state = state.get_buffer_state(bufnr)
    assert.equals(true, buffer_state.autopilot_override)

    -- autopilot.is_enabled should reflect the override
    local autopilot = require("flemma.autopilot")
    assert.is_true(autopilot.is_enabled(bufnr))
  end)

  -- =========================================================================
  -- Tool use response: frontmatter evaluated once per dispatch turn
  -- =========================================================================

  it("evaluates frontmatter once per dispatch when LLM returns tool_use", function()
    local eval_spy = spy.on(processor, "evaluate_frontmatter")

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```lua",
      'return { tools = { auto_approve = { "calculator" } } }',
      "```",
      "",
      "@You: Calculate 15 * 7",
    })

    -- First turn: LLM returns a tool_use for calculator
    client.register_fixture("api%.anthropic%.com", "tests/fixtures/tool_calling/anthropic_tool_use_streaming.txt")
    core.send_or_execute({ bufnr = bufnr })

    -- Wait for the tool_use block to appear in the buffer
    vim.wait(2000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local content = table.concat(lines, "\n")
      return content:match("%*%*Tool Use:%*%*") ~= nil
    end)

    -- NOTE: We do NOT assert an exact call count here. The autopilot re-dispatch
    -- (via vim.schedule) can fire during vim.wait polling, so by the time we reach
    -- this point evaluate_frontmatter may have been called 1 or 2 times depending
    -- on event loop timing. The final assertions below validate the real invariant.

    -- Autopilot fires and calls send_or_execute again for tool categorization + execution.
    -- Wait for the tool result placeholder to appear
    vim.wait(2000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local content = table.concat(lines, "\n")
      return content:match("Tool Result") ~= nil
    end)

    -- The autopilot re-dispatch calls send_or_execute again → 1 more evaluation
    -- Total so far: 2 (one per dispatch cycle)
    local call_count = #eval_spy.calls
    assert.is_true(call_count >= 2, "Expected at least 2 evaluations (one per dispatch), got " .. call_count)

    -- Now switch fixture to the final text response for the autopilot continuation
    client.clear_fixtures()
    client.register_fixture("api%.anthropic%.com", "tests/fixtures/tool_calling/anthropic_final_response_streaming.txt")

    -- Wait for the final response to complete
    vim.wait(3000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local content = table.concat(lines, "\n")
      -- The final response should end with @You: prompt after a second @Assistant message
      local last_line = lines[#lines]
      return last_line == "@You: " and content:match("105") ~= nil
    end)

    -- Each dispatch cycle evaluates frontmatter exactly once.
    -- The key invariant: each call to send_or_execute produces exactly 1 evaluate_frontmatter call.
    local final_count = #eval_spy.calls
    assert.is_true(
      final_count >= 2,
      "Expected at least 2 evaluate_frontmatter calls across dispatch cycles, got " .. final_count
    )
    -- Verify it's not excessive — should be at most 1 per dispatch turn
    -- With tool auto-approve, the turns are: initial send, autopilot re-dispatch(s), final send
    assert.is_true(final_count <= 5, "Too many evaluate_frontmatter calls: " .. final_count .. " (expected <=5)")

    eval_spy:revert()
  end)

  -- =========================================================================
  -- Pipeline backward compatibility: no pre-resolved frontmatter
  -- =========================================================================

  it("pipeline.run evaluates frontmatter internally when not provided", function()
    local pipeline = require("flemma.pipeline")
    local parser = require("flemma.parser")
    local ctxutil = require("flemma.context")

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```lua",
      "return { parameters = { temperature = 0.9 } }",
      "```",
      "",
      "@You: Hello",
    })

    local doc = parser.get_parsed_document(bufnr)
    local context = ctxutil.from_buffer(bufnr)

    -- Call without evaluated_frontmatter — should evaluate internally via the local function
    local eval_spy = spy.on(processor, "evaluate_frontmatter")
    local _, evaluated = pipeline.run(doc, context, nil)

    -- evaluate_frontmatter on the module table is NOT called (evaluate() uses
    -- evaluate_frontmatter_internal directly for backward compat)
    assert.spy(eval_spy).was_called(0)

    -- But the evaluation still happened — verify opts were resolved
    assert.is_not_nil(evaluated.opts)

    eval_spy:revert()
  end)

  it("pipeline.run reuses evaluated_frontmatter when provided", function()
    local pipeline = require("flemma.pipeline")
    local parser = require("flemma.parser")
    local ctxutil = require("flemma.context")

    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```lua",
      "return { parameters = { temperature = 0.9 } }",
      "```",
      "",
      "@You: Hello",
    })

    local doc = parser.get_parsed_document(bufnr)
    local context = ctxutil.from_buffer(bufnr)

    -- Pre-evaluate frontmatter
    local evaluated_frontmatter = processor.evaluate_frontmatter(doc, context)

    -- Now call pipeline.run with the pre-resolved result
    local eval_spy = spy.on(processor, "evaluate_frontmatter")
    local _, evaluated = pipeline.run(doc, context, evaluated_frontmatter)

    -- The spy should not have been called — frontmatter was reused
    assert.spy(eval_spy).was_called(0)

    -- Opts should still be resolved from the pre-evaluated context
    assert.is_not_nil(evaluated.opts)

    eval_spy:revert()
  end)

  -- =========================================================================
  -- evaluate_buffer_frontmatter routes through evaluate_frontmatter
  -- =========================================================================

  it("evaluate_buffer_frontmatter calls evaluate_frontmatter exactly once", function()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "```lua",
      "return { parameters = { temperature = 0.7 } }",
      "```",
      "",
      "@You: Hello",
    })

    local eval_spy = spy.on(processor, "evaluate_frontmatter")
    local result = processor.evaluate_buffer_frontmatter(bufnr)

    assert.spy(eval_spy).was_called(1)
    assert.is_not_nil(result.context)
    assert.is_not_nil(result.diagnostics)

    eval_spy:revert()
  end)
end)
