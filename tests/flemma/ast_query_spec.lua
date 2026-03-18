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

  describe("build_tool_label_map", function()
    it("returns label for tool_use with input.label", function()
      local query = require("flemma.ast.query")
      local doc = parser.parse_lines({
        "@Assistant:",
        "**Tool Use:** `bash` (`call_001`)",
        "```json",
        '{"command": "ls", "label": "List files", "timeout": 30}',
        "```",
      })
      local map = query.build_tool_label_map(doc)
      assert.are.equal("List files", map["call_001"])
    end)

    it("omits tool_use without input.label", function()
      local query = require("flemma.ast.query")
      local doc = parser.parse_lines({
        "@Assistant:",
        "**Tool Use:** `bash` (`call_002`)",
        "```json",
        '{"command": "ls", "timeout": 30}',
        "```",
      })
      local map = query.build_tool_label_map(doc)
      assert.is_nil(map["call_002"])
    end)

    it("handles multiple tools across messages", function()
      local query = require("flemma.ast.query")
      local doc = parser.parse_lines({
        "@Assistant:",
        "**Tool Use:** `read` (`call_003`)",
        "```json",
        '{"path": "foo.lua", "label": "Reading foo", "offset": null, "limit": null}',
        "```",
        "**Tool Use:** `bash` (`call_004`)",
        "```json",
        '{"command": "ls", "label": "List files", "timeout": 30}',
        "```",
      })
      local map = query.build_tool_label_map(doc)
      assert.are.equal("Reading foo", map["call_003"])
      assert.are.equal("List files", map["call_004"])
    end)

    it("ignores tool_result segments", function()
      local query = require("flemma.ast.query")
      local doc = parser.parse_lines({
        "@You:",
        "**Tool Result:** `call_005`",
        "",
        "```",
        "output",
        "```",
      })
      local map = query.build_tool_label_map(doc)
      assert.is_nil(map["call_005"])
    end)
  end)

  describe("build_tool_sibling_table", function()
    it("returns empty table for empty document", function()
      local doc = parser.parse_lines({})
      local table_ = ast.build_tool_sibling_table(doc)
      assert.same({}, table_)
    end)

    it("indexes paired tool use and result", function()
      local doc = parser.parse_lines({
        "@Assistant:",
        "**Tool Use:** `bash` (`call_x`)",
        "```json",
        '{"command": "ls"}',
        "```",
        "@You:",
        "**Tool Result:** `call_x`",
        "",
        "```",
        "output",
        "```",
      })

      local siblings = ast.build_tool_sibling_table(doc)
      assert.is_not_nil(siblings["call_x"])
      assert.is_not_nil(siblings["call_x"].use)
      assert.equals("bash", siblings["call_x"].use.name)
      assert.is_not_nil(siblings["call_x"].use_message)
      assert.equals("Assistant", siblings["call_x"].use_message.role)
      assert.is_not_nil(siblings["call_x"].result)
      assert.equals("call_x", siblings["call_x"].result.tool_use_id)
      assert.is_not_nil(siblings["call_x"].result_message)
      assert.equals("You", siblings["call_x"].result_message.role)
    end)

    it("handles orphan tool_use (no result)", function()
      local doc = parser.parse_lines({
        "@Assistant:",
        "**Tool Use:** `bash` (`call_orphan_use`)",
        "```json",
        '{"command": "pwd"}',
        "```",
      })

      local siblings = ast.build_tool_sibling_table(doc)
      assert.is_not_nil(siblings["call_orphan_use"])
      assert.is_not_nil(siblings["call_orphan_use"].use)
      assert.is_nil(siblings["call_orphan_use"].result)
    end)

    it("last tool_result wins for duplicate tool_use_id", function()
      local doc = parser.parse_lines({
        "@Assistant:",
        "**Tool Use:** `bash` (`call_dup2`)",
        "```json",
        '{"command": "echo"}',
        "```",
        "@You:",
        "**Tool Result:** `call_dup2`",
        "",
        "```",
        "first",
        "```",
        "**Tool Result:** `call_dup2`",
        "",
        "```",
        "second",
        "```",
      })

      local siblings = ast.build_tool_sibling_table(doc)
      assert.is_not_nil(siblings["call_dup2"])
      assert.equals("second", siblings["call_dup2"].result.content)
    end)

    it("preserves status on tool_result entries", function()
      local doc = parser.parse_lines({
        "@Assistant:",
        "**Tool Use:** `bash` (`call_status`)",
        "```json",
        '{"command": "rm /"}',
        "```",
        "@You:",
        "**Tool Result:** `call_status`",
        "",
        "```flemma:tool status=pending",
        "```",
      })

      local siblings = ast.build_tool_sibling_table(doc)
      assert.is_not_nil(siblings["call_status"])
      assert.is_not_nil(siblings["call_status"].result)
      assert.equals("pending", siblings["call_status"].result.status)
    end)

    it("indexes multiple pairs correctly", function()
      local doc = parser.parse_lines({
        "@Assistant:",
        "**Tool Use:** `bash` (`id_1`)",
        "```json",
        '{"command": "a"}',
        "```",
        "**Tool Use:** `read` (`id_2`)",
        "```json",
        '{"path": "b"}',
        "```",
        "@You:",
        "**Tool Result:** `id_1`",
        "",
        "```",
        "res_a",
        "```",
        "**Tool Result:** `id_2`",
        "",
        "```",
        "res_b",
        "```",
      })

      local siblings = ast.build_tool_sibling_table(doc)
      assert.is_not_nil(siblings["id_1"])
      assert.is_not_nil(siblings["id_2"])
      assert.equals("bash", siblings["id_1"].use.name)
      assert.equals("read", siblings["id_2"].use.name)
      assert.equals("res_a", siblings["id_1"].result.content)
      assert.equals("res_b", siblings["id_2"].result.content)
    end)
  end)
end)
