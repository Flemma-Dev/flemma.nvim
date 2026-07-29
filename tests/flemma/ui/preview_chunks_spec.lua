package.loaded["flemma.ui.preview"] = nil
package.loaded["flemma.tools"] = nil

local preview = require("flemma.ui.preview")

describe("flemma.ui.preview chunk operations", function()
  before_each(function()
    package.loaded["flemma.ui.preview"] = nil
    package.loaded["flemma.tools"] = nil
    preview = require("flemma.ui.preview")
  end)

  describe("trim_chunks", function()
    ---@param text string
    ---@return {[1]: string, [2]: string|string[]}[]
    local function line(text)
      return { { text, "TestHl" } }
    end

    it("returns all lines when they fit within budget", function()
      local lines = { line("short"), line("also short") }
      local result = preview.trim_chunks(lines, 6, 6)
      assert.equals(2, #result)
    end)

    it("trims to head + indicator + tail for many lines", function()
      local lines = {}
      for i = 1, 20 do
        lines[i] = line("line " .. i)
      end
      local result = preview.trim_chunks(lines, 3, 3)
      assert.equals(7, #result)
      local indicator_text = result[4][1][1]
      assert.is_truthy(indicator_text:find("more lines"))
    end)

    it("returns all lines when count equals budget exactly", function()
      local lines = {}
      for i = 1, 6 do
        lines[i] = line("x")
      end
      local result = preview.trim_chunks(lines, 3, 3)
      assert.equals(6, #result)
    end)

    it("handles off-by-one: count = budget + 1", function()
      local lines = {}
      for i = 1, 7 do
        lines[i] = line("line" .. i)
      end
      local result = preview.trim_chunks(lines, 3, 3)
      assert.equals(7, #result)
      local indicator_text = result[4][1][1]
      assert.is_truthy(indicator_text:find("1 more line"))
    end)

    it("handles empty chunk arrays in lines", function()
      local lines = { line(""), line("content"), line("") }
      local result = preview.trim_chunks(lines, 6, 6)
      assert.equals(3, #result)
    end)
  end)

  describe("truncate_chunks", function()
    it("returns chunks unchanged when they fit within max_width", function()
      local chunks = { { "hello", "HlA" }, { " world", "HlB" } }
      local result = preview.truncate_chunks(chunks, 80)
      assert.equals(2, #result)
      assert.equals("hello", result[1][1])
      assert.equals(" world", result[2][1])
    end)

    it("truncates mid-chunk and appends marker", function()
      local chunks = { { "hello ", "HlA" }, { "world", "HlB" } }
      local result = preview.truncate_chunks(chunks, 8)
      local text = ""
      for _, c in ipairs(result) do
        text = text .. c[1]
      end
      assert.is_true(vim.api.nvim_strwidth(text) <= 8)
      assert.is_truthy(text:find("…"))
    end)

    it("truncates at exact chunk boundary", function()
      local chunks = { { "hello", "HlA" }, { " world", "HlB" } }
      local result = preview.truncate_chunks(chunks, 6)
      local text = ""
      for _, c in ipairs(result) do
        text = text .. c[1]
      end
      assert.is_true(vim.api.nvim_strwidth(text) <= 6)
      assert.is_truthy(text:find("…"))
    end)

    it("handles single chunk exceeding max_width", function()
      local chunks = { { "a very long string that exceeds the limit", "HlA" } }
      local result = preview.truncate_chunks(chunks, 15)
      local text = ""
      for _, c in ipairs(result) do
        text = text .. c[1]
      end
      assert.is_true(vim.api.nvim_strwidth(text) <= 15)
      assert.is_truthy(text:find("…"))
    end)

    it("returns empty array for zero max_width", function()
      local chunks = { { "hello", "HlA" } }
      local result = preview.truncate_chunks(chunks, 0)
      assert.equals(0, #result)
    end)

    it("preserves highlight groups through truncation", function()
      local chunks = { { "abc", "HlA" }, { "def", "HlB" }, { "ghi", "HlC" } }
      local result = preview.truncate_chunks(chunks, 5)
      assert.equals("HlA", result[1][2])
    end)
  end)
end)
