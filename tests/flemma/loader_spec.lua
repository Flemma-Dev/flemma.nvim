local loader = require("flemma.loader")

describe("flemma.loader", function()
  describe("is_module_path()", function()
    it("returns true for dotted strings", function()
      assert.is_true(loader.is_module_path("3rd.tools.todos"))
      assert.is_true(loader.is_module_path("my.module"))
    end)

    it("returns false for plain names", function()
      assert.is_false(loader.is_module_path("bash"))
      assert.is_false(loader.is_module_path("calculator"))
      assert.is_false(loader.is_module_path(""))
    end)
  end)

  describe("assert_exists()", function()
    it("passes for modules on package.path", function()
      assert.has_no.errors(function()
        loader.assert_exists("flemma.config")
      end)
    end)

    it("passes for modules in package.preload", function()
      package.preload["test.preloaded.module"] = function()
        return {}
      end
      assert.has_no.errors(function()
        loader.assert_exists("test.preloaded.module")
      end)
      package.preload["test.preloaded.module"] = nil
    end)

    it("throws for missing modules", function()
      assert.has_error(function()
        loader.assert_exists("nonexistent.module.path")
      end, "flemma: module 'nonexistent.module.path' not found on package.path")
    end)
  end)

  describe("load()", function()
    it("returns module table for valid modules", function()
      local mod = loader.load("flemma.config")
      assert.is_table(mod)
    end)

    it("throws for modules that error on load", function()
      package.preload["test.error_module"] = function()
        error("intentional load error")
      end
      assert.has_error(function()
        loader.load("test.error_module")
      end)
      package.preload["test.error_module"] = nil
    end)
  end)

  describe("load_select()", function()
    it("extracts the named field from a module", function()
      package.preload["test.with_field"] = function()
        return { definitions = { { name = "test_tool" } } }
      end
      local defs = loader.load_select("test.with_field", "definitions", "tool module")
      assert.is_table(defs)
      assert.equals("test_tool", defs[1].name)
      package.preload["test.with_field"] = nil
      package.loaded["test.with_field"] = nil
    end)

    it("throws when the field is missing", function()
      package.preload["test.no_field"] = function()
        return { something_else = true }
      end
      assert.has_error(function()
        loader.load_select("test.no_field", "definitions", "tool module")
      end, "flemma: module 'test.no_field' has no 'definitions' export (expected tool module)")
      package.preload["test.no_field"] = nil
      package.loaded["test.no_field"] = nil
    end)
  end)
end)
