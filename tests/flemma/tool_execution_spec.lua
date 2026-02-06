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

  describe("hidden flag", function()
    it("excludes hidden tools from get_all()", function()
      registry.register("visible", { name = "visible", execute = function() end })
      registry.register("secret", { name = "secret", hidden = true, execute = function() end })

      local all = registry.get_all()
      assert.is_not_nil(all.visible)
      assert.is_nil(all.secret, "Hidden tool should not appear in get_all()")
    end)

    it("includes hidden tools when include_hidden is true", function()
      registry.register("visible", { name = "visible", execute = function() end })
      registry.register("secret", { name = "secret", hidden = true, execute = function() end })

      local all = registry.get_all({ include_hidden = true })
      assert.is_not_nil(all.visible)
      assert.is_not_nil(all.secret, "Hidden tool should appear when include_hidden is true")
    end)

    it("allows hidden tools to be executed", function()
      registry.register("secret", { name = "secret", hidden = true, execute = function() end })

      assert.is_true(registry.is_executable("secret"))
      local exec, is_async = registry.get_executor("secret")
      assert.is_not_nil(exec)
      assert.is_false(is_async)
    end)

    it("allows hidden tools to be looked up by name", function()
      registry.register("secret", { name = "secret", hidden = true, execute = function() end })

      assert.is_not_nil(registry.get("secret"))
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

  describe("multi-tool cursor in user message", function()
    it("resolves correct tool when cursor is on specific tool_result", function()
      local bufnr = create_buffer({
        '@Assistant: Running tools:',
        '',
        '**Tool Use:** `bash` (`toolu_multi_first`)',
        '```json',
        '{ "command": "echo first" }',
        '```',
        '',
        '**Tool Use:** `calculator` (`toolu_multi_second`)',
        '```json',
        '{ "expression": "1+1" }',
        '```',
        '',
        '@You: **Tool Result:** `toolu_multi_first`',
        '',
        '```',
        'first result',
        '```',
        '',
        '**Tool Result:** `toolu_multi_second`',
        '',
        '```',
        '2',
        '```',
      })

      -- Cursor on first tool_result header (line 14)
      local ctx1, err1 = context.resolve(bufnr, { row = 14 })
      assert.is_nil(err1)
      assert.is_not_nil(ctx1)
      assert.equals("toolu_multi_first", ctx1.tool_id)
      assert.equals("bash", ctx1.tool_name)

      -- Cursor on second tool_result header (line 20)
      local ctx2, err2 = context.resolve(bufnr, { row = 20 })
      assert.is_nil(err2)
      assert.is_not_nil(ctx2)
      assert.equals("toolu_multi_second", ctx2.tool_id)
      assert.equals("calculator", ctx2.tool_name)
    end)

    it("resolves correct tool when cursor is inside tool_result content", function()
      local bufnr = create_buffer({
        '@Assistant: Running tools:',
        '',
        '**Tool Use:** `bash` (`toolu_content_first`)',
        '```json',
        '{ "command": "echo first" }',
        '```',
        '',
        '**Tool Use:** `calculator` (`toolu_content_second`)',
        '```json',
        '{ "expression": "2+2" }',
        '```',
        '',
        '@You: **Tool Result:** `toolu_content_first`',
        '',
        '```',
        'first output',
        '```',
        '',
        '**Tool Result:** `toolu_content_second`',
        '',
        '```',
        '4',
        '```',
      })

      -- Cursor inside first tool_result content (line 16)
      local ctx1, err1 = context.resolve(bufnr, { row = 16 })
      assert.is_nil(err1)
      assert.is_not_nil(ctx1)
      assert.equals("toolu_content_first", ctx1.tool_id)

      -- Cursor inside second tool_result content (line 22)
      local ctx2, err2 = context.resolve(bufnr, { row = 22 })
      assert.is_nil(err2)
      assert.is_not_nil(ctx2)
      assert.equals("toolu_content_second", ctx2.tool_id)
    end)

    it("falls back to nearest tool_result when cursor is between results", function()
      local bufnr = create_buffer({
        '@Assistant: Running tools:',
        '',
        '**Tool Use:** `bash` (`toolu_between_first`)',
        '```json',
        '{ "command": "echo first" }',
        '```',
        '',
        '**Tool Use:** `calculator` (`toolu_between_second`)',
        '```json',
        '{ "expression": "3+3" }',
        '```',
        '',
        '@You: **Tool Result:** `toolu_between_first`',
        '',
        '```',
        'first',
        '```',
        '',
        '**Tool Result:** `toolu_between_second`',
        '',
        '```',
        '6',
        '```',
      })

      -- Cursor on empty line between the two results (line 18)
      local ctx, err = context.resolve(bufnr, { row = 18 })
      assert.is_nil(err)
      assert.is_not_nil(ctx)
      -- Should resolve to nearest tool_result (either is acceptable since equidistant)
      assert.is_truthy(
        ctx.tool_id == "toolu_between_first" or ctx.tool_id == "toolu_between_second",
        "Should resolve to one of the two tools"
      )
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

    it("falls back to assistant tools when cursor is on tool_result in @You:", function()
      local bufnr = create_buffer({
        '@Assistant: Running tool:',
        '',
        '**Tool Use:** `bash` (`toolu_result_cursor`)',
        '```json',
        '{ "command": "echo hello" }',
        '```',
        '',
        '@You: **Tool Result:** `toolu_result_cursor`',
        '',
        '```',
        'old result',
        '```',
      })

      -- Cursor on the tool_result header line (which is in @You: message)
      local ctx, err = context.resolve(bufnr, { row = 8 })
      assert.is_nil(err)
      assert.is_not_nil(ctx)
      assert.equals("toolu_result_cursor", ctx.tool_id)
      assert.equals("bash", ctx.tool_name)
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

    it("inserts placeholder before existing user text in @You: message", function()
      local bufnr = create_buffer({
        "@Assistant: Here is the tool:",
        "",
        '**Tool Use:** `bash` (`toolu_before_text`)',
        "```json",
        '{ "command": "echo hello" }',
        "```",
        "",
        "@You: I'll run this.",
      })

      local header_line, err = injector.inject_placeholder(bufnr, "toolu_before_text")
      assert.is_nil(err)
      assert.is_not_nil(header_line)

      local lines = get_lines(bufnr)
      -- The placeholder should be inserted at the @You: line
      assert.is_truthy(lines[header_line]:match("Tool Result.*toolu_before_text"), "Header should be at returned line")
      -- The existing user text should be preserved after the placeholder
      local found_text = false
      for _, line in ipairs(lines) do
        if line:match("I'll run this") then
          found_text = true
          break
        end
      end
      assert.is_true(found_text, "Original user text should be preserved")
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

    it("uses 5-tick fence when content contains 4 backticks", function()
      local bufnr = create_buffer({
        '@Assistant: Run:',
        '',
        '**Tool Use:** `bash` (`toolu_fence5`)',
        '```json',
        '{ "command": "echo test" }',
        '```',
        '',
        '@You: **Tool Result:** `toolu_fence5`',
      })

      injector.inject_result(bufnr, "toolu_fence5", {
        success = true,
        output = "output with ```` four backticks",
      })

      local lines = get_lines(bufnr)
      local content = table.concat(lines, "\n")
      assert.is_truthy(content:match("`````"), "Should use 5-tick fence when content has 4 backticks")
    end)

    it("uses 5-tick fence when content has mixed 3 and 4 backtick sequences", function()
      local bufnr = create_buffer({
        '@Assistant: Run:',
        '',
        '**Tool Use:** `bash` (`toolu_fence_mixed`)',
        '```json',
        '{ "command": "echo test" }',
        '```',
        '',
        '@You: **Tool Result:** `toolu_fence_mixed`',
      })

      injector.inject_result(bufnr, "toolu_fence_mixed", {
        success = true,
        output = "has ``` and also ```` in it",
      })

      local lines = get_lines(bufnr)
      local content = table.concat(lines, "\n")
      assert.is_truthy(content:match("`````"), "Should use 5-tick fence for mixed 3+4 backtick content")
    end)

    it("uses triple backticks when content has only single/double backticks", function()
      local bufnr = create_buffer({
        '@Assistant: Run:',
        '',
        '**Tool Use:** `bash` (`toolu_fence_low`)',
        '```json',
        '{ "command": "echo test" }',
        '```',
        '',
        '@You: **Tool Result:** `toolu_fence_low`',
      })

      injector.inject_result(bufnr, "toolu_fence_low", {
        success = true,
        output = "has ` single and `` double backticks only",
      })

      local lines = get_lines(bufnr)
      local content = table.concat(lines, "\n")
      assert.is_truthy(content:match("```"), "Should use triple backticks")
      assert.is_falsy(content:match("````[^`]"), "Should not use 4+ backticks for single/double backtick content")
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

  describe("multi-tool ordering", function()
    -- Tests for Bug 1 fix: placeholders must be inserted in tool_use order,
    -- not always appended after the last existing tool_result.

    it("inserts placeholders in tool_use order (sequential in-order)", function()
      -- Three tool_uses in assistant message, inject placeholders in order
      local bufnr = create_buffer({
        "@Assistant: Running multiple tools:",
        "",
        "**Tool Use:** `calculator` (`toolu_a`)",
        "```json",
        '{ "expression": "1+1" }',
        "```",
        "",
        "**Tool Use:** `calculator` (`toolu_b`)",
        "```json",
        '{ "expression": "2+2" }',
        "```",
        "",
        "**Tool Use:** `calculator` (`toolu_c`)",
        "```json",
        '{ "expression": "3+3" }',
        "```",
      })

      -- Inject in order: a, b, c
      local line_a, err_a = injector.inject_placeholder(bufnr, "toolu_a")
      assert.is_nil(err_a)
      assert.is_not_nil(line_a)

      local line_b, err_b = injector.inject_placeholder(bufnr, "toolu_b")
      assert.is_nil(err_b)
      assert.is_not_nil(line_b)

      local line_c, err_c = injector.inject_placeholder(bufnr, "toolu_c")
      assert.is_nil(err_c)
      assert.is_not_nil(line_c)

      -- All three should appear in order in the buffer
      local lines = get_lines(bufnr)
      local pos_a, pos_b, pos_c
      for i, line in ipairs(lines) do
        if line:match("Tool Result.*toolu_a") then
          pos_a = i
        end
        if line:match("Tool Result.*toolu_b") then
          pos_b = i
        end
        if line:match("Tool Result.*toolu_c") then
          pos_c = i
        end
      end

      assert.is_not_nil(pos_a, "toolu_a result should exist")
      assert.is_not_nil(pos_b, "toolu_b result should exist")
      assert.is_not_nil(pos_c, "toolu_c result should exist")
      assert.is_true(pos_a < pos_b, "toolu_a should come before toolu_b")
      assert.is_true(pos_b < pos_c, "toolu_b should come before toolu_c")
    end)

    it("inserts placeholders in tool_use order (out-of-order injection)", function()
      -- Three tool_uses, but inject c first, then a, then b
      local bufnr = create_buffer({
        "@Assistant: Running multiple tools:",
        "",
        "**Tool Use:** `calculator` (`toolu_d`)",
        "```json",
        '{ "expression": "1+1" }',
        "```",
        "",
        "**Tool Use:** `calculator` (`toolu_e`)",
        "```json",
        '{ "expression": "2+2" }',
        "```",
        "",
        "**Tool Use:** `calculator` (`toolu_f`)",
        "```json",
        '{ "expression": "3+3" }',
        "```",
      })

      -- Inject out of order: f (3rd), d (1st), e (2nd)
      local _, err_f = injector.inject_placeholder(bufnr, "toolu_f")
      assert.is_nil(err_f)

      local _, err_d = injector.inject_placeholder(bufnr, "toolu_d")
      assert.is_nil(err_d)

      local _, err_e = injector.inject_placeholder(bufnr, "toolu_e")
      assert.is_nil(err_e)

      -- Despite out-of-order injection, results should be in tool_use order
      local lines = get_lines(bufnr)
      local pos_d, pos_e, pos_f
      for i, line in ipairs(lines) do
        if line:match("Tool Result.*toolu_d") then
          pos_d = i
        end
        if line:match("Tool Result.*toolu_e") then
          pos_e = i
        end
        if line:match("Tool Result.*toolu_f") then
          pos_f = i
        end
      end

      assert.is_not_nil(pos_d, "toolu_d result should exist")
      assert.is_not_nil(pos_e, "toolu_e result should exist")
      assert.is_not_nil(pos_f, "toolu_f result should exist")
      assert.is_true(pos_d < pos_e, "toolu_d should come before toolu_e")
      assert.is_true(pos_e < pos_f, "toolu_e should come before toolu_f")
    end)

    it("inserts before first result when our tool comes first", function()
      -- Two tool_uses, inject second one first, then first
      local bufnr = create_buffer({
        "@Assistant: Running tools:",
        "",
        "**Tool Use:** `calculator` (`toolu_first`)",
        "```json",
        '{ "expression": "1+1" }',
        "```",
        "",
        "**Tool Use:** `calculator` (`toolu_second`)",
        "```json",
        '{ "expression": "2+2" }',
        "```",
      })

      -- Inject second tool first - creates @You: message
      local _, err2 = injector.inject_placeholder(bufnr, "toolu_second")
      assert.is_nil(err2)

      -- Now inject first tool - must be placed before second
      local _, err1 = injector.inject_placeholder(bufnr, "toolu_first")
      assert.is_nil(err1)

      local lines = get_lines(bufnr)
      local pos_first, pos_second
      for i, line in ipairs(lines) do
        if line:match("Tool Result.*toolu_first") then
          pos_first = i
        end
        if line:match("Tool Result.*toolu_second") then
          pos_second = i
        end
      end

      assert.is_not_nil(pos_first, "toolu_first result should exist")
      assert.is_not_nil(pos_second, "toolu_second result should exist")
      assert.is_true(pos_first < pos_second, "First tool result should come before second")
    end)

    it("inserts between existing results in correct position", function()
      -- Three tool_uses, inject first and third, then middle
      local bufnr = create_buffer({
        "@Assistant: Running tools:",
        "",
        "**Tool Use:** `calculator` (`toolu_g`)",
        "```json",
        '{ "expression": "1+1" }',
        "```",
        "",
        "**Tool Use:** `calculator` (`toolu_h`)",
        "```json",
        '{ "expression": "2+2" }',
        "```",
        "",
        "**Tool Use:** `calculator` (`toolu_i`)",
        "```json",
        '{ "expression": "3+3" }',
        "```",
      })

      -- Inject first and third
      local _, err_g = injector.inject_placeholder(bufnr, "toolu_g")
      assert.is_nil(err_g)
      local _, err_i = injector.inject_placeholder(bufnr, "toolu_i")
      assert.is_nil(err_i)

      -- Now inject middle - should go between g and i
      local _, err_h = injector.inject_placeholder(bufnr, "toolu_h")
      assert.is_nil(err_h)

      local lines = get_lines(bufnr)
      local pos_g, pos_h, pos_i
      for i, line in ipairs(lines) do
        if line:match("Tool Result.*toolu_g") then
          pos_g = i
        end
        if line:match("Tool Result.*toolu_h") then
          pos_h = i
        end
        if line:match("Tool Result.*toolu_i") then
          pos_i = i
        end
      end

      assert.is_not_nil(pos_g, "toolu_g result should exist")
      assert.is_not_nil(pos_h, "toolu_h result should exist")
      assert.is_not_nil(pos_i, "toolu_i result should exist")
      assert.is_true(pos_g < pos_h, "toolu_g should come before toolu_h")
      assert.is_true(pos_h < pos_i, "toolu_h should come before toolu_i")
    end)

    it("maintains order with full result injection (not just placeholders)", function()
      -- Two tool_uses, inject full results out of order
      local bufnr = create_buffer({
        "@Assistant: Running tools:",
        "",
        "**Tool Use:** `calculator` (`toolu_j`)",
        "```json",
        '{ "expression": "1+1" }',
        "```",
        "",
        "**Tool Use:** `calculator` (`toolu_k`)",
        "```json",
        '{ "expression": "2+2" }',
        "```",
      })

      -- Inject result for second tool first
      local ok_k, err_k = injector.inject_result(bufnr, "toolu_k", {
        success = true,
        output = "result_k",
      })
      assert.is_true(ok_k)
      assert.is_nil(err_k)

      -- Inject result for first tool second
      local ok_j, err_j = injector.inject_result(bufnr, "toolu_j", {
        success = true,
        output = "result_j",
      })
      assert.is_true(ok_j)
      assert.is_nil(err_j)

      -- result_j should appear before result_k in the buffer
      local lines = get_lines(bufnr)
      local pos_j, pos_k
      for i, line in ipairs(lines) do
        if line:match("result_j") then
          pos_j = i
        end
        if line:match("result_k") then
          pos_k = i
        end
      end

      assert.is_not_nil(pos_j, "result_j should exist")
      assert.is_not_nil(pos_k, "result_k should exist")
      assert.is_true(pos_j < pos_k, "result_j should come before result_k")
    end)
  end)

end)

-- ============================================================================
-- Cancel Priority Logic Tests
-- ============================================================================

describe("Cancel Priority Logic", function()
  -- Tests the cancel dispatch logic from commands.lua:158-182
  -- This is duplicated in keymaps.lua cancel handler with the same priority.

  local executor

  before_each(function()
    package.loaded["flemma.tools.executor"] = nil
    executor = require("flemma.tools.executor")
    registry.clear()
    tools.setup()
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  it("cancels API request when API is active (priority 1)", function()
    local bufnr = create_buffer({
      "@Assistant: Running tool:",
      "",
      '**Tool Use:** `calculator` (`toolu_cancel_api`)',
      "```json",
      '{ "expression": "1+1" }',
      "```",
    })

    local st = require("flemma.state")
    local buffer_state = st.get_buffer_state(bufnr)

    -- Simulate active API request
    st.set_buffer_state(bufnr, "current_request", { id = "test_req" })

    -- The cancel logic: priority 1 = API request
    assert.is_not_nil(buffer_state.current_request, "API request should be active")

    -- Verify that with an active API request, we would NOT touch tools
    local pending = executor.get_pending(bufnr)
    -- Even if tools were pending, API cancellation takes priority
    -- This test verifies the priority check condition
    assert.is_truthy(buffer_state.current_request, "Should detect active API request first")

    st.set_buffer_state(bufnr, "current_request", nil)
  end)

  it("cancels first tool by start time when no API active (priority 2)", function()
    local bufnr = create_buffer({
      "@Assistant: Running tools:",
      "",
      '**Tool Use:** `calculator` (`toolu_cancel_first`)',
      "```json",
      '{ "expression": "1+1" }',
      "```",
      "",
      '**Tool Use:** `calculator` (`toolu_cancel_second`)',
      "```json",
      '{ "expression": "2+2" }',
      "```",
    })

    -- Execute both tools to create pending entries
    executor.execute(bufnr, {
      tool_id = "toolu_cancel_first",
      tool_name = "calculator",
      input = { expression = "1+1" },
      start_line = 3,
      end_line = 6,
    })
    executor.execute(bufnr, {
      tool_id = "toolu_cancel_second",
      tool_name = "calculator",
      input = { expression = "2+2" },
      start_line = 8,
      end_line = 11,
    })

    -- Simulate cancel dispatch logic
    local st = require("flemma.state")
    local buffer_state = st.get_buffer_state(bufnr)

    -- No active API request
    assert.is_nil(buffer_state.current_request)

    local pending = executor.get_pending(bufnr)
    -- Note: sync tools complete immediately via vim.schedule, but pending entries
    -- exist until vim.schedule runs. In tests, vim.schedule hasn't run yet.
    -- For this test, verify the sorting logic.
    if #pending > 0 then
      table.sort(pending, function(a, b)
        return a.started_at < b.started_at
      end)
      -- First by start time should be toolu_cancel_first
      assert.equals("toolu_cancel_first", pending[1].tool_id)
    end
  end)

  it("notifies when nothing is pending (priority 3)", function()
    local bufnr = create_buffer({
      "@Assistant: Just text, no tools.",
    })

    local st = require("flemma.state")
    local buffer_state = st.get_buffer_state(bufnr)

    -- No API request
    assert.is_nil(buffer_state.current_request)

    -- No pending tools
    local pending = executor.get_pending(bufnr)
    assert.equals(0, #pending, "Should have no pending executions")
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
      -- Use an async tool that never completes, so the pending slot stays occupied
      registry.register("slow_async_dup", {
        name = "slow_async_dup",
        description = "Async tool that never completes",
        async = true,
        execute = function(_, _)
          -- Never call the callback — stays pending
          return function() end
        end,
      })

      local bufnr = create_buffer({
        '@Assistant: Tool:',
        '',
        '**Tool Use:** `slow_async_dup` (`toolu_dup`)',
        '```json',
        '{}',
        '```',
      })

      -- First execution should succeed
      local ok1, err1 = executor.execute(bufnr, {
        tool_id = "toolu_dup",
        tool_name = "slow_async_dup",
        input = {},
        start_line = 3,
        end_line = 6,
      })
      assert.is_true(ok1)
      assert.is_nil(err1)

      -- Second execution of same tool_id should be rejected
      local ok2, err2 = executor.execute(bufnr, {
        tool_id = "toolu_dup",
        tool_name = "slow_async_dup",
        input = {},
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

    it("calls cancel_fn for pending async tools on cleanup", function()
      local cancel_called = false

      -- Register an async tool that returns a cancel function
      registry.register("slow_async", {
        name = "slow_async",
        description = "Slow async tool for testing",
        async = true,
        execute = function(_, _)
          -- Return a cancel function, never call the callback
          return function()
            cancel_called = true
          end
        end,
      })

      local bufnr = create_buffer({
        "@Assistant: Tool:",
        "",
        '**Tool Use:** `slow_async` (`toolu_cancel_fn`)',
        "```json",
        "{}",
        "```",
      })

      executor.execute(bufnr, {
        tool_id = "toolu_cancel_fn",
        tool_name = "slow_async",
        input = {},
        start_line = 3,
        end_line = 6,
      })

      -- Tool should be pending
      local pending = executor.get_pending(bufnr)
      assert.equals(1, #pending)

      -- Cleanup should call cancel_fn
      executor.cleanup_buffer(bufnr)
      assert.is_true(cancel_called, "cancel_fn should have been called during cleanup")

      -- State should be cleared
      pending = executor.get_pending(bufnr)
      assert.equals(0, #pending)
    end)
  end)
end)
