local parser = require("flemma.parser")

describe("parse_messages extraction", function()
  it("parse_lines produces same result after refactor - simple conversation", function()
    local lines = {
      "@System:",
      "You are helpful.",
      "@You:",
      "Hello",
      "@Assistant:",
      "Hi there!",
      "@You:",
      "Thanks",
    }
    local doc = parser.parse_lines(lines)
    assert.equals(4, #doc.messages)
    assert.equals("System", doc.messages[1].role)
    assert.equals("You", doc.messages[2].role)
    assert.equals("Assistant", doc.messages[3].role)
    assert.equals("You", doc.messages[4].role)
    assert.equals(1, doc.messages[1].position.start_line)
    assert.equals(2, doc.messages[1].position.end_line)
    assert.equals(3, doc.messages[2].position.start_line)
    assert.equals(4, doc.messages[2].position.end_line)
    assert.equals(5, doc.messages[3].position.start_line)
    assert.equals(6, doc.messages[3].position.end_line)
    assert.equals(7, doc.messages[4].position.start_line)
    assert.equals(8, doc.messages[4].position.end_line)
  end)

  it("parse_lines with frontmatter offsets positions correctly", function()
    local lines = {
      "```toml",
      'model = "test"',
      "```",
      "@You:",
      "Hello",
      "@Assistant:",
      "World",
    }
    local doc = parser.parse_lines(lines)
    assert.is_not_nil(doc.frontmatter)
    assert.equals(2, #doc.messages)
    assert.equals(4, doc.messages[1].position.start_line)
    assert.equals(5, doc.messages[1].position.end_line)
    assert.equals(6, doc.messages[2].position.start_line)
    assert.equals(7, doc.messages[2].position.end_line)
  end)
end)
