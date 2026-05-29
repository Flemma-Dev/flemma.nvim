local parser = require("flemma.parser")

describe("parser malformed tool_use JSON", function()
  it("skips malformed tool_use without eating subsequent tool_use blocks", function()
    local lines = {
      "@Assistant:",
      "**Tool Use:** `tool_a` (`id_a`)",
      "",
      "```json",
      "{bad json here",
      "```",
      "",
      "**Tool Use:** `tool_b` (`id_b`)",
      "",
      "```json",
      '{"valid": true}',
      "```",
    }
    local doc = parser.parse_lines(lines)
    assert.equals(1, #doc.messages)

    local tool_uses = {}
    for _, seg in ipairs(doc.messages[1].segments) do
      if seg.kind == "tool_use" then
        table.insert(tool_uses, seg)
      end
    end

    assert.equals(1, #tool_uses, "expected tool_b to survive")
    assert.equals("tool_b", tool_uses[1].name)
    assert.equals("id_b", tool_uses[1].id)
    assert.is_true(tool_uses[1].input.valid)
  end)

  it("emits diagnostic for malformed JSON", function()
    local lines = {
      "@Assistant:",
      "**Tool Use:** `broken` (`id_broken`)",
      "",
      "```json",
      "{not valid}",
      "```",
    }
    local doc = parser.parse_lines(lines)

    assert.is_true(#doc.errors > 0, "expected a diagnostic for malformed JSON")
    local found = false
    for _, d in ipairs(doc.errors) do
      if d.type == "tool_use" and d.error:find("parse") then
        found = true
      end
    end
    assert.is_true(found, "expected a tool_use parse diagnostic")
  end)

  it("parses tool_use blocks after malformed one in the same message", function()
    local lines = {
      "@Assistant:",
      "**Tool Use:** `first` (`id_1`)",
      "",
      "```json",
      '{"good": 1}',
      "```",
      "",
      "**Tool Use:** `bad` (`id_2`)",
      "",
      "```json",
      "{broken",
      "```",
      "",
      "**Tool Use:** `third` (`id_3`)",
      "",
      "```json",
      '{"also_good": 2}',
      "```",
    }
    local doc = parser.parse_lines(lines)
    assert.equals(1, #doc.messages)

    local names = {}
    for _, seg in ipairs(doc.messages[1].segments) do
      if seg.kind == "tool_use" then
        table.insert(names, seg.name)
      end
    end

    assert.equals(2, #names, "expected first and third to parse")
    assert.equals("first", names[1])
    assert.equals("third", names[2])
  end)
end)
