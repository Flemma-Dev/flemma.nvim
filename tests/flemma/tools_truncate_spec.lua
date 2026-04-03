-- tests/flemma/tools_truncate_spec.lua
describe("tools.truncate", function()
  local tools_truncate
  local base_truncate = require("flemma.utilities.truncate")

  before_each(function()
    package.loaded["flemma.tools.truncate"] = nil
    tools_truncate = require("flemma.tools.truncate")
  end)

  describe("re-exports", function()
    it("exposes truncate_head from utilities", function()
      assert.equals(base_truncate.truncate_head, tools_truncate.truncate_head)
    end)

    it("exposes truncate_tail from utilities", function()
      assert.equals(base_truncate.truncate_tail, tools_truncate.truncate_tail)
    end)

    it("exposes format_size from utilities", function()
      assert.equals(base_truncate.format_size, tools_truncate.format_size)
    end)

    it("exposes MAX_LINES constant", function()
      assert.equals(base_truncate.MAX_LINES, tools_truncate.MAX_LINES)
    end)

    it("exposes MAX_BYTES constant", function()
      assert.equals(base_truncate.MAX_BYTES, tools_truncate.MAX_BYTES)
    end)
  end)

  describe("truncate_with_overflow", function()
    local function temp_dir()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      return dir
    end

    local function make_opts(overrides)
      local dir = temp_dir()
      overrides = overrides or {}
      return vim.tbl_extend("force", {
        direction = "head",
        source = "tool",
        id = "test_123",
        bufnr = 0,
        output_path_format = dir .. "/flemma_#{source}_#{id}.txt",
      }, overrides)
    end

    it("passes short output through unchanged", function()
      local result = tools_truncate.truncate_with_overflow("hello world", make_opts())
      assert.equals("hello world", result.content)
      assert.is_nil(result.overflow_path)
      assert.is_false(result.truncated)
    end)

    it("truncates head output exceeding line limit and writes file", function()
      local lines = {}
      for i = 1, base_truncate.MAX_LINES + 500 do
        lines[i] = "line " .. i
      end
      local text = table.concat(lines, "\n")
      local result = tools_truncate.truncate_with_overflow(text, make_opts())

      assert.is_true(result.truncated)
      assert.is_string(result.overflow_path)
      assert.is_truthy(result.content:find("%[Showing lines 1%-"))
      assert.is_truthy(result.content:find("Full output:"))
      local f = io.open(result.overflow_path, "r")
      assert.is_truthy(f)
      local saved = f:read("*a")
      f:close()
      assert.equals(text, saved)
      assert.is_falsy(result.content:find("line " .. #lines))
    end)

    it("truncates head output exceeding byte limit", function()
      local lines = {}
      local long_line = string.rep("x", 1000)
      for i = 1, 200 do
        lines[i] = long_line
      end
      local text = table.concat(lines, "\n")
      assert.is_truthy(#text > base_truncate.MAX_BYTES)
      local result = tools_truncate.truncate_with_overflow(text, make_opts())

      assert.is_true(result.truncated)
      assert.is_string(result.overflow_path)
      assert.is_truthy(result.content:find("limit"))
    end)

    it("truncates tail output exceeding line limit", function()
      local lines = {}
      for i = 1, base_truncate.MAX_LINES + 500 do
        lines[i] = "line " .. i
      end
      local text = table.concat(lines, "\n")
      local result = tools_truncate.truncate_with_overflow(text, make_opts({ direction = "tail" }))

      assert.is_true(result.truncated)
      assert.is_string(result.overflow_path)
      assert.is_truthy(result.content:find("line " .. #lines))
      assert.is_falsy(result.content:find("^line 1\n"))
    end)

    it("handles first line exceeding byte limit", function()
      local text = string.rep("x", base_truncate.MAX_BYTES + 1000)
      local result = tools_truncate.truncate_with_overflow(text, make_opts())

      assert.is_true(result.truncated)
      assert.is_string(result.overflow_path)
      assert.is_truthy(result.content:find("%[Output too large"))
      assert.is_truthy(result.content:find("Full output:"))
    end)

    it("uses #{source} and #{id} in output path", function()
      local lines = {}
      for i = 1, base_truncate.MAX_LINES + 10 do
        lines[i] = "line " .. i
      end
      local text = table.concat(lines, "\n")
      local result = tools_truncate.truncate_with_overflow(
        text,
        make_opts({
          source = "mysource",
          id = "myid",
        })
      )

      assert.is_truthy(result.overflow_path)
      assert.is_truthy(result.overflow_path:find("flemma_mysource_myid%.txt"))
    end)

    it("creates parent directories for overflow path", function()
      local base = vim.fn.tempname()
      local result = tools_truncate.truncate_with_overflow(
        string.rep("x", base_truncate.MAX_BYTES + 1000),
        make_opts({ output_path_format = base .. "/deep/nested/flemma_#{source}_#{id}.txt" })
      )

      assert.is_truthy(result.overflow_path)
      assert.equals(1, vim.fn.filereadable(result.overflow_path))
    end)

    it("omits Full output suffix when file write fails", function()
      local result = tools_truncate.truncate_with_overflow(
        string.rep("x", base_truncate.MAX_BYTES + 1000),
        make_opts({ output_path_format = "/dev/null/impossible/flemma_#{source}_#{id}.txt" })
      )

      assert.is_true(result.truncated)
      assert.is_nil(result.overflow_path)
      assert.is_falsy(result.content:find("Full output:"))
    end)
  end)
end)
