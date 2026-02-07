--- Tests for edit tool definition

package.loaded["flemma.tools"] = nil
package.loaded["flemma.tools.registry"] = nil
package.loaded["flemma.tools.definitions.edit"] = nil

local tools = require("flemma.tools")
local registry = require("flemma.tools.registry")

describe("Edit Tool", function()
  local edit_def
  local test_dir
  local test_file

  before_each(function()
    registry.clear()
    tools.setup()
    edit_def = registry.get("edit")

    -- Create a temp directory and test file
    test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")
    test_file = test_dir .. "/test.txt"
  end)

  after_each(function()
    vim.fn.delete(test_dir, "rf")
  end)

  it("is registered on setup", function()
    assert.is_not_nil(edit_def)
    assert.equals("edit", edit_def.name)
    assert.is_false(edit_def.async)
  end)

  describe("basic editing", function()
    it("replaces exact text", function()
      vim.fn.writefile({ "hello world" }, test_file)

      local result = edit_def.execute({
        label = "test",
        path = test_file,
        oldText = "hello",
        newText = "goodbye",
      })
      assert.is_true(result.success)
      assert.is_truthy(result.output:match("Successfully replaced"))

      -- Verify file content
      local content = table.concat(vim.fn.readfile(test_file), "\n")
      assert.equals("goodbye world", content)
    end)

    it("replaces multiline text", function()
      vim.fn.writefile({ "line 1", "line 2", "line 3" }, test_file)

      local result = edit_def.execute({
        label = "test",
        path = test_file,
        oldText = "line 1\nline 2",
        newText = "new line 1\nnew line 2",
      })
      assert.is_true(result.success)

      local content = table.concat(vim.fn.readfile(test_file), "\n")
      assert.equals("new line 1\nnew line 2\nline 3", content)
    end)

    it("handles special pattern characters in oldText", function()
      vim.fn.writefile({ "price is $5.00 (USD)" }, test_file)

      local result = edit_def.execute({
        label = "test",
        path = test_file,
        oldText = "$5.00 (USD)",
        newText = "$10.00 (EUR)",
      })
      assert.is_true(result.success)

      local content = table.concat(vim.fn.readfile(test_file), "\n")
      assert.equals("price is $10.00 (EUR)", content)
    end)

    it("handles Lua pattern characters in text", function()
      vim.fn.writefile({ "match [%w+] here" }, test_file)

      local result = edit_def.execute({
        label = "test",
        path = test_file,
        oldText = "[%w+]",
        newText = "[%d+]",
      })
      assert.is_true(result.success)

      local content = table.concat(vim.fn.readfile(test_file), "\n")
      assert.equals("match [%d+] here", content)
    end)
  end)

  describe("error cases", function()
    it("returns error for missing file", function()
      local result = edit_def.execute({
        label = "test",
        path = test_dir .. "/nonexistent.txt",
        oldText = "hello",
        newText = "world",
      })
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("File not found"))
    end)

    it("returns error when text not found", function()
      vim.fn.writefile({ "hello world" }, test_file)

      local result = edit_def.execute({
        label = "test",
        path = test_file,
        oldText = "nonexistent text",
        newText = "replacement",
      })
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("Could not find"))
    end)

    it("returns error for multiple occurrences", function()
      vim.fn.writefile({ "hello hello hello" }, test_file)

      local result = edit_def.execute({
        label = "test",
        path = test_file,
        oldText = "hello",
        newText = "world",
      })
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("3 occurrences"))
      assert.is_truthy(result.error:match("unique"))
    end)

    it("returns error for identical replacement", function()
      vim.fn.writefile({ "hello world" }, test_file)

      local result = edit_def.execute({
        label = "test",
        path = test_file,
        oldText = "hello",
        newText = "hello",
      })
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("No changes made"))
    end)

    it("returns error for empty oldText", function()
      vim.fn.writefile({ "hello" }, test_file)

      local result = edit_def.execute({
        label = "test",
        path = test_file,
        oldText = "",
        newText = "world",
      })
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("No oldText"))
    end)

    it("returns error for empty path", function()
      local result = edit_def.execute({
        label = "test",
        path = "",
        oldText = "hello",
        newText = "world",
      })
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("No path"))
    end)
  end)

  describe("edge cases", function()
    it("can replace with empty string (deletion)", function()
      vim.fn.writefile({ "hello world" }, test_file)

      local result = edit_def.execute({
        label = "test",
        path = test_file,
        oldText = " world",
        newText = "",
      })
      assert.is_true(result.success)

      local content = table.concat(vim.fn.readfile(test_file), "\n")
      assert.equals("hello", content)
    end)

    it("preserves file when exactly 2 occurrences", function()
      vim.fn.writefile({ "foo bar foo" }, test_file)

      local result = edit_def.execute({
        label = "test",
        path = test_file,
        oldText = "foo",
        newText = "baz",
      })
      assert.is_false(result.success)
      assert.is_truthy(result.error:match("2 occurrences"))

      -- File should be unchanged
      local content = table.concat(vim.fn.readfile(test_file), "\n")
      assert.equals("foo bar foo", content)
    end)
  end)
end)
