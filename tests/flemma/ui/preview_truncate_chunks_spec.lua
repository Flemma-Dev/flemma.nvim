package.loaded["flemma.ui.preview"] = nil
package.loaded["flemma.tools"] = nil

local preview = require("flemma.ui.preview")

describe("flemma.ui.preview.truncate_chunks", function()
  before_each(function()
    package.loaded["flemma.ui.preview"] = nil
    package.loaded["flemma.tools"] = nil
    preview = require("flemma.ui.preview")
  end)

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
