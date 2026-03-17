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

  it("does not split 2-byte Cyrillic characters", function()
    -- U+041F (П) is 2 bytes: 0xd0 0x9f; U+0440 (р) is 2 bytes: 0xd1 0x80
    -- "Привет" = 12 bytes (6 Cyrillic chars x 2 bytes each)
    local privet = "\xd0\x9f\xd1\x80\xd0\xb8\xd0\xb2\xd0\xb5\xd1\x82" -- "Привет"
    local line = string.rep(privet, 50) -- 600 bytes
    -- max_chars=20, suffix=15 bytes, budget=5 — fits 2 complete 2-byte chars (4 bytes)
    local result = truncate.truncate_line(line, 20)
    assert.is_true(result.truncated)
    local suffix = "... [truncated]"
    local kept = result.text:sub(1, #result.text - #suffix)
    -- 5 byte budget: 2 Cyrillic chars (4 bytes) fit, 3rd (bytes 5-6) does not
    assert.equals(4, #kept)
    assert.equals("\xd0\x9f\xd1\x80", kept) -- "П" + "р"
  end)

  it("does not split 4-byte emoji characters", function()
    -- U+1F600 (grinning face) is 4 bytes: 0xf0 0x9f 0x98 0x80
    local emoji = "\xf0\x9f\x98\x80" -- U+1F600 😀
    local line = string.rep(emoji, 150) -- 600 bytes
    -- max_chars=20, suffix=15 bytes, budget=5 — 4-byte emoji fits once (4 bytes)
    local result = truncate.truncate_line(line, 20)
    assert.is_true(result.truncated)
    local suffix = "... [truncated]"
    local kept = result.text:sub(1, #result.text - #suffix)
    assert.equals(4, #kept)
    assert.equals(emoji, kept)
  end)

  it("handles cut point landing on each byte of a 4-byte emoji", function()
    -- "ab" (2 bytes) + U+1F600 (4 bytes) + padding = line that truncates mid-emoji
    local emoji = "\xf0\x9f\x98\x80" -- U+1F600 😀
    -- budget lands on byte 3 of the emoji (offset 5 in the string)
    -- "ab" = 2 bytes, emoji starts at byte 3, so budget=4 lands on 2nd byte of emoji
    local line = "ab" .. string.rep(emoji, 150)
    local result = truncate.truncate_line(line, 19)
    -- budget = 19 - 15 = 4; "ab" (2 bytes) + emoji byte 1-2 don't complete, keep "ab"
    assert.is_true(result.truncated)
    local suffix = "... [truncated]"
    local kept = result.text:sub(1, #result.text - #suffix)
    assert.equals("ab", kept)
  end)
end)
