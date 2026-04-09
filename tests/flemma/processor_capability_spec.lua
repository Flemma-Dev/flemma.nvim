--- Tests for processor capability-gated tool result template evaluation.
--- Verifies that tool results from tools with `template_tool_result` capability
--- get their segments compiled, while tools without the capability use fallback.

local ast = require("flemma.ast")
local ctx = require("flemma.context")

describe("Processor: capability-gated tool result evaluation", function()
  local processor
  local registry

  before_each(function()
    -- Clear caches for isolation
    package.loaded["flemma.processor"] = nil
    package.loaded["flemma.tools.registry"] = nil
    package.loaded["flemma.ast.query"] = nil

    processor = require("flemma.processor")
    registry = require("flemma.tools.registry")

    -- Start with a clean registry for each test
    registry.clear()
  end)

  after_each(function()
    registry.clear()
  end)

  --- Build a minimal document with a tool_use/tool_result pair.
  --- @param tool_name string
  --- @param tool_use_id string
  --- @param result_segments flemma.ast.Segment[] Inner segments of the tool_result
  --- @param content string
  --- @return flemma.ast.DocumentNode
  local function build_doc(tool_name, tool_use_id, result_segments, content)
    local pos = { start_line = 1, end_line = 1 }
    local assistant_msg = ast.message("Assistant", {
      ast.tool_use(tool_use_id, tool_name, {}, pos),
    }, pos)
    local you_msg = ast.message("You", {
      ast.tool_result(tool_use_id, {
        segments = result_segments,
        content = content,
        is_error = false,
        start_line = 2,
        end_line = 4,
      }),
    }, pos)
    return ast.document(nil, { assistant_msg, you_msg }, {}, pos)
  end

  it("compiles segments for a tool WITH template_tool_result capability", function()
    -- Register a tool that opts in to template evaluation
    registry.register("capable_tool", {
      name = "capable_tool",
      description = "A tool that opts in",
      input_schema = { type = "object", properties = {} },
      capabilities = { "template_tool_result" },
    })

    local inner_segments = { ast.text("hello from template", nil) }
    local doc = build_doc("capable_tool", "call_001", inner_segments, "fallback text")
    local base = ctx.clone(nil)
    local result = processor.evaluate(doc, base)

    -- The @You message should have a tool_result part
    assert.equals(2, #result.messages)
    local you_parts = result.messages[2].parts
    -- Should have exactly one tool_result part
    assert.equals(1, #you_parts)
    local tr_part = you_parts[1]
    assert.equals("tool_result", tr_part.kind)
    assert.equals("call_001", tr_part.tool_use_id)
    -- With template_tool_result capability, .parts should be populated from segments
    assert.is_not_nil(tr_part.parts, "Expected .parts to be set for opted-in tool")
    assert.equals(1, #tr_part.parts)
    assert.equals("text", tr_part.parts[1].kind)
    assert.equals("hello from template", tr_part.parts[1].text)
  end)

  it("collapses segments to fallback for a tool WITHOUT the capability", function()
    -- Register a tool that does NOT opt in
    registry.register("plain_tool", {
      name = "plain_tool",
      description = "A tool without the capability",
      input_schema = { type = "object", properties = {} },
      -- No capabilities field
    })

    local inner_segments = { ast.text("rich content that should be ignored", nil) }
    local doc = build_doc("plain_tool", "call_002", inner_segments, "plain fallback")
    local base = ctx.clone(nil)
    local result = processor.evaluate(doc, base)

    assert.equals(2, #result.messages)
    local you_parts = result.messages[2].parts
    assert.equals(1, #you_parts)
    local tr_part = you_parts[1]
    assert.equals("tool_result", tr_part.kind)
    assert.equals("call_002", tr_part.tool_use_id)
    -- Without the capability, content is used — no .parts from segments
    -- The part should carry the content string
    assert.equals("plain fallback", tr_part.content)
    -- .parts should NOT be present (it's a ToolResultPart, not a compiled one)
    assert.is_nil(tr_part.parts)
  end)

  it("tool_result with empty segments passes through unchanged (already collapsed)", function()
    -- A tool that would have capability, but tool_result already has no segments
    registry.register("capable_tool2", {
      name = "capable_tool2",
      description = "Opted-in but empty result",
      input_schema = { type = "object", properties = {} },
      capabilities = { "template_tool_result" },
    })

    local doc = build_doc("capable_tool2", "call_003", {}, "fallback for empty")
    local base = ctx.clone(nil)
    local result = processor.evaluate(doc, base)

    local you_parts = result.messages[2].parts
    assert.equals(1, #you_parts)
    local tr_part = you_parts[1]
    assert.equals("tool_result", tr_part.kind)
    -- Empty segments -> no .parts created through capture
    assert.is_nil(tr_part.parts)
    assert.equals("fallback for empty", tr_part.content)
  end)

  it("unknown tool_use_id (no matching use) collapses to content", function()
    -- No tool_use segment with matching id in the doc
    local pos = { start_line = 1, end_line = 1 }
    local you_msg = ast.message("You", {
      ast.tool_result("orphan_id", {
        segments = { ast.text("content", nil) },
        content = "orphan fallback",
        is_error = false,
        start_line = 1,
        end_line = 2,
      }),
    }, pos)
    local doc = ast.document(nil, { you_msg }, {}, pos)
    local base = ctx.clone(nil)
    local result = processor.evaluate(doc, base)

    local you_parts = result.messages[1].parts
    assert.equals(1, #you_parts)
    local tr_part = you_parts[1]
    assert.equals("tool_result", tr_part.kind)
    -- No matching tool_use → info is nil → collapses to content
    assert.is_nil(tr_part.parts)
    assert.equals("orphan fallback", tr_part.content)
  end)

  it("non-tool-result segments in @You messages pass through unchanged", function()
    registry.register("any_tool", {
      name = "any_tool",
      description = "Any tool",
      input_schema = { type = "object", properties = {} },
    })

    local pos = { start_line = 1, end_line = 1 }
    local you_msg = ast.message("You", {
      ast.text("Hello world", nil),
    }, pos)
    local doc = ast.document(nil, { you_msg }, {}, pos)
    local base = ctx.clone(nil)
    local result = processor.evaluate(doc, base)

    local you_parts = result.messages[1].parts
    assert.equals(1, #you_parts)
    assert.equals("text", you_parts[1].kind)
    assert.equals("Hello world", you_parts[1].text)
  end)
end)
