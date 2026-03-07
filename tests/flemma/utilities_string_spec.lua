--- Tests for flemma.utilities.string — display-width helpers

package.loaded["flemma.utilities.string"] = nil

local str = require("flemma.utilities.string")

describe("flemma.utilities.string", function()
  describe("strwidth", function()
    it("returns 0 for empty string", function()
      assert.are.equal(0, str.strwidth(""))
    end)

    it("returns byte count for ASCII", function()
      assert.are.equal(5, str.strwidth("hello"))
    end)

    it("returns 1 for single-column multibyte character", function()
      -- "…" (U+2026) is 3 bytes, 1 display column
      assert.are.equal(1, str.strwidth("…"))
    end)

    it("returns 2 for CJK double-width character", function()
      -- "你" (U+4F60) is 3 bytes, 2 display columns
      assert.are.equal(2, str.strwidth("你"))
    end)

    it("counts mixed ASCII and multibyte correctly", function()
      -- "hi你" = 2 (ASCII) + 2 (CJK) = 4 display columns
      assert.are.equal(4, str.strwidth("hi你"))
    end)

    it("counts Unicode symbols used in notifications", function()
      -- "Σ" (U+03A3) is 1 display column
      assert.are.equal(1, str.strwidth("Σ"))
      -- "↑" (U+2191) is 1 display column
      assert.are.equal(1, str.strwidth("↑"))
      -- "ℹ" (U+2139) is 1 display column
      assert.are.equal(1, str.strwidth("ℹ"))
    end)
  end)

  describe("truncate", function()
    it("returns text unchanged when it fits", function()
      assert.are.equal("hello", str.truncate("hello", 10))
    end)

    it("returns text unchanged when exactly at limit", function()
      assert.are.equal("hello", str.truncate("hello", 5))
    end)

    it("truncates ASCII text with default suffix", function()
      local result = str.truncate("hello world", 8)
      -- "hello w" = 7 cols + "…" = 1 col = 8 cols
      assert.are.equal("hello w…", result)
    end)

    it("truncates with custom suffix", function()
      local result = str.truncate("hello world", 8, "..")
      -- "hello " = 6 cols + ".." = 2 cols = 8 cols
      assert.are.equal("hello ..", result)
    end)

    it("returns empty string when max_width is 0", function()
      assert.are.equal("", str.truncate("hello", 0))
    end)

    it("returns empty string when max_width is negative", function()
      assert.are.equal("", str.truncate("hello", -1))
    end)

    it("returns just the suffix when only suffix fits", function()
      -- max_width=1 with default "…" (1 col) → just the suffix
      assert.are.equal("…", str.truncate("hello world", 1))
    end)

    -- Multibyte safety
    it("does not split multibyte UTF-8 sequences", function()
      -- "café" = 4 chars, 4 display cols (é is 1 col, 2 bytes)
      local result = str.truncate("café mocha", 6)
      -- Should be "café …" (4+1+1=6) not a broken byte sequence
      assert.are.equal("café …", result)
      -- Verify valid UTF-8 by checking strwidth doesn't error
      assert.are.equal(6, str.strwidth(result))
    end)

    it("handles CJK double-width characters correctly", function()
      -- "你好世界" = 4 chars, 8 display cols (each char is 2 cols)
      local result = str.truncate("你好世界test", 7)
      -- "你好世" = 6 cols + "…" = 1 col = 7 cols
      assert.are.equal("你好世…", result)
      assert.are.equal(7, str.strwidth(result))
    end)

    it("skips double-width character that would exceed budget", function()
      -- "你好世界" = 8 cols. Truncate to 4 cols:
      -- "你" = 2 cols, budget left = 4-1(suffix)=3. "你" fits (2 ≤ 3).
      -- "你好" = 4 cols > 3. So only "你" fits.
      local result = str.truncate("你好世界", 4)
      assert.are.equal("你…", result)
      assert.are.equal(3, str.strwidth(result))
    end)

    it("handles mixed ASCII and CJK", function()
      -- "hi你好" = 2+2+2 = 6 cols. Truncate to 5:
      -- target = 5-1 = 4 cols for text. "hi你" = 4 cols. Fits.
      local result = str.truncate("hi你好world", 5)
      assert.are.equal("hi你…", result)
      assert.are.equal(5, str.strwidth(result))
    end)

    it("handles single-column multibyte chars (accented, symbols)", function()
      -- "αβγδ" = 4 chars, 4 display cols (Greek letters are 1 col each)
      local result = str.truncate("αβγδεζ", 5)
      assert.are.equal("αβγδ…", result)
      assert.are.equal(5, str.strwidth(result))
    end)

    it("handles truncation marker that is multi-byte", function()
      -- Custom suffix "→" is 3 bytes but 1 display column
      local result = str.truncate("hello world", 8, "→")
      assert.are.equal("hello w→", result)
    end)

    it("handles text that is all multibyte", function()
      -- "↑↓←→" = 4 chars, 4 cols (arrows are 1 col each)
      local result = str.truncate("↑↓←→", 3)
      assert.are.equal("↑↓…", result)
    end)
  end)
end)
