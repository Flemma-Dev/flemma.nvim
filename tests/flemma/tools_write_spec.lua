--- Tests for write tool definition

package.loaded["flemma.tools"] = nil
package.loaded["flemma.tools.registry"] = nil
package.loaded["flemma.tools.definitions.write"] = nil

local tools = require("flemma.tools")
local registry = require("flemma.tools.registry")

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
end)
