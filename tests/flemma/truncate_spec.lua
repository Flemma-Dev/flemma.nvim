package.loaded["flemma.utilities.truncate"] = nil
local truncate = require("flemma.utilities.truncate")

describe("truncate_line()", function()
  it("returns short lines unchanged", function()
    local result = truncate.truncate_line("hello world", 500)
    assert.equals("hello world", result.text)
    assert.is_false(result.truncated)
  end)

  it("truncates long lines with suffix", function()
    local long = string.rep("x", 600)
    local result = truncate.truncate_line(long, 500)
    assert.is_true(result.truncated)
    assert.truthy(result.text:find("%[truncated%]$"))
    assert.truthy(#result.text <= 500)
  end)

  it("uses default max_chars when not specified", function()
    local long = string.rep("x", 600)
    local result = truncate.truncate_line(long)
    assert.is_true(result.truncated)
    assert.truthy(#result.text <= truncate.MAX_LINE_CHARS)
  end)

  it("handles exact boundary length", function()
    local exact = string.rep("x", 500)
    local result = truncate.truncate_line(exact, 500)
    assert.equals(exact, result.text)
    assert.is_false(result.truncated)
  end)

  it("handles empty string", function()
    local result = truncate.truncate_line("", 500)
    assert.equals("", result.text)
    assert.is_false(result.truncated)
  end)

  it("handles very small max_chars", function()
    local result = truncate.truncate_line("hello world", 5)
    assert.is_true(result.truncated)
    assert.truthy(#result.text > 0)
  end)

  it("does not split multi-byte UTF-8 characters", function()
    -- U+2500 (─) is 3 bytes: 0xe2 0x94 0x80
    -- Build a line: "aaa" (3 bytes) + 200 box-drawing chars (600 bytes) = 603 bytes
    local line = "aaa" .. string.rep("\xe2\x94\x80", 200)
    -- max_chars=20, suffix "... [truncated]" is 15 bytes, budget = 5
    -- Budget of 5 fits "aaa" (3 bytes) but not the next box char (needs 3 more bytes)
    local result = truncate.truncate_line(line, 20)
    assert.is_true(result.truncated)
    assert.truthy(result.text:find("%[truncated%]$"))
    -- The kept prefix must end at a valid UTF-8 boundary — just "aaa"
    local suffix = "... [truncated]"
    local kept = result.text:sub(1, #result.text - #suffix)
    assert.equals("aaa", kept)
  end)

  it("keeps complete multi-byte characters that fit", function()
    -- 2 box-drawing chars (6 bytes) + 1 ASCII = 7 bytes total
    local line = "\xe2\x94\x80\xe2\x94\x80x"
    -- Not truncated when limit is large enough
    local result = truncate.truncate_line(line, 500)
    assert.is_false(result.truncated)
    assert.equals(line, result.text)
  end)
end)
