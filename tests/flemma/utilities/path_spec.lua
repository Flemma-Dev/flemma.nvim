--- Tests for utilities/path module

package.loaded["flemma.utilities.path"] = nil

local path_util = require("flemma.utilities.path")

describe("utilities.path", function()
  describe("resolve", function()
    it("expands ~/ paths", function()
      local home = vim.fn.expand("~")
      local result = path_util.resolve("~/Documents/file.txt")
      assert.equals(home .. "/Documents/file.txt", result)
    end)

    it("expands bare ~ path", function()
      local home = vim.fn.expand("~")
      local result = path_util.resolve("~")
      assert.equals(home, result)
    end)

    it("normalizes absolute paths", function()
      local result = path_util.resolve("/tmp/foo/../bar")
      assert.equals("/tmp/bar", result)
    end)

    it("passes through clean absolute paths", function()
      local result = path_util.resolve("/tmp/foo.png")
      assert.equals("/tmp/foo.png", result)
    end)

    it("joins relative paths with base_dir and normalizes", function()
      local result = path_util.resolve("foo/bar.txt", "/base/dir")
      assert.equals("/base/dir/foo/bar.txt", result)
    end)

    it("normalizes joined relative paths", function()
      local result = path_util.resolve("../sibling.txt", "/base/sub")
      assert.equals("/base/sibling.txt", result)
    end)

    it("handles ./ relative paths with base_dir", function()
      local result = path_util.resolve("./file.txt", "/base/dir")
      assert.equals("/base/dir/file.txt", result)
    end)

    it("returns relative path as-is when no base_dir", function()
      local result = path_util.resolve("foo/bar.txt")
      assert.equals("foo/bar.txt", result)
    end)

    it("returns ./path as-is when no base_dir", function()
      local result = path_util.resolve("./file.txt")
      assert.equals("./file.txt", result)
    end)

    it("ignores base_dir for absolute paths", function()
      local result = path_util.resolve("/absolute/path.txt", "/ignored/base")
      assert.equals("/absolute/path.txt", result)
    end)

    it("ignores base_dir for tilde paths", function()
      local home = vim.fn.expand("~")
      local result = path_util.resolve("~/file.txt", "/ignored/base")
      assert.equals(home .. "/file.txt", result)
    end)
  end)

  describe("dirname", function()
    it("returns parent directory", function()
      assert.equals("/home/user", path_util.dirname("/home/user/file.txt"))
    end)

    it("returns . for bare filename", function()
      assert.equals(".", path_util.dirname("file.txt"))
    end)
  end)

  describe("basename", function()
    it("returns filename component", function()
      assert.equals("file.txt", path_util.basename("/home/user/file.txt"))
    end)

    it("returns input for bare filename", function()
      assert.equals("file.txt", path_util.basename("file.txt"))
    end)
  end)

  describe("realpath", function()
    it("returns absolute path for relative input", function()
      local result = path_util.realpath(".")
      assert.is_truthy(vim.startswith(result, "/"), "expected absolute path, got: " .. result)
    end)
  end)

  describe("relative", function()
    it("strips base_dir prefix", function()
      assert.equals("./sub/file.txt", path_util.relative("/base/dir/sub/file.txt", "/base/dir"))
    end)

    it("returns . when path equals base_dir", function()
      assert.equals(".", path_util.relative("/base/dir", "/base/dir"))
    end)

    it("returns path unchanged when not under base_dir", function()
      assert.equals("/other/file.txt", path_util.relative("/other/file.txt", "/base/dir"))
    end)
  end)
end)
