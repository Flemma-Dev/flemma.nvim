package.loaded["flemma.ui.preview"] = nil
package.loaded["flemma.tools"] = nil

local preview = require("flemma.ui.preview")

describe("flemma.ui.preview.trim_chunks", function()
  before_each(function()
    package.loaded["flemma.ui.preview"] = nil
    package.loaded["flemma.tools"] = nil
    preview = require("flemma.ui.preview")
  end)

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
