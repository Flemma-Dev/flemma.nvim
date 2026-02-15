--- Tests for write tool definition

package.loaded["flemma.tools"] = nil
package.loaded["flemma.tools.registry"] = nil
package.loaded["flemma.tools.definitions.write"] = nil
package.loaded["flemma.sandbox"] = nil
package.loaded["flemma.sandbox.backends.bwrap"] = nil

local tools = require("flemma.tools")
local registry = require("flemma.tools.registry")
local state = require("flemma.state")

describe("Write Tool", function()
  local write_def
  local test_dir

  before_each(function()
    registry.clear()
    tools.setup()
    write_def = registry.get("write")

    -- Create a temp directory
    test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")
  end)

  after_each(function()
    vim.fn.delete(test_dir, "rf")
  end)

  it("is registered on setup", function()
    assert.is_not_nil(write_def)
    assert.equals("write", write_def.name)
    assert.is_false(write_def.async)
  end)

  describe("basic writing", function()
    it("creates a new file", function()
      local path = test_dir .. "/new_file.txt"

      local result = write_def.execute({
        label = "test",
        path = path,
        content = "hello world",
      })
      assert.is_true(result.success)
      assert.is_truthy(result.output:match("11 bytes"))

      -- Verify file content
      local content = table.concat(vim.fn.readfile(path), "\n")
      assert.equals("hello world", content)
    end)

    it("overwrites existing file", function()
      local path = test_dir .. "/existing.txt"
      vim.fn.writefile({ "old content" }, path)

      local result = write_def.execute({
        label = "test",
        path = path,
        content = "new content",
      })
      assert.is_true(result.success)

      local content = table.concat(vim.fn.readfile(path), "\n")
      assert.equals("new content", content)
    end)

    it("creates parent directories", function()
      local path = test_dir .. "/deep/nested/dir/file.txt"

      local result = write_def.execute({
        label = "test",
        path = path,
        content = "nested content",
      })
      assert.is_true(result.success)

      -- Verify file exists
      assert.equals(1, vim.fn.filereadable(path))
      local content = table.concat(vim.fn.readfile(path), "\n")
      assert.equals("nested content", content)
    end)

    it("writes empty content", function()
      local path = test_dir .. "/empty.txt"

      local result = write_def.execute({
        label = "test",
        path = path,
        content = "",
      })
      assert.is_true(result.success)
      assert.is_truthy(result.output:match("0 bytes"))
    end)

    it("writes multiline content", function()
      local path = test_dir .. "/multi.txt"

      local result = write_def.execute({
        label = "test",
        path = path,
        content = "line 1\nline 2\nline 3",
      })
      assert.is_true(result.success)

      local lines = vim.fn.readfile(path)
      assert.equals(3, #lines)
      assert.equals("line 1", lines[1])
      assert.equals("line 3", lines[3])
    end)
  end)

  describe("error cases", function()
    it("returns error for empty path", function()
      local result = write_def.execute({
        label = "test",
        path = "",
        content = "hello",
      })
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("No path"))
    end)

    it("returns error for nil path", function()
      local result = write_def.execute({ label = "test", content = "hello" })
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("No path"))
    end)

    it("returns error for nil content", function()
      local result = write_def.execute({ label = "test", path = test_dir .. "/test.txt" })
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("No content"))
    end)
  end)

  describe("sandbox enforcement", function()
    local sandbox
    local bufnr

    before_each(function()
      package.loaded["flemma.sandbox"] = nil
      package.loaded["flemma.sandbox.backends.bwrap"] = nil
      sandbox = require("flemma.sandbox")
      sandbox.reset_enabled()
      sandbox.clear()

      -- Register a mock backend so sandbox can be fully enabled
      sandbox.register("mock", {
        available = function()
          return true, nil
        end,
        wrap = function(_, _, inner)
          return inner, nil
        end,
        priority = 50,
      })

      bufnr = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
      sandbox.reset_enabled()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("allows writes inside rw_paths", function()
      state.set_config({
        sandbox = {
          enabled = true,
          backend = "mock",
          policy = { rw_paths = { test_dir } },
        },
      })
      local path = test_dir .. "/sandbox_allowed.txt"
      ---@type flemma.tools.ExecutionContext
      local context = { bufnr = bufnr, cwd = vim.fn.getcwd() }

      local result = write_def.execute({
        label = "test",
        path = path,
        content = "sandbox ok",
      }, nil, context)

      assert.is_true(result.success)
      local content = table.concat(vim.fn.readfile(path), "\n")
      assert.equals("sandbox ok", content)
    end)

    it("denies writes outside rw_paths", function()
      state.set_config({
        sandbox = {
          enabled = true,
          backend = "mock",
          policy = { rw_paths = { "/nonexistent/allowed" } },
        },
      })
      local path = test_dir .. "/sandbox_denied.txt"
      ---@type flemma.tools.ExecutionContext
      local context = { bufnr = bufnr, cwd = vim.fn.getcwd() }

      local result = write_def.execute({
        label = "test",
        path = path,
        content = "should not write",
      }, nil, context)

      assert.is_false(result.success)
      assert.is_truthy(result.error:match("Sandbox"))
      assert.is_truthy(result.error:match("write denied"))
      -- File should not exist
      assert.equals(0, vim.fn.filereadable(path))
    end)

    it("allows all writes when sandbox is disabled", function()
      state.set_config({
        sandbox = {
          enabled = false,
          policy = { rw_paths = {} },
        },
      })
      local path = test_dir .. "/sandbox_disabled.txt"
      ---@type flemma.tools.ExecutionContext
      local context = { bufnr = bufnr, cwd = vim.fn.getcwd() }

      local result = write_def.execute({
        label = "test",
        path = path,
        content = "no sandbox",
      }, nil, context)

      assert.is_true(result.success)
    end)

    it("respects per-buffer sandbox overrides via context.opts", function()
      -- Global config: sandbox disabled
      state.set_config({
        sandbox = {
          enabled = false,
          backend = "mock",
          policy = { rw_paths = { "/nonexistent/allowed" } },
        },
      })
      local path = test_dir .. "/buffer_override.txt"
      ---@type flemma.tools.ExecutionContext
      local context = {
        bufnr = bufnr,
        cwd = vim.fn.getcwd(),
        opts = {
          sandbox = {
            enabled = true,
            policy = { rw_paths = { "/nonexistent/allowed" } },
          },
        },
      }

      local result = write_def.execute({
        label = "test",
        path = path,
        content = "denied by buffer override",
      }, nil, context)

      assert.is_false(result.success)
      assert.is_truthy(result.error:match("Sandbox"))
    end)

    it("works without context (no sandbox enforcement)", function()
      -- When no context is provided, falls back to get_current_buf
      -- and no opts — sandbox enforcement depends on global config
      state.set_config({
        sandbox = {
          enabled = false,
          policy = { rw_paths = {} },
        },
      })
      local path = test_dir .. "/no_context.txt"

      local result = write_def.execute({
        label = "test",
        path = path,
        content = "no context",
      })

      assert.is_true(result.success)
    end)
  end)
end)
