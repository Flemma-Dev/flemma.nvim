local ast = require("flemma.ast")
local parser = require("flemma.parser")

describe("ast.query", function()
  before_each(function()
    package.loaded["flemma.ast"] = nil
    package.loaded["flemma.ast.query"] = nil
    package.loaded["flemma.ast.nodes"] = nil
    package.loaded["flemma.parser"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.preprocessor"] = nil
    package.loaded["flemma.preprocessor.registry"] = nil
    package.loaded["flemma.preprocessor.runner"] = nil
    package.loaded["flemma.preprocessor.context"] = nil
    package.loaded["flemma.preprocessor.utilities"] = nil
    package.loaded["flemma.preprocessor.rewriters.file_references"] = nil
    ast = require("flemma.ast")
    parser = require("flemma.parser")
  end)

  describe("find_tool_sibling", function()
    it("returns tool_result for a tool_use segment", function()
      local doc = parser.parse_lines({
        "@Assistant:",
        "**Tool Use:** `bash` (`call_001`)",
        "```json",
        '{"command": "ls"}',
        "```",
        "@You:",
        "**Tool Result:** `call_001`",
        "",
        "```",
        "file1.txt",
        "```",
      })

      -- Find the tool_use segment
      local tool_use = nil
      for _, msg in ipairs(doc.messages) do
        for _, seg in ipairs(msg.segments) do
          if seg.kind == "tool_use" then
            tool_use = seg
          end
        end
      end
      assert.is_not_nil(tool_use)

      local counterpart, counterpart_msg = ast.find_tool_sibling(doc, tool_use)
      assert.is_not_nil(counterpart)
      assert.equals("tool_result", counterpart.kind)
      assert.equals("call_001", counterpart.tool_use_id)
      assert.is_not_nil(counterpart_msg)
      assert.equals("You", counterpart_msg.role)
    end)

    it("returns tool_use for a tool_result segment", function()
      local doc = parser.parse_lines({
        "@Assistant:",
        "**Tool Use:** `read` (`call_002`)",
        "```json",
        '{"path": "/tmp/a.txt"}',
        "```",
        "@You:",
        "**Tool Result:** `call_002`",
        "",
        "```",
        "contents",
        "```",
      })

      local tool_result = nil
      for _, msg in ipairs(doc.messages) do
        for _, seg in ipairs(msg.segments) do
          if seg.kind == "tool_result" then
            tool_result = seg
          end
        end
      end
      assert.is_not_nil(tool_result)

      local counterpart, counterpart_msg = ast.find_tool_sibling(doc, tool_result)
      assert.is_not_nil(counterpart)
      assert.equals("tool_use", counterpart.kind)
      assert.equals("call_002", counterpart.id)
      assert.is_not_nil(counterpart_msg)
      assert.equals("Assistant", counterpart_msg.role)
    end)

    it("returns nil for tool_use without result", function()
      local doc = parser.parse_lines({
        "@Assistant:",
        "**Tool Use:** `bash` (`call_003`)",
        "```json",
        '{"command": "pwd"}',
        "```",
      })

      local tool_use = nil
      for _, msg in ipairs(doc.messages) do
        for _, seg in ipairs(msg.segments) do
          if seg.kind == "tool_use" then
            tool_use = seg
          end
        end
      end
      assert.is_not_nil(tool_use)

      local counterpart, counterpart_msg = ast.find_tool_sibling(doc, tool_use)
      assert.is_nil(counterpart)
      assert.is_nil(counterpart_msg)
    end)

    it("returns nil for orphan tool_result", function()
      local doc = parser.parse_lines({
        "@You:",
        "**Tool Result:** `call_orphan`",
        "",
        "```",
        "data",
        "```",
      })

      local tool_result = nil
      for _, msg in ipairs(doc.messages) do
        for _, seg in ipairs(msg.segments) do
          if seg.kind == "tool_result" then
            tool_result = seg
          end
        end
      end
      assert.is_not_nil(tool_result)

      local counterpart, counterpart_msg = ast.find_tool_sibling(doc, tool_result)
      assert.is_nil(counterpart)
      assert.is_nil(counterpart_msg)
    end)

    it("handles multiple tool pairs", function()
      local doc = parser.parse_lines({
        "@Assistant:",
        "**Tool Use:** `bash` (`call_a`)",
        "```json",
        '{"command": "ls"}',
        "```",
        "**Tool Use:** `read` (`call_b`)",
        "```json",
        '{"path": "/tmp"}',
        "```",
        "@You:",
        "**Tool Result:** `call_a`",
        "",
        "```",
        "result_a",
        "```",
        "**Tool Result:** `call_b`",
        "",
        "```",
        "result_b",
        "```",
      })

      -- Find call_b tool_use
      local tool_use_b = nil
      for _, msg in ipairs(doc.messages) do
        for _, seg in ipairs(msg.segments) do
          if seg.kind == "tool_use" and seg.id == "call_b" then
            tool_use_b = seg
          end
        end
      end
      assert.is_not_nil(tool_use_b)

      local counterpart = ast.find_tool_sibling(doc, tool_use_b)
      assert.is_not_nil(counterpart)
      assert.equals("tool_result", counterpart.kind)
      assert.equals("call_b", counterpart.tool_use_id)
    end)

    it("returns first match for duplicate tool_result", function()
      -- Simulate re-execution: two tool_results for same tool_use_id
      local doc = parser.parse_lines({
        "@Assistant:",
        "**Tool Use:** `bash` (`call_dup`)",
        "```json",
        '{"command": "echo hi"}',
        "```",
        "@You:",
        "**Tool Result:** `call_dup`",
        "",
        "```",
        "first_result",
        "```",
        "**Tool Result:** `call_dup`",
        "",
        "```",
        "second_result",
        "```",
      })

      local tool_use = nil
      for _, msg in ipairs(doc.messages) do
        for _, seg in ipairs(msg.segments) do
          if seg.kind == "tool_use" then
            tool_use = seg
          end
        end
      end
      assert.is_not_nil(tool_use)

      local counterpart = ast.find_tool_sibling(doc, tool_use)
      assert.is_not_nil(counterpart)
      assert.equals("first_result", counterpart.content)
    end)

    it("works with intermediate status tool_result", function()
      local doc = parser.parse_lines({
        "@Assistant:",
        "**Tool Use:** `bash` (`call_pending`)",
        "```json",
        '{"command": "rm -rf /"}',
        "```",
        "@You:",
        "**Tool Result:** `call_pending`",
        "",
        "```flemma:tool status=pending",
        "```",
      })

      local tool_use = nil
      for _, msg in ipairs(doc.messages) do
        for _, seg in ipairs(msg.segments) do
          if seg.kind == "tool_use" then
            tool_use = seg
          end
        end
      end
      assert.is_not_nil(tool_use)

      local counterpart = ast.find_tool_sibling(doc, tool_use)
      assert.is_not_nil(counterpart)
      assert.equals("tool_result", counterpart.kind)
      assert.equals("pending", counterpart.status)
    end)
  end)
end)
