package.loaded["flemma.ui.preview"] = nil
package.loaded["flemma.tools"] = nil
package.loaded["flemma.tools.registry"] = nil

local preview = require("flemma.ui.preview")

describe("generic YAML preview", function()
  before_each(function()
    package.loaded["flemma.ui.preview"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.tools.registry"] = nil
    preview = require("flemma.ui.preview")
  end)

  describe("format_tool_preview_multiline generic fallback", function()
    it("renders short inputs as inline YAML", function()
      local lines = preview.format_tool_preview_multiline("tool", { enabled = true, count = 5 }, 200)
      assert.equals(1, #lines)
      assert.is_truthy(lines[1]:find("{"))
      assert.is_truthy(lines[1]:find("count: 5"))
      assert.is_truthy(lines[1]:find("enabled: true"))
    end)

    it("renders long inputs as multi-line YAML with highlight context", function()
      local input = {
        alpha = "aaaa",
        bravo = "bbbb",
        charlie = "cccc",
        delta = "dddd",
        echo_field = "eeee",
        foxtrot = "ffff",
        golf = "gggg",
        hotel = "a]long string that pushes us over the threshold",
      }
      local lines, _, ctx = preview.format_tool_preview_multiline("tool", input, 120)

      assert.is_true(#lines > 1, "expected multi-line output, got " .. #lines)
      assert.is_not_nil(ctx, "expected highlight_context for multi-line YAML")
      assert.equals("yaml", ctx.lang)
    end)

    it("uses JSON encoding for values", function()
      local lines = preview.format_tool_preview_multiline("t", { name = "hello world" }, 200)
      assert.is_truthy(lines[1]:find('"hello world"'))
    end)

    it("sorts scalar keys before table keys", function()
      local input = { zebra = 1, nested = { a = 1 }, alpha = 2 }
      local lines = preview.format_tool_preview_multiline("t", input, 200)
      local text = lines[1]
      local alpha_pos = text:find("alpha")
      local zebra_pos = text:find("zebra")
      local nested_pos = text:find("nested")
      assert.is_truthy(alpha_pos)
      assert.is_truthy(zebra_pos)
      assert.is_truthy(nested_pos)
      assert.is_true(alpha_pos < zebra_pos, "alpha should come before zebra")
      assert.is_true(zebra_pos < nested_pos, "scalars should come before tables")
    end)

    it("accounts for tool name prefix in inline threshold", function()
      local long_name = string.rep("x", 80)
      local input = { alpha = "aaa", bravo = "bbb", charlie = "ccc", delta = "ddd" }
      local lines = preview.format_tool_preview_multiline(long_name, input, 120)
      -- 80-char prefix + ": " = 82 chars, leaving 38 for content.
      -- The inline YAML is ~60 chars — exceeds the 38-char budget → multi-line.
      assert.is_true(#lines > 1, "expected multi-line when prefix is long")
    end)

    it("returns empty braces for empty input", function()
      local lines = preview.format_tool_preview_multiline("tool", {}, 120)
      assert.equals(1, #lines)
      assert.equals("tool", lines[1])
    end)

    it("puts tool name on its own line when multiline", function()
      local input = {
        alpha = "aaaa",
        bravo = "bbbb",
        charlie = "cccc",
        delta = "dddd",
        echo_field = "eeee",
        foxtrot = "ffff",
        golf = "gggg",
        hotel = "hhhh",
      }
      local lines = preview.format_tool_preview_multiline("my_tool", input, 120)
      assert.is_true(#lines > 2, "expected multi-line output")
      assert.equals("my_tool:", lines[1])
      assert.is_truthy(lines[2]:find("alpha"), "first key should be on second line")
    end)

    it("indents all detail lines with opts.indent when multiline", function()
      local input = {
        alpha = "aaaa",
        bravo = "bbbb",
        charlie = "cccc",
        delta = "dddd",
        echo_field = "eeee",
        foxtrot = "ffff",
        golf = "gggg",
        hotel = "a long string that pushes us over the threshold",
      }
      local lines = preview.format_tool_preview_multiline("tool", input, 120, { indent = "  " })
      assert.is_true(#lines > 2, "expected multi-line output")
      assert.equals("tool:", lines[1])
      for i = 2, #lines do
        assert.equals("  ", lines[i]:sub(1, 2), "line " .. i .. " should start with 2-space indent")
      end
    end)

    it("keeps first key on same line for inline preview", function()
      local lines = preview.format_tool_preview_multiline("tool", { enabled = true, count = 5 }, 200)
      assert.equals(1, #lines)
      assert.is_truthy(lines[1]:find("^tool: "), "inline preview keeps name prefix on same line")
    end)

    it("provides highlight_context with header as name_prefix when multiline", function()
      local input = {
        alpha = "aaaa",
        bravo = "bbbb",
        charlie = "cccc",
        delta = "dddd",
        echo_field = "eeee",
        foxtrot = "ffff",
        golf = "gggg",
        hotel = "a long string that pushes us over the threshold",
      }
      local _, _, ctx = preview.format_tool_preview_multiline("tool", input, 120, { indent = "    " })
      assert.is_not_nil(ctx, "expected highlight_context")
      assert.equals("tool:", ctx.name_prefix)
      assert.equals("    ", ctx.indent)
    end)
  end)
end)
