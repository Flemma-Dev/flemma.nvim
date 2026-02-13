--- Tests for truncation utilities

package.loaded["flemma.tools.truncate"] = nil

local truncate = require("flemma.tools.truncate")

describe("Truncation Utilities", function()
  describe("format_size", function()
    it("formats bytes", function()
      assert.equals("500B", truncate.format_size(500))
    end)

    it("formats kilobytes", function()
      assert.equals("1.5KB", truncate.format_size(1536))
    end)

    it("formats megabytes", function()
      assert.equals("2.0MB", truncate.format_size(2 * 1024 * 1024))
    end)

    it("formats zero", function()
      assert.equals("0B", truncate.format_size(0))
    end)

    it("formats exactly 1KB", function()
      assert.equals("1.0KB", truncate.format_size(1024))
    end)
  end)

  describe("truncate_head", function()
    it("returns content unchanged when within limits", function()
      local result = truncate.truncate_head("line1\nline2\nline3")
      assert.is_false(result.truncated)
      assert.equals("line1\nline2\nline3", result.content)
      assert.equals(3, result.total_lines)
      assert.equals(3, result.output_lines)
    end)

    it("truncates by line count", function()
      -- Create content with more than max_lines
      local lines = {}
      for i = 1, 10 do
        lines[i] = "line " .. i
      end
      local content = table.concat(lines, "\n")

      local result = truncate.truncate_head(content, { max_lines = 5 })
      assert.is_true(result.truncated)
      assert.equals("lines", result.truncated_by)
      assert.equals(5, result.output_lines)
      assert.equals(10, result.total_lines)
    end)

    it("truncates by byte count", function()
      -- Create content that exceeds byte limit but not line limit
      local lines = {}
      for i = 1, 5 do
        lines[i] = string.rep("x", 100) -- 100 bytes per line
      end
      local content = table.concat(lines, "\n")

      local result = truncate.truncate_head(content, { max_bytes = 250 })
      assert.is_true(result.truncated)
      assert.equals("bytes", result.truncated_by)
      assert.is_true(result.output_lines < 5)
    end)

    it("detects first line exceeding byte limit", function()
      local content = string.rep("x", 200) .. "\nshort line"
      local result = truncate.truncate_head(content, { max_bytes = 100 })
      assert.is_true(result.truncated)
      assert.is_true(result.first_line_exceeds_limit)
      assert.equals("", result.content)
      assert.equals(0, result.output_lines)
    end)

    it("handles empty content", function()
      local result = truncate.truncate_head("")
      assert.is_false(result.truncated)
      assert.equals("", result.content)
      assert.equals(1, result.total_lines) -- "" splits to {""}
    end)

    it("handles single line within limits", function()
      local result = truncate.truncate_head("hello world")
      assert.is_false(result.truncated)
      assert.equals("hello world", result.content)
    end)

    it("keeps complete lines only", function()
      -- 3 lines: "aaa", "bbb", "ccc" - with newlines that's 11 bytes total
      local content = "aaa\nbbb\nccc"
      -- Set byte limit so that only first 2 lines fit (3 + 1 + 3 = 7 bytes for 2 lines)
      local result = truncate.truncate_head(content, { max_bytes = 8 })
      assert.is_true(result.truncated)
      assert.equals(2, result.output_lines)
      assert.equals("aaa\nbbb", result.content)
    end)
  end)

  describe("truncate_tail", function()
    it("returns content unchanged when within limits", function()
      local result = truncate.truncate_tail("line1\nline2\nline3")
      assert.is_false(result.truncated)
      assert.equals("line1\nline2\nline3", result.content)
    end)

    it("truncates by line count keeping tail", function()
      local lines = {}
      for i = 1, 10 do
        lines[i] = "line " .. i
      end
      local content = table.concat(lines, "\n")

      local result = truncate.truncate_tail(content, { max_lines = 3 })
      assert.is_true(result.truncated)
      assert.equals("lines", result.truncated_by)
      assert.equals(3, result.output_lines)
      assert.equals(10, result.total_lines)
      -- Should keep last 3 lines
      assert.is_truthy(result.content:match("line 8"))
      assert.is_truthy(result.content:match("line 9"))
      assert.is_truthy(result.content:match("line 10"))
      -- Should NOT contain early lines
      assert.is_falsy(result.content:match("line 1\n"))
    end)

    it("truncates by byte count keeping tail", function()
      local lines = {}
      for i = 1, 5 do
        lines[i] = string.rep("x", 100)
      end
      local content = table.concat(lines, "\n")

      local result = truncate.truncate_tail(content, { max_bytes = 250 })
      assert.is_true(result.truncated)
      assert.equals("bytes", result.truncated_by)
      assert.is_true(result.output_lines < 5)
    end)

    it("handles partial last line when single line exceeds limit", function()
      -- Single very long line
      local content = string.rep("x", 200)
      local result = truncate.truncate_tail(content, { max_bytes = 50 })
      assert.is_true(result.truncated)
      assert.is_true(result.last_line_partial)
      assert.is_true(#result.content <= 50)
    end)

    it("handles empty content", function()
      local result = truncate.truncate_tail("")
      assert.is_false(result.truncated)
      assert.equals("", result.content)
    end)
  end)
end)
