-- tests/flemma/tool_names_spec.lua
describe("utilities.tools", function()
  local tool_names

  before_each(function()
    package.loaded["flemma.utilities.tools"] = nil
    tool_names = require("flemma.utilities.tools")
  end)

  describe("encode_tool_name", function()
    it("replaces colon with wire separator", function()
      assert.equals("slack__channels_list", tool_names.encode_tool_name("slack:channels_list"))
    end)

    it("handles multiple colons", function()
      assert.equals("server__group__tool", tool_names.encode_tool_name("server:group:tool"))
    end)

    it("passes through names without colons", function()
      assert.equals("bash", tool_names.encode_tool_name("bash"))
    end)

    it("passes through empty string", function()
      assert.equals("", tool_names.encode_tool_name(""))
    end)
  end)

  describe("decode_tool_name", function()
    it("replaces wire separator with colon", function()
      assert.equals("slack:channels_list", tool_names.decode_tool_name("slack__channels_list"))
    end)

    it("handles multiple wire separators", function()
      assert.equals("server:group:tool", tool_names.decode_tool_name("server__group__tool"))
    end)

    it("passes through names without wire separator", function()
      assert.equals("bash", tool_names.decode_tool_name("bash"))
    end)

    it("passes through empty string", function()
      assert.equals("", tool_names.decode_tool_name(""))
    end)
  end)

  describe("round-trip", function()
    it("encode then decode returns original", function()
      local original = "slack:channels_list"
      assert.equals(original, tool_names.decode_tool_name(tool_names.encode_tool_name(original)))
    end)

    it("decode then encode returns original", function()
      local wire = "slack__channels_list"
      assert.equals(wire, tool_names.encode_tool_name(tool_names.decode_tool_name(wire)))
    end)
  end)
end)
