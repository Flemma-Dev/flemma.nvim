--- Tests for write tool definition

package.loaded["flemma.tools"] = nil
package.loaded["flemma.tools.approval"] = nil
package.loaded["flemma.tools.registry"] = nil
package.loaded["flemma.tools.executor"] = nil
package.loaded["flemma.tools.definitions.write"] = nil
package.loaded["flemma.sandbox"] = nil
package.loaded["flemma.sandbox.backends.bwrap"] = nil

local tools = require("flemma.tools")
local registry = require("flemma.tools.registry")
local executor = require("flemma.tools.executor")
local config_facade = require("flemma.config")
local schema = require("flemma.config.schema.definition")

describe("Write Tool", function()
  local write_def
  local test_dir
  local bufnr
  local ctx

  before_each(function()
    registry.clear()
    tools.setup()
    write_def = registry.get("write")

    -- Create a temp directory
    test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")

    bufnr = vim.api.nvim_create_buf(false, true)
    ctx = executor.build_execution_context({
      bufnr = bufnr,
      cwd = vim.fn.getcwd(),
      timeout = 30,
      tool_name = "write",
    })
  end)

  after_each(function()
    vim.fn.delete(test_dir, "rf")
    vim.api.nvim_buf_delete(bufnr, { force = true })
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
      }, ctx)
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
      }, ctx)
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
      }, ctx)
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
      }, ctx)
      assert.is_true(result.success)
      assert.is_truthy(result.output:match("0 bytes"))
    end)

    it("writes multiline content", function()
      local path = test_dir .. "/multi.txt"

      local result = write_def.execute({
        label = "test",
        path = path,
        content = "line 1\nline 2\nline 3",
      }, ctx)
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
      }, ctx)
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("No path"))
    end)

    it("returns error for nil path", function()
      local result = write_def.execute({ label = "test", content = "hello" }, ctx)
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("No path"))
    end)

    it("returns error for nil content", function()
      local result = write_def.execute({ label = "test", path = test_dir .. "/test.txt" }, ctx)
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("No content"))
    end)
  end)

  describe("sandbox enforcement", function()
    local sandbox
    local sandbox_bufnr

    before_each(function()
      package.loaded["flemma.sandbox"] = nil
      package.loaded["flemma.sandbox.backends.bwrap"] = nil
      package.loaded["flemma.tools.approval"] = nil
      package.loaded["flemma.tools.executor"] = nil
      package.loaded["flemma.config"] = nil
      package.loaded["flemma.config.store"] = nil
      package.loaded["flemma.config.proxy"] = nil
      package.loaded["flemma.config.schema.definition"] = nil
      sandbox = require("flemma.sandbox")
      executor = require("flemma.tools.executor")
      config_facade = require("flemma.config")
      schema = require("flemma.config.schema.definition")
      config_facade.init(schema)
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

      sandbox_bufnr = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
      sandbox.reset_enabled()
      vim.api.nvim_buf_delete(sandbox_bufnr, { force = true })
    end)

    it("allows writes inside rw_paths", function()
      config_facade.apply(config_facade.LAYERS.SETUP, {
        sandbox = {
          enabled = true,
          backend = "mock",
          policy = { rw_paths = { test_dir } },
        },
      })
      local path = test_dir .. "/sandbox_allowed.txt"
      local context = executor.build_execution_context({
        bufnr = sandbox_bufnr,
        cwd = vim.fn.getcwd(),
        timeout = 30,
        tool_name = "write",
      })

      local result = write_def.execute({
        label = "test",
        path = path,
        content = "sandbox ok",
      }, context)

      assert.is_true(result.success)
      local content = table.concat(vim.fn.readfile(path), "\n")
      assert.equals("sandbox ok", content)
    end)

    it("denies writes outside rw_paths", function()
      config_facade.apply(config_facade.LAYERS.SETUP, {
        sandbox = {
          enabled = true,
          backend = "mock",
          policy = { rw_paths = { "/nonexistent/allowed" } },
        },
      })
      local path = test_dir .. "/sandbox_denied.txt"
      local context = executor.build_execution_context({
        bufnr = sandbox_bufnr,
        cwd = vim.fn.getcwd(),
        timeout = 30,
        tool_name = "write",
      })

      local result = write_def.execute({
        label = "test",
        path = path,
        content = "should not write",
      }, context)

      assert.is_false(result.success)
      assert.is_truthy(result.error:match("Sandbox"))
      assert.is_truthy(result.error:match("write denied"))
      -- File should not exist
      assert.equals(0, vim.fn.filereadable(path))
    end)

    it("allows all writes when sandbox is disabled", function()
      config_facade.apply(config_facade.LAYERS.SETUP, {
        sandbox = {
          enabled = false,
          policy = { rw_paths = {} },
        },
      })
      local path = test_dir .. "/sandbox_disabled.txt"
      local context = executor.build_execution_context({
        bufnr = sandbox_bufnr,
        cwd = vim.fn.getcwd(),
        timeout = 30,
        tool_name = "write",
      })

      local result = write_def.execute({
        label = "test",
        path = path,
        content = "no sandbox",
      }, context)

      assert.is_true(result.success)
    end)

    it("respects per-buffer sandbox overrides via frontmatter", function()
      -- Global config: sandbox disabled
      config_facade.apply(config_facade.LAYERS.SETUP, {
        sandbox = {
          enabled = false,
          backend = "mock",
          policy = { rw_paths = { "/nonexistent/allowed" } },
        },
      })
      -- Per-buffer frontmatter: sandbox enabled with restricted paths
      local w = config_facade.writer(sandbox_bufnr, config_facade.LAYERS.FRONTMATTER)
      w.sandbox.enabled = true
      w.sandbox.policy.rw_paths = { "/nonexistent/allowed" }

      local path = test_dir .. "/buffer_override.txt"
      local context = executor.build_execution_context({
        bufnr = sandbox_bufnr,
        cwd = vim.fn.getcwd(),
        timeout = 30,
        tool_name = "write",
      })

      local result = write_def.execute({
        label = "test",
        path = path,
        content = "denied by buffer override",
      }, context)

      assert.is_false(result.success)
      assert.is_truthy(result.error:match("Sandbox"))
    end)

    it("allows writes when sandbox is disabled even with empty rw_paths", function()
      config_facade.apply(config_facade.LAYERS.SETUP, {
        sandbox = {
          enabled = false,
          policy = { rw_paths = {} },
        },
      })
      local path = test_dir .. "/disabled_sandbox.txt"
      local disabled_ctx = executor.build_execution_context({
        bufnr = bufnr,
        cwd = vim.fn.getcwd(),
        timeout = 30,
        tool_name = "write",
      })

      local result = write_def.execute({
        label = "test",
        path = path,
        content = "disabled sandbox",
      }, disabled_ctx)

      assert.is_true(result.success)
    end)
  end)
end)
