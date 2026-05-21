--- Tests for bash tool definition

package.loaded["flemma.tools.definitions.builtin.bash"] = nil
package.loaded["flemma.utilities.truncate"] = nil
package.loaded["flemma.utilities.json"] = nil

local executor = require("flemma.tools.executor")
local bash_module = require("flemma.tools.definitions.builtin.bash")
local truncate = require("flemma.utilities.truncate")

local HAS_TERMINAL_PTY_FIX = vim.fn.has("nvim-0.12") == 1

describe("Bash Tool", function()
  local bash_def, bufnr, ctx

  before_each(function()
    bash_def = bash_module.definitions[1]
    bufnr = vim.api.nvim_create_buf(false, true)
    ctx = executor.build_execution_context({
      bufnr = bufnr,
      cwd = vim.fn.getcwd(),
      timeout = 30,
      tool_name = "bash",
    })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("has correct metadata", function()
    assert.is_not_nil(bash_def)
    assert.equals("bash", bash_def.name)
    assert.is_true(bash_def.async)
  end)

  it("declares can_auto_approve_if_sandboxed capability", function()
    assert.is_truthy(vim.tbl_contains(bash_def.capabilities, "can_auto_approve_if_sandboxed"))
  end)

  describe("execution", function()
    ---@param input table<string, any>
    ---@param execution_ctx flemma.tools.ExecutionContext
    ---@return flemma.tools.ExecutionResult
    local function run_bash(input, execution_ctx)
      local result = nil
      bash_def.execute(input, execution_ctx, function(r)
        result = r
      end)
      vim.wait(10000, function()
        return result ~= nil
      end, 50)
      assert.is_not_nil(result, "bash did not complete within timeout")
      return result
    end

    it("executes a simple command and returns output", function()
      local result = run_bash({ label = "test", command = "echo hello" }, ctx)
      assert.is_true(result.success)
      assert.equals("hello", result.output)
    end)

    it("returns error for empty command", function()
      local result = nil
      bash_def.execute({ label = "test", command = "" }, ctx, function(r)
        result = r
      end)
      assert.is_not_nil(result)
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("No command"))
    end)

    it("returns error for nil command", function()
      local result = nil
      bash_def.execute({ label = "test" }, ctx, function(r)
        result = r
      end)
      assert.is_not_nil(result)
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("No command"))
    end)

    it("reports non-zero exit code", function()
      local result = run_bash({ label = "test", command = "exit 42" }, ctx)
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("Command exited with code 42"))
    end)

    it("captures stderr merged with stdout", function()
      local result = run_bash({ label = "test", command = "echo out; echo err >&2" }, ctx)
      assert.is_true(result.success)
      assert.is_truthy(result.output:match("out"))
      assert.is_truthy(result.output:match("err"))
    end)

    it("truncates output exceeding MAX_LINES and writes overflow file", function()
      local line_count = truncate.MAX_LINES + 500
      local cmd = string.format('for i in $(seq 1 %d); do echo "line $i"; done', line_count)
      local result = run_bash({ label = "test", command = cmd }, ctx)
      assert.is_true(result.success)
      -- Output should be truncated (showing lines X-Y of Z)
      assert.is_truthy(result.output:match("%[Showing lines"))
      -- Should mention the full output file
      assert.is_truthy(result.output:match("Full output:"))
    end)

    it("returns cancel function that stops the job", function()
      local result = nil
      local cancel = bash_def.execute({ label = "test", command = "sleep 60" }, ctx, function(r)
        result = r
      end)
      assert.is_function(cancel)
      cancel()
      -- After cancel, no callback fires (job was killed before exit)
      vim.wait(500, function()
        return result ~= nil
      end, 50)
    end)
  end)

  describe("format_preview", function()
    it("shows label and command", function()
      local preview = bash_def.format_preview({ label = "running tests", command = "make test" })
      assert.equals("running tests", preview.label)
      assert.equals("$ make test", preview.detail)
    end)
  end)

  -- Terminal buffer tests only apply on 0.12+ where the termopen backend is used.
  -- On 0.11.x, the jobstart+sink backend has no terminal buffer to inspect.
  describe("terminal buffer", function()
    ---@param input table<string, any>
    ---@param execution_ctx flemma.tools.ExecutionContext
    ---@return flemma.tools.ExecutionResult
    local function run_bash(input, execution_ctx)
      local result = nil
      bash_def.execute(input, execution_ctx, function(r)
        result = r
      end)
      vim.wait(10000, function()
        return result ~= nil
      end, 50)
      assert.is_not_nil(result, "bash did not complete within timeout")
      return result
    end

    ---Find any terminal buffers created by Flemma bash tool.
    ---@return integer[]
    local function find_terminal_buffers()
      local result = {}
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(b) then
          local name = vim.api.nvim_buf_get_name(b)
          if name:match("^flemma://terminal/bash/") then
            table.insert(result, b)
          end
        end
      end
      return result
    end

    it("cleans up terminal buffer after completion", function()
      if not HAS_TERMINAL_PTY_FIX then
        pending("requires Neovim 0.12+ (termopen backend)")
        return
      end
      local before = find_terminal_buffers()
      run_bash({ label = "test", command = "echo cleanup" }, ctx)
      local after = find_terminal_buffers()
      assert.equals(#before, #after)
    end)

    it("defers cleanup when terminal buffer is visible in a window", function()
      if not HAS_TERMINAL_PTY_FIX then
        pending("requires Neovim 0.12+ (termopen backend)")
        return
      end
      local term_buf = nil
      local result = nil

      -- Start a long-running command
      bash_def.execute({ label = "visible", command = "sleep 2" }, ctx, function(r)
        result = r
      end)

      -- Find the terminal buffer while the command is running
      vim.wait(1000, function()
        local bufs = find_terminal_buffers()
        if #bufs > 0 then
          term_buf = bufs[1]
          return true
        end
        return false
      end, 50)
      assert.is_not_nil(term_buf, "terminal buffer was not found while command was running")

      -- Display the terminal buffer in a window
      vim.cmd("split")
      vim.api.nvim_set_current_buf(term_buf)

      -- Wait for the command to finish
      vim.wait(10000, function()
        return result ~= nil
      end, 50)

      -- Buffer should still exist (deferred wipe via bufhidden)
      assert.is_true(vim.api.nvim_buf_is_valid(term_buf))
      assert.equals("wipe", vim.bo[term_buf].bufhidden)

      -- Close the window to trigger wipe
      vim.cmd("close")
      -- Buffer should now be gone
      assert.is_false(vim.api.nvim_buf_is_valid(term_buf))
    end)

    it("sets scrollback to the Neovim maximum on the terminal buffer", function()
      if not HAS_TERMINAL_PTY_FIX then
        pending("requires Neovim 0.12+ (termopen backend)")
        return
      end
      local term_buf = nil

      bash_def.execute({ label = "scrollback", command = "sleep 2" }, ctx, function() end)

      vim.wait(1000, function()
        local bufs = find_terminal_buffers()
        if #bufs > 0 then
          term_buf = bufs[1]
          return true
        end
        return false
      end, 50)
      assert.is_not_nil(term_buf, "terminal buffer was not found while command was running")
      -- -1 resolves to SB_MAX (100K on 0.11, 1M on 0.12+); assert it expanded.
      local sb = vim.bo[term_buf].scrollback
      assert.is_true(sb >= 100000, "scrollback should be at least 100000, got " .. tostring(sb))
    end)

    it("uses explicit shell from list form, not user $SHELL", function()
      if not HAS_TERMINAL_PTY_FIX then
        pending("requires Neovim 0.12+ (termopen backend)")
        return
      end
      local result = run_bash({ label = "test", command = "echo $0" }, ctx)
      assert.is_true(result.success)
      assert.is_truthy(result.output:match("bash"))
    end)

    it("does not block on interactive stdin (read gets immediate EOF)", function()
      if not HAS_TERMINAL_PTY_FIX then
        pending("requires Neovim 0.12+ (termopen backend)")
        return
      end
      local short_ctx = executor.build_execution_context({
        bufnr = bufnr,
        cwd = vim.fn.getcwd(),
        timeout = 3,
        tool_name = "bash",
      })
      -- `read` without -t blocks on a TTY waiting for input. With stdin
      -- redirected from /dev/null it gets immediate EOF and continues.
      -- The 3s timeout catches the blocking case as a failure.
      local result = run_bash({ label = "test", command = "read line || true; echo done" }, short_ctx)
      assert.is_truthy(result)
      assert.is_true(result.success)
      assert.is_truthy(result.output:match("done"))
    end)
  end)
end)
