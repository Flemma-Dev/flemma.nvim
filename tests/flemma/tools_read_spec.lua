--- Tests for read tool definition

package.loaded["flemma.tools"] = nil
package.loaded["flemma.tools.registry"] = nil
package.loaded["flemma.tools.executor"] = nil
package.loaded["flemma.tools.definitions.read"] = nil
package.loaded["flemma.tools.truncate"] = nil

local tools = require("flemma.tools")
local registry = require("flemma.tools.registry")
local executor = require("flemma.tools.executor")

describe("Read Tool", function()
  local read_def
  local test_dir
  local test_file
  local bufnr
  local ctx

  before_each(function()
    registry.clear()
    tools.setup()
    read_def = registry.get("read")

    -- Create a temp directory and test file
    test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")
    test_file = test_dir .. "/test.txt"

    bufnr = vim.api.nvim_create_buf(false, true)
    ctx = executor.build_execution_context({
      bufnr = bufnr,
      cwd = vim.fn.getcwd(),
      timeout = 30,
      tool_name = "read",
    })
  end)

  after_each(function()
    -- Clean up
    vim.fn.delete(test_dir, "rf")
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("is registered on setup", function()
    assert.is_not_nil(read_def)
    assert.equals("read", read_def.name)
    assert.is_false(read_def.async)
  end)

  it("reads a simple file", function()
    vim.fn.writefile({ "hello", "world" }, test_file)

    local result = read_def.execute({ label = "test", path = test_file }, ctx)
    assert.is_true(result.success)
    assert.equals("hello\nworld", result.output)
  end)

  it("returns error for missing file", function()
    local result = read_def.execute({ label = "test", path = test_dir .. "/nonexistent.txt" }, ctx)
    assert.is_false(result.success)
    assert.is_truthy(result.error:match("File not found"))
  end)

  it("returns error for empty path", function()
    local result = read_def.execute({ label = "test", path = "" }, ctx)
    assert.is_false(result.success)
    assert.is_truthy(result.error:match("No path"))
  end)

  it("returns error for nil path", function()
    local result = read_def.execute({ label = "test" }, ctx)
    assert.is_false(result.success)
    assert.is_truthy(result.error:match("No path"))
  end)

  describe("nil offset and limit", function()
    it("reads full file when offset and limit are nil", function()
      vim.fn.writefile({ "hello", "world" }, test_file)

      local result = read_def.execute({ label = "test", path = test_file, offset = nil, limit = nil }, ctx)
      assert.is_true(result.success)
      assert.equals("hello\nworld", result.output)
    end)
  end)

  describe("offset and limit", function()
    before_each(function()
      -- Write a 10-line file
      local lines = {}
      for i = 1, 10 do
        lines[i] = "line " .. i
      end
      vim.fn.writefile(lines, test_file)
    end)

    it("reads from offset", function()
      local result = read_def.execute({ label = "test", path = test_file, offset = 3 }, ctx)
      assert.is_true(result.success)
      -- Should start from line 3
      assert.is_truthy(result.output:match("^line 3"))
      assert.is_falsy(result.output:match("line 1\n"))
      assert.is_falsy(result.output:match("line 2\n"))
    end)

    it("reads with limit", function()
      local result = read_def.execute({ label = "test", path = test_file, limit = 3 }, ctx)
      assert.is_true(result.success)
      -- Should have only 3 lines
      assert.is_truthy(result.output:match("line 1"))
      assert.is_truthy(result.output:match("line 3"))
      -- Should have continuation notice
      assert.is_truthy(result.output:match("more lines"))
      assert.is_truthy(result.output:match("offset=4"))
    end)

    it("reads with both offset and limit", function()
      local result = read_def.execute({ label = "test", path = test_file, offset = 5, limit = 2 }, ctx)
      assert.is_true(result.success)
      assert.is_truthy(result.output:match("line 5"))
      assert.is_truthy(result.output:match("line 6"))
      assert.is_truthy(result.output:match("more lines"))
    end)

    it("returns error for offset beyond file", function()
      local result = read_def.execute({ label = "test", path = test_file, offset = 100 }, ctx)
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("beyond end of file"))
    end)

    it("handles offset at last line", function()
      local result = read_def.execute({ label = "test", path = test_file, offset = 10 }, ctx)
      assert.is_true(result.success)
      assert.equals("line 10", result.output)
    end)
  end)

  describe("truncation", function()
    it("truncates large files by line count", function()
      -- Write more lines than MAX_LINES
      local truncate = require("flemma.tools.truncate")
      local lines = {}
      for i = 1, truncate.MAX_LINES + 100 do
        lines[i] = "line " .. i
      end
      vim.fn.writefile(lines, test_file)

      local result = read_def.execute({ label = "test", path = test_file }, ctx)
      assert.is_true(result.success)
      -- Should have truncation notice
      assert.is_truthy(result.output:match("Showing lines"))
      assert.is_truthy(result.output:match("offset="))
    end)
  end)
end)
