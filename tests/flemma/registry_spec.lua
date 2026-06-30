local registry_utils = require("flemma.utilities.registry")
local registry = require("flemma.tools.registry")

describe("flemma.utilities.registry", function()
  describe("validate_name()", function()
    it("accepts plain names without error", function()
      assert.has_no.errors(function()
        registry_utils.validate_name("bash", "tool")
      end)
      assert.has_no.errors(function()
        registry_utils.validate_name("my_tool", "tool")
      end)
    end)

    it("accepts dotted names", function()
      assert.has_no.errors(function()
        registry_utils.validate_name("my.tool", "tool")
      end)
    end)

    it("accepts hyphenated names", function()
      assert.has_no.errors(function()
        registry_utils.validate_name("my-tool", "tool")
      end)
    end)

    it("rejects colons", function()
      assert.has.errors(function()
        registry_utils.validate_name("my:tool", "tool")
      end)
    end)

    it("includes the registry label in the error message", function()
      local ok, err = pcall(registry_utils.validate_name, "my:tool", "tool")
      assert.is_false(ok)
      assert.matches("tool name 'my:tool' contains invalid characters", tostring(err))
    end)

    it("uses the provided label for different registry types", function()
      local ok, err = pcall(registry_utils.validate_name, "my tool", "sandbox backend")
      assert.is_false(ok)
      assert.matches("sandbox backend name 'my tool' contains invalid characters", tostring(err))
    end)
  end)
end)

describe("flemma.tools.registry has_capability", function()
  before_each(function()
    package.loaded["flemma.tools.registry"] = nil
    registry = require("flemma.tools.registry")
  end)

  it("returns true when tool has the capability", function()
    registry.register("test_tool", {
      name = "test_tool",
      description = "test",
      input_schema = {},
      capabilities = { "auto_approves_if_sandboxed", "emits_template" },
    })
    assert.is_true(registry.has_capability("test_tool", "emits_template"))
    assert.is_true(registry.has_capability("test_tool", "auto_approves_if_sandboxed"))
  end)

  it("returns false when tool lacks the capability", function()
    registry.register("test_tool", {
      name = "test_tool",
      description = "test",
      input_schema = {},
      capabilities = { "auto_approves_if_sandboxed" },
    })
    assert.is_false(registry.has_capability("test_tool", "emits_template"))
  end)

  it("returns false when tool has no capabilities field", function()
    registry.register("test_tool", {
      name = "test_tool",
      description = "test",
      input_schema = {},
    })
    assert.is_false(registry.has_capability("test_tool", "emits_template"))
  end)

  it("returns false when tool does not exist", function()
    assert.is_false(registry.has_capability("nonexistent", "emits_template"))
  end)
end)
