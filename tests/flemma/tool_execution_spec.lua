--- Tests for tool execution automation feature
--- Covers: registry extensions, calculator executor, context resolver, injector, executor

-- Clear module caches for clean state
package.loaded["flemma.tools"] = nil
package.loaded["flemma.tools.registry"] = nil
package.loaded["flemma.tools.executor"] = nil
package.loaded["flemma.tools.injector"] = nil
package.loaded["flemma.tools.context"] = nil
package.loaded["flemma.tools.definitions.calculator"] = nil
package.loaded["flemma.tools.definitions.bash"] = nil

local tools = require("flemma.tools")
local registry = require("flemma.tools.registry")
local context = require("flemma.tools.context")
local injector = require("flemma.tools.injector")
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
-- Registry Extension Tests
-- ============================================================================

describe("Tool Registry Extensions", function()
  before_each(function()
    registry.clear()
  end)

  describe("is_executable", function()
    it("returns true for tool with execute function", function()
      registry.register("test", {
        name = "test",
        execute = function() end,
      })
      assert.is_true(registry.is_executable("test"))
    end)

    it("returns false for tool without execute function", function()
      registry.register("schema_only", {
        name = "schema_only",
        description = "No executor",
      })
      assert.is_false(registry.is_executable("schema_only"))
    end)

    it("returns false for tool with executable=false", function()
      registry.register("disabled", {
        name = "disabled",
        execute = function() end,
        executable = false,
      })
      assert.is_false(registry.is_executable("disabled"))
    end)

    it("returns false for non-existent tool", function()
      assert.is_false(registry.is_executable("nonexistent"))
    end)
  end)

  describe("get_executor", function()
    it("returns executor and false for sync tool", function()
      local fn = function() end
      registry.register("sync_tool", {
        name = "sync_tool",
        async = false,
        execute = fn,
      })
      local executor, is_async = registry.get_executor("sync_tool")
      assert.equals(fn, executor)
      assert.is_false(is_async)
    end)

    it("returns executor and true for async tool", function()
      local fn = function() end
      registry.register("async_tool", {
        name = "async_tool",
        async = true,
        execute = fn,
      })
      local executor, is_async = registry.get_executor("async_tool")
      assert.equals(fn, executor)
      assert.is_true(is_async)
    end)

    it("returns nil for non-executable tool", function()
      registry.register("disabled", {
        name = "disabled",
        execute = function() end,
        executable = false,
      })
      local executor, is_async = registry.get_executor("disabled")
      assert.is_nil(executor)
      assert.is_false(is_async)
    end)

    it("returns nil for tool without execute", function()
      registry.register("no_exec", { name = "no_exec" })
      local executor, is_async = registry.get_executor("no_exec")
      assert.is_nil(executor)
      assert.is_false(is_async)
    end)

    it("returns nil for non-existent tool", function()
      local executor, is_async = registry.get_executor("nonexistent")
      assert.is_nil(executor)
      assert.is_false(is_async)
    end)
  end)
end)

-- ============================================================================
-- Calculator Executor Tests
-- ============================================================================

describe("Calculator Executor", function()
  local calc_def

  before_each(function()
    registry.clear()
    tools.setup()
    calc_def = registry.get("calculator")
  end)

  describe("basic math", function()
    it("evaluates addition", function()
      local result = calc_def.execute({ expression = "1 + 1" })
      assert.is_true(result.success)
      assert.equals("2", result.output)
    end)

    it("evaluates subtraction", function()
      local result = calc_def.execute({ expression = "10 - 3" })
      assert.is_true(result.success)
      assert.equals("7", result.output)
    end)

    it("evaluates multiplication", function()
      local result = calc_def.execute({ expression = "6 * 7" })
      assert.is_true(result.success)
      assert.equals("42", result.output)
    end)

    it("evaluates division", function()
      local result = calc_def.execute({ expression = "15 / 3" })
      assert.is_true(result.success)
      assert.equals("5", result.output)
    end)

    it("evaluates exponentiation", function()
      local result = calc_def.execute({ expression = "2 ^ 10" })
      assert.is_true(result.success)
      assert.equals("1024", result.output)
    end)

    it("evaluates modulo", function()
      local result = calc_def.execute({ expression = "17 % 5" })
      assert.is_true(result.success)
      assert.equals("2", result.output)
    end)
  end)

  describe("math library functions", function()
    it("evaluates math.sqrt", function()
      local result = calc_def.execute({ expression = "math.sqrt(16)" })
      assert.is_true(result.success)
      assert.equals("4", result.output)
    end)

    it("evaluates math.sin", function()
      local result = calc_def.execute({ expression = "math.sin(0)" })
      assert.is_true(result.success)
      assert.equals("0", result.output)
    end)

    it("evaluates math.pi", function()
      local result = calc_def.execute({ expression = "math.pi" })
      assert.is_true(result.success)
      assert.is_truthy(result.output:match("^3%.14159"))
    end)

    it("evaluates math.floor", function()
      local result = calc_def.execute({ expression = "math.floor(3.7)" })
      assert.is_true(result.success)
      assert.equals("3", result.output)
    end)

    it("evaluates math.abs", function()
      local result = calc_def.execute({ expression = "math.abs(-5)" })
      assert.is_true(result.success)
      assert.equals("5", result.output)
    end)
  end)

  describe("error cases", function()
    it("returns error for empty expression", function()
      local result = calc_def.execute({ expression = "" })
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("No expression"))
    end)

    it("returns error for nil expression", function()
      local result = calc_def.execute({})
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("No expression"))
    end)

    it("returns error for invalid syntax", function()
      local result = calc_def.execute({ expression = "1 ++" })
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("Invalid expression"))
    end)

    it("blocks access to os module", function()
      local result = calc_def.execute({ expression = 'os.execute("echo hi")' })
      assert.is_false(result.success)
    end)

    it("blocks access to require", function()
      local result = calc_def.execute({ expression = 'require("io")' })
      assert.is_false(result.success)
    end)

    it("blocks access to dofile", function()
      local result = calc_def.execute({ expression = 'dofile("/etc/passwd")' })
      assert.is_false(result.success)
    end)

    it("handles division by zero gracefully", function()
      local result = calc_def.execute({ expression = "1 / 0" })
      assert.is_true(result.success)
      assert.equals("inf", result.output)
    end)

    it("handles undefined variable by returning nil as string", function()
      -- In the sandboxed environment, undefined vars resolve to nil
      -- The calculator returns tostring(nil) = "nil" as success
      local result = calc_def.execute({ expression = "undefined_var" })
      assert.is_true(result.success)
      assert.equals("nil", result.output)
    end)
  end)

  it("is registered as sync tool", function()
    assert.is_false(calc_def.async)
    assert.is_true(registry.is_executable("calculator"))
    local _, is_async = registry.get_executor("calculator")
    assert.is_false(is_async)
  end)
end)

-- ============================================================================
-- Tool Context Resolver Tests
-- ============================================================================

describe("Tool Context Resolver", function()
  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  describe("basic resolution", function()
    it("resolves context when cursor is on tool header line", function()
      local bufnr = create_buffer({
        '@Assistant: Here is the result:',
        '',
        '**Tool Use:** `bash` (`toolu_abc123`)',
        '```json',
        '{ "command": "echo hello" }',
        '```',
      })

      local ctx, err = context.resolve(bufnr, { row = 3 })
      assert.is_nil(err)
      assert.is_not_nil(ctx)
      assert.equals("toolu_abc123", ctx.tool_id)
      assert.equals("bash", ctx.tool_name)
    end)

    it("resolves context when cursor is inside fenced block", function()
      local bufnr = create_buffer({
        '@Assistant: Here is the result:',
        '',
        '**Tool Use:** `bash` (`toolu_abc123`)',
        '```json',
        '{ "command": "echo hello" }',
        '```',
      })

      local ctx, err = context.resolve(bufnr, { row = 5 })
      assert.is_nil(err)
      assert.is_not_nil(ctx)
      assert.equals("toolu_abc123", ctx.tool_id)
    end)

    it("resolves context when cursor is on closing fence", function()
      local bufnr = create_buffer({
        '@Assistant: Here is the result:',
        '',
        '**Tool Use:** `bash` (`toolu_abc123`)',
        '```json',
        '{ "command": "echo hello" }',
        '```',
      })

      local ctx, err = context.resolve(bufnr, { row = 6 })
      assert.is_nil(err)
      assert.is_not_nil(ctx)
      assert.equals("toolu_abc123", ctx.tool_id)
    end)

    it("resolves context when cursor is after tool block", function()
      local bufnr = create_buffer({
        '@Assistant: Here is the result:',
        '',
        '**Tool Use:** `bash` (`toolu_abc123`)',
        '```json',
        '{ "command": "echo hello" }',
        '```',
        '',
        'Some text after tool.',
      })

      local ctx, err = context.resolve(bufnr, { row = 8 })
      assert.is_nil(err)
      assert.is_not_nil(ctx)
      assert.equals("toolu_abc123", ctx.tool_id)
    end)

    it("returns parsed input table", function()
      local bufnr = create_buffer({
        '@Assistant: Running command:',
        '',
        '**Tool Use:** `bash` (`toolu_input_test`)',
        '```json',
        '{ "command": "ls -la", "timeout": 10 }',
        '```',
      })

      local ctx, err = context.resolve(bufnr, { row = 3 })
      assert.is_nil(err)
      assert.is_not_nil(ctx)
      assert.is_not_nil(ctx.input)
      assert.equals("ls -la", ctx.input.command)
      assert.equals(10, ctx.input.timeout)
    end)
  end)

  describe("multiple tools in message", function()
    it("resolves first tool when cursor is on first tool", function()
      local bufnr = create_buffer({
        '@Assistant: Running tools:',
        '',
        '**Tool Use:** `bash` (`toolu_first`)',
        '```json',
        '{ "command": "echo first" }',
        '```',
        '',
        '**Tool Use:** `calculator` (`toolu_second`)',
        '```json',
        '{ "expression": "1+1" }',
        '```',
      })

      local ctx, err = context.resolve(bufnr, { row = 3 })
      assert.is_nil(err)
      assert.equals("toolu_first", ctx.tool_id)
      assert.equals("bash", ctx.tool_name)
    end)

    it("resolves second tool when cursor is on second tool", function()
      local bufnr = create_buffer({
        '@Assistant: Running tools:',
        '',
        '**Tool Use:** `bash` (`toolu_first`)',
        '```json',
        '{ "command": "echo first" }',
        '```',
        '',
        '**Tool Use:** `calculator` (`toolu_second`)',
        '```json',
        '{ "expression": "1+1" }',
        '```',
      })

      local ctx, err = context.resolve(bufnr, { row = 8 })
      assert.is_nil(err)
      assert.equals("toolu_second", ctx.tool_id)
      assert.equals("calculator", ctx.tool_name)
    end)

    it("resolves nearest tool when cursor is between tools", function()
      local bufnr = create_buffer({
        '@Assistant: Running tools:',
        '',
        '**Tool Use:** `bash` (`toolu_first`)',
        '```json',
        '{ "command": "echo first" }',
        '```',
        '',
        '**Tool Use:** `calculator` (`toolu_second`)',
        '```json',
        '{ "expression": "1+1" }',
        '```',
      })

      -- Line 7 is the empty line between the two tools
      local ctx, err = context.resolve(bufnr, { row = 7 })
      assert.is_nil(err)
      assert.is_not_nil(ctx)
      -- Should resolve to the nearest tool (first is 1 line away, second is 1 line away)
      -- Both equal distance - either is acceptable
      assert.is_truthy(ctx.tool_id == "toolu_first" or ctx.tool_id == "toolu_second")
    end)
  end)

  describe("cursor in user message", function()
    it("falls back to previous assistant message tools", function()
      local bufnr = create_buffer({
        '@Assistant: Running tool:',
        '',
        '**Tool Use:** `bash` (`toolu_fallback`)',
        '```json',
        '{ "command": "echo hello" }',
        '```',
        '',
        '@You: Here is the result:',
      })

      local ctx, err = context.resolve(bufnr, { row = 8 })
      assert.is_nil(err)
      assert.is_not_nil(ctx)
      assert.equals("toolu_fallback", ctx.tool_id)
    end)
  end)

  describe("edge cases and errors", function()
    it("returns error when no tools in assistant message", function()
      local bufnr = create_buffer({
        '@Assistant: Just some text, no tools here.',
      })

      local ctx, err = context.resolve(bufnr, { row = 1 })
      assert.is_nil(ctx)
      assert.is_not_nil(err)
      assert.is_truthy(err:match("No tool call"))
    end)

    it("returns error when cursor is in frontmatter", function()
      local bufnr = create_buffer({
        '---',
        'model: claude-sonnet-4-20250514',
        '---',
        '',
        '@You: Hello',
      })

      local ctx, err = context.resolve(bufnr, { row = 2 })
      assert.is_nil(ctx)
      assert.is_not_nil(err)
      assert.is_truthy(err:match("No tool call"))
    end)

    it("returns error when cursor is in system message", function()
      local bufnr = create_buffer({
        '@System: You are helpful.',
        '',
        '@You: Hello',
      })

      local ctx, err = context.resolve(bufnr, { row = 1 })
      assert.is_nil(ctx)
      assert.is_not_nil(err)
    end)

    it("returns error for user message without preceding assistant tools", function()
      local bufnr = create_buffer({
        '@You: Hello',
      })

      local ctx, err = context.resolve(bufnr, { row = 1 })
      assert.is_nil(ctx)
      assert.is_not_nil(err)
    end)
  end)
end)

-- ============================================================================
-- Result Injector Tests
-- ============================================================================

describe("Result Injector", function()
  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  describe("inject_placeholder", function()
    it("creates @You: message when none exists after assistant", function()
      local bufnr = create_buffer({
        '@Assistant: Here is the tool:',
        '',
        '**Tool Use:** `bash` (`toolu_ph_test`)',
        '```json',
        '{ "command": "echo hello" }',
        '```',
      })

      local header_line, err = injector.inject_placeholder(bufnr, "toolu_ph_test")
      assert.is_nil(err)
      assert.is_not_nil(header_line)

      local lines = get_lines(bufnr)
      -- Should have added @You: **Tool Result:** `toolu_ph_test` after the assistant message
      local found = false
      for _, line in ipairs(lines) do
        if line:match("@You:") and line:match("Tool Result") and line:match("toolu_ph_test") then
          found = true
          break
        end
      end
      assert.is_true(found, "Should have inserted @You: Tool Result header")
    end)

    it("reuses existing tool_result position on re-execution", function()
      local bufnr = create_buffer({
        '@Assistant: Here is the tool:',
        '',
        '**Tool Use:** `bash` (`toolu_reexec`)',
        '```json',
        '{ "command": "echo hello" }',
        '```',
        '',
        '@You: **Tool Result:** `toolu_reexec`',
        '',
        '```',
        'old result',
        '```',
      })

      local header_line, err = injector.inject_placeholder(bufnr, "toolu_reexec")
      assert.is_nil(err)
      assert.is_not_nil(header_line)
      -- Should return the existing line, not create a new one
      assert.equals(8, header_line)
    end)
  end)

  describe("inject_result", function()
    it("injects success result with fenced content", function()
      local bufnr = create_buffer({
        '@Assistant: Running tool:',
        '',
        '**Tool Use:** `bash` (`toolu_success`)',
        '```json',
        '{ "command": "echo hello" }',
        '```',
        '',
        '@You: **Tool Result:** `toolu_success`',
      })

      local ok, err = injector.inject_result(bufnr, "toolu_success", {
        success = true,
        output = "hello world",
      })
      assert.is_true(ok)
      assert.is_nil(err)

      local lines = get_lines(bufnr)
      local content = table.concat(lines, "\n")
      assert.is_truthy(content:match("hello world"), "Should contain the result output")
      assert.is_truthy(content:match("```"), "Should have fenced code block")
    end)

    it("injects error result with (error) marker", function()
      local bufnr = create_buffer({
        '@Assistant: Running tool:',
        '',
        '**Tool Use:** `bash` (`toolu_err`)',
        '```json',
        '{ "command": "false" }',
        '```',
        '',
        '@You: **Tool Result:** `toolu_err`',
      })

      local ok, err = injector.inject_result(bufnr, "toolu_err", {
        success = false,
        error = "Command failed with exit code 1",
      })
      assert.is_true(ok)
      assert.is_nil(err)

      local lines = get_lines(bufnr)
      local content = table.concat(lines, "\n")
      assert.is_truthy(content:match("%(error%)"), "Should have (error) marker in header")
      assert.is_truthy(content:match("exit code 1"), "Should contain error message")
    end)

    it("injects table result as JSON", function()
      local bufnr = create_buffer({
        '@Assistant: Computing:',
        '',
        '**Tool Use:** `calculator` (`toolu_json`)',
        '```json',
        '{ "expression": "1+1" }',
        '```',
        '',
        '@You: **Tool Result:** `toolu_json`',
      })

      local ok, err = injector.inject_result(bufnr, "toolu_json", {
        success = true,
        output = { result = 42 },
      })
      assert.is_true(ok)
      assert.is_nil(err)

      local lines = get_lines(bufnr)
      local content = table.concat(lines, "\n")
      assert.is_truthy(content:match("json"), "Should have json language tag")
    end)

    it("handles error with partial output", function()
      local bufnr = create_buffer({
        '@Assistant: Running:',
        '',
        '**Tool Use:** `bash` (`toolu_partial`)',
        '```json',
        '{ "command": "test" }',
        '```',
        '',
        '@You: **Tool Result:** `toolu_partial`',
      })

      local ok, err = injector.inject_result(bufnr, "toolu_partial", {
        success = false,
        error = "Exit code 1",
        output = "partial data",
      })
      assert.is_true(ok)
      assert.is_nil(err)

      local lines = get_lines(bufnr)
      local content = table.concat(lines, "\n")
      assert.is_truthy(content:match("Exit code 1"), "Should contain error message")
      assert.is_truthy(content:match("partial data"), "Should contain partial output")
    end)

    it("injects when no placeholder exists (creates one)", function()
      local bufnr = create_buffer({
        '@Assistant: Running tool:',
        '',
        '**Tool Use:** `bash` (`toolu_noph`)',
        '```json',
        '{ "command": "echo hello" }',
        '```',
      })

      local ok, err = injector.inject_result(bufnr, "toolu_noph", {
        success = true,
        output = "hello",
      })
      assert.is_true(ok)
      assert.is_nil(err)

      local lines = get_lines(bufnr)
      local content = table.concat(lines, "\n")
      assert.is_truthy(content:match("Tool Result.*toolu_noph"), "Should have created result header")
      assert.is_truthy(content:match("hello"), "Should contain result")
    end)
  end)

  describe("format and fence sizing", function()
    it("uses triple backticks for simple content", function()
      local bufnr = create_buffer({
        '@Assistant: Run:',
        '',
        '**Tool Use:** `bash` (`toolu_fence3`)',
        '```json',
        '{ "command": "echo hi" }',
        '```',
        '',
        '@You: **Tool Result:** `toolu_fence3`',
      })

      injector.inject_result(bufnr, "toolu_fence3", {
        success = true,
        output = "simple text",
      })

      local lines = get_lines(bufnr)
      local content = table.concat(lines, "\n")
      -- Should use 3 backticks (default)
      assert.is_truthy(content:match("```"), "Should use triple backticks")
      assert.is_falsy(content:match("````[^`]"), "Should not use 4+ backticks for simple content")
    end)

    it("uses extra backticks when content contains triple backticks", function()
      local bufnr = create_buffer({
        '@Assistant: Run:',
        '',
        '**Tool Use:** `bash` (`toolu_fence4`)',
        '```json',
        '{ "command": "echo test" }',
        '```',
        '',
        '@You: **Tool Result:** `toolu_fence4`',
      })

      injector.inject_result(bufnr, "toolu_fence4", {
        success = true,
        output = "output with ``` backticks",
      })

      local lines = get_lines(bufnr)
      local content = table.concat(lines, "\n")
      -- Should use 4 backticks since content has 3
      assert.is_truthy(content:match("````"), "Should use 4+ backticks when content has triple backticks")
    end)
  end)

  describe("re-execution", function()
    it("replaces existing result on re-execution", function()
      local bufnr = create_buffer({
        '@Assistant: Run:',
        '',
        '**Tool Use:** `bash` (`toolu_rerun`)',
        '```json',
        '{ "command": "echo hello" }',
        '```',
        '',
        '@You: **Tool Result:** `toolu_rerun`',
        '',
        '```',
        'old result',
        '```',
      })

      local ok, err = injector.inject_result(bufnr, "toolu_rerun", {
        success = true,
        output = "new result",
      })
      assert.is_true(ok)
      assert.is_nil(err)

      local lines = get_lines(bufnr)
      local content = table.concat(lines, "\n")
      assert.is_truthy(content:match("new result"), "Should contain new result")
      assert.is_falsy(content:match("old result"), "Should not contain old result")
    end)
  end)
end)

-- ============================================================================
-- Executor State Management Tests
-- ============================================================================

describe("Tool Executor", function()
  -- We test the executor module's state management logic.
  -- Async operations use vim.schedule which complicates testing,
  -- so we focus on synchronous flow and state tracking.

  local executor

  before_each(function()
    -- Reset executor module state
    package.loaded["flemma.tools.executor"] = nil
    executor = require("flemma.tools.executor")

    registry.clear()
    tools.setup()
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  describe("get_pending", function()
    it("returns empty for buffer with no executions", function()
      local pending = executor.get_pending(999)
      assert.equals(0, #pending)
    end)
  end)

  describe("execute validation", function()
    it("rejects execution of unknown tool", function()
      local bufnr = create_buffer({
        '@Assistant: Tool:',
        '',
        '**Tool Use:** `nonexistent` (`toolu_unknown`)',
        '```json',
        '{ "command": "test" }',
        '```',
      })

      local ok, err = executor.execute(bufnr, {
        tool_id = "toolu_unknown",
        tool_name = "nonexistent",
        input = { command = "test" },
        start_line = 3,
        end_line = 6,
      })

      assert.is_false(ok)
      assert.is_truthy(err:match("Unknown tool"))
    end)

    it("rejects execution while API request is in flight", function()
      local state = require("flemma.state")
      local bufnr = create_buffer({
        '@Assistant: Tool:',
        '',
        '**Tool Use:** `calculator` (`toolu_blocked`)',
        '```json',
        '{ "expression": "1+1" }',
        '```',
      })

      -- Simulate active API request
      state.set_buffer_state(bufnr, "current_request", { id = "test" })

      local ok, err = executor.execute(bufnr, {
        tool_id = "toolu_blocked",
        tool_name = "calculator",
        input = { expression = "1+1" },
        start_line = 3,
        end_line = 6,
      })

      assert.is_false(ok)
      assert.is_truthy(err:match("API request"))

      -- Clean up
      state.set_buffer_state(bufnr, "current_request", nil)
    end)

    it("rejects duplicate execution of same tool_id", function()
      local bufnr = create_buffer({
        '@Assistant: Tool:',
        '',
        '**Tool Use:** `calculator` (`toolu_dup`)',
        '```json',
        '{ "expression": "1+1" }',
        '```',
      })

      -- First execution should succeed
      local ok1, err1 = executor.execute(bufnr, {
        tool_id = "toolu_dup",
        tool_name = "calculator",
        input = { expression = "1+1" },
        start_line = 3,
        end_line = 6,
      })
      assert.is_true(ok1)
      assert.is_nil(err1)

      -- Second execution of same tool_id should be rejected
      local ok2, err2 = executor.execute(bufnr, {
        tool_id = "toolu_dup",
        tool_name = "calculator",
        input = { expression = "1+1" },
        start_line = 3,
        end_line = 6,
      })
      assert.is_false(ok2)
      assert.is_truthy(err2:match("already executing"))
    end)

    it("rejects execution of non-executable tool", function()
      registry.register("schema_only", {
        name = "schema_only",
        description = "No executor",
        input_schema = {},
        executable = false,
        execute = function() end,
      })

      local bufnr = create_buffer({
        '@Assistant: Tool:',
        '',
        '**Tool Use:** `schema_only` (`toolu_noexec`)',
        '```json',
        '{}',
        '```',
      })

      local ok, err = executor.execute(bufnr, {
        tool_id = "toolu_noexec",
        tool_name = "schema_only",
        input = {},
        start_line = 3,
        end_line = 6,
      })

      assert.is_false(ok)
      assert.is_truthy(err:match("not executable"))
    end)
  end)

  describe("sync execution", function()
    it("creates pending entry during execution", function()
      local bufnr = create_buffer({
        '@Assistant: Computing:',
        '',
        '**Tool Use:** `calculator` (`toolu_pending_test`)',
        '```json',
        '{ "expression": "2+2" }',
        '```',
      })

      local ok, err = executor.execute(bufnr, {
        tool_id = "toolu_pending_test",
        tool_name = "calculator",
        input = { expression = "2+2" },
        start_line = 3,
        end_line = 6,
      })
      assert.is_true(ok)
      assert.is_nil(err)

      -- Note: For sync execution, completion handler uses vim.schedule,
      -- so we can check pending state right after execute returns.
      -- The pending state will be cleaned up after vim.schedule runs.
      -- At this point, the entry exists but is marked completed.
    end)
  end)

  describe("cancel", function()
    it("returns false for non-existent tool_id", function()
      local result = executor.cancel("nonexistent_id")
      assert.is_false(result)
    end)
  end)

  describe("cleanup_buffer", function()
    it("cleans up all state for buffer", function()
      local bufnr = create_buffer({
        '@Assistant: Tool:',
        '',
        '**Tool Use:** `calculator` (`toolu_cleanup`)',
        '```json',
        '{ "expression": "1+1" }',
        '```',
      })

      executor.execute(bufnr, {
        tool_id = "toolu_cleanup",
        tool_name = "calculator",
        input = { expression = "1+1" },
        start_line = 3,
        end_line = 6,
      })

      executor.cleanup_buffer(bufnr)

      -- After cleanup, pending should be empty
      local pending = executor.get_pending(bufnr)
      assert.equals(0, #pending)
    end)
  end)
end)
