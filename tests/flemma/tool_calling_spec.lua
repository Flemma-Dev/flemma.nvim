package.loaded["flemma.tools"] = nil
package.loaded["flemma.tools.registry"] = nil
package.loaded["flemma.tools.definitions.calculator"] = nil

local ast = require("flemma.ast")
local ctx = require("flemma.context")
local parser = require("flemma.parser")
local processor = require("flemma.processor")
local pipeline = require("flemma.pipeline")
local tools = require("flemma.tools")
local codeblock = require("flemma.codeblock")

describe("Tool Registry", function()
  before_each(function()
    tools.clear()
  end)

  it("registers and retrieves tools", function()
    tools.register("test_tool", {
      name = "test_tool",
      description = "A test tool",
      input_schema = {
        type = "object",
        properties = {
          value = { type = "string" },
        },
        required = { "value" },
      },
    })

    local tool = tools.get("test_tool")
    assert.is_not_nil(tool)
    assert.equals("test_tool", tool.name)
    assert.equals("A test tool", tool.description)
  end)

  it("returns all registered tools", function()
    tools.register("tool1", { name = "tool1", description = "First", input_schema = {} })
    tools.register("tool2", { name = "tool2", description = "Second", input_schema = {} })

    local all = tools.get_all()
    assert.is_not_nil(all.tool1)
    assert.is_not_nil(all.tool2)
    assert.equals(2, tools.count())
  end)

  it("clears all tools", function()
    tools.register("tool1", { name = "tool1", description = "First", input_schema = {} })
    assert.equals(1, tools.count())

    tools.clear()
    assert.equals(0, tools.count())
  end)
end)

describe("Calculator Tool", function()
  before_each(function()
    tools.clear()
    tools.setup()
  end)

  it("is registered on setup", function()
    local calc = tools.get("calculator")
    assert.is_not_nil(calc)
    assert.equals("calculator", calc.name)
    assert.is_not_nil(calc.input_schema)
    assert.is_not_nil(calc.input_schema.properties.expression)
  end)
end)

describe("Codeblock Utilities", function()
  it("generates fence with correct length", function()
    assert.equals("```", codeblock.get_fence("simple text"))
    assert.equals("````", codeblock.get_fence("text with ``` backticks"))
    assert.equals("`````", codeblock.get_fence("text with ```` four backticks"))
  end)

  it("parses fenced code block", function()
    local lines = {
      "```json",
      '{ "expression": "15 * 7" }',
      "```",
    }
    local block, end_idx = codeblock.parse_fenced_block(lines, 1)
    assert.is_not_nil(block)
    assert.equals("json", block.language)
    assert.equals('{ "expression": "15 * 7" }', block.content)
    assert.equals(3, end_idx)
  end)

  it("parses multi-line fenced block", function()
    local lines = {
      "````json",
      "{",
      '  "key": "value",',
      '  "nested": "```code```"',
      "}",
      "````",
    }
    local block, end_idx = codeblock.parse_fenced_block(lines, 1)
    assert.is_not_nil(block)
    assert.equals("json", block.language)
    assert.equals(4, block.fence_length)
    assert.equals(6, end_idx)
  end)

  it("returns nil for non-fenced content", function()
    local lines = { "regular text", "more text" }
    local block, end_idx = codeblock.parse_fenced_block(lines, 1)
    assert.is_nil(block)
    assert.equals(1, end_idx)
  end)

  it("skips blank lines correctly", function()
    local lines = { "", "  ", "content", "" }
    assert.equals(3, codeblock.skip_blank_lines(lines, 1))
    assert.equals(3, codeblock.skip_blank_lines(lines, 2))
    assert.equals(3, codeblock.skip_blank_lines(lines, 3))
    assert.equals(5, codeblock.skip_blank_lines(lines, 4))
  end)
end)

describe("AST Tool Nodes", function()
  it("creates tool_use node", function()
    local node = ast.tool_use("toolu_123", "calculator", { expression = "1+1" }, { start_line = 5 })
    assert.equals("tool_use", node.kind)
    assert.equals("toolu_123", node.id)
    assert.equals("calculator", node.name)
    assert.equals("1+1", node.input.expression)
    assert.equals(5, node.position.start_line)
  end)

  it("creates tool_result node", function()
    local node = ast.tool_result("toolu_123", "42", false, { start_line = 10 })
    assert.equals("tool_result", node.kind)
    assert.equals("toolu_123", node.tool_use_id)
    assert.equals("42", node.content)
    assert.equals(false, node.is_error)
  end)

  it("creates tool_result error node", function()
    local node = ast.tool_result("toolu_123", "Division by zero", true, { start_line = 10 })
    assert.equals("tool_result", node.kind)
    assert.equals(true, node.is_error)
  end)
end)

describe("Parser Tool Blocks", function()
  it("parses tool_use block from assistant message", function()
    local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_with_tools.chat")
    local doc = parser.parse_lines(lines)

    -- Messages: 1=System, 2=You, 3=Assistant (with tool_use), 4=You (tool_result), 5=Assistant
    local assistant_msg = doc.messages[3]
    assert.equals("Assistant", assistant_msg.role)

    local tool_use = nil
    for _, seg in ipairs(assistant_msg.segments) do
      if seg.kind == "tool_use" then
        tool_use = seg
      end
    end

    assert.is_not_nil(tool_use, "Should have tool_use segment")
    assert.equals("calculator", tool_use.name)
    assert.equals("toolu_01A09q90qw90lq917835lgs0", tool_use.id)
    assert.equals("15 * 7", tool_use.input.expression)
  end)

  it("parses tool_result with plain fenced block from user message", function()
    local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_with_tools.chat")
    local doc = parser.parse_lines(lines)

    -- Messages: 1=System, 2=You, 3=Assistant, 4=You (tool_result), 5=Assistant
    local user_msg = doc.messages[4]
    assert.equals("You", user_msg.role)

    local tool_result = nil
    for _, seg in ipairs(user_msg.segments) do
      if seg.kind == "tool_result" then
        tool_result = seg
      end
    end

    assert.is_not_nil(tool_result, "Should have tool_result segment")
    assert.equals("toolu_01A09q90qw90lq917835lgs0", tool_result.tool_use_id)
    assert.equals("105", tool_result.content)
    assert.equals(false, tool_result.is_error)
  end)

  it("parses tool_result with JSON code block", function()
    local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_tool_result_json.chat")
    local doc = parser.parse_lines(lines)

    -- Messages: 1=System, 2=You, 3=Assistant, 4=You (tool_result)
    local user_msg = doc.messages[4]
    local tool_result = nil
    for _, seg in ipairs(user_msg.segments) do
      if seg.kind == "tool_result" then
        tool_result = seg
      end
    end

    assert.is_not_nil(tool_result)
    assert.equals("toolu_01A09q90qw90lq917835lgs0", tool_result.tool_use_id)
    assert.is_true(tool_result.content:match("105") ~= nil, "Should contain result value")
  end)

  it("parses tool_result with plain fenced block (no language)", function()
    local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_tool_result_plain_fenced.chat")
    local doc = parser.parse_lines(lines)

    -- Messages: 1=System, 2=You, 3=Assistant, 4=You (tool_result with plain fenced block)
    local user_msg = doc.messages[4]
    local tool_result = nil
    for _, seg in ipairs(user_msg.segments) do
      if seg.kind == "tool_result" then
        tool_result = seg
      end
    end

    assert.is_not_nil(tool_result)
    assert.equals("toolu_01PLAIN123", tool_result.tool_use_id)
    assert.equals(false, tool_result.is_error)
    assert.equals("this is a result of a tool\nwith multiple lines", tool_result.content)
  end)

  it("parses tool_result with error marker", function()
    local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_tool_error.chat")
    local doc = parser.parse_lines(lines)

    -- Messages: 1=System, 2=You, 3=Assistant, 4=You (tool_result with error)
    local user_msg = doc.messages[4]
    local tool_result = nil
    for _, seg in ipairs(user_msg.segments) do
      if seg.kind == "tool_result" then
        tool_result = seg
      end
    end

    assert.is_not_nil(tool_result)
    assert.equals("toolu_01ERROR123", tool_result.tool_use_id)
    assert.equals(true, tool_result.is_error)
    assert.is_true(tool_result.content:match("Division by zero") ~= nil)
  end)

  it("handles nested backticks with dynamic fence sizing", function()
    local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_nested_backticks.chat")
    local doc = parser.parse_lines(lines)

    assert.equals(0, #doc.errors, "Should parse without errors")

    -- Messages: 1=System, 2=You, 3=Assistant (with tool_use)
    local assistant_msg = doc.messages[3]
    local tool_use = nil
    for _, seg in ipairs(assistant_msg.segments) do
      if seg.kind == "tool_use" then
        tool_use = seg
      end
    end

    assert.is_not_nil(tool_use)
    assert.equals("generate_code", tool_use.name)
    assert.is_true(tool_use.input.template:match("```python") ~= nil, "Should contain nested markdown code block")
  end)

  it("emits warning for malformed tool result and treats as plain text", function()
    local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_malformed_tool_result.chat")
    local doc = parser.parse_lines(lines)

    -- Should have a diagnostic warning about malformed JSON
    assert.is_true(#doc.errors > 0, "Should have parsing diagnostics")
    local has_warning = false
    for _, err in ipairs(doc.errors) do
      if err.type == "tool_result" and err.severity == "warning" then
        has_warning = true
      end
    end
    assert.is_true(has_warning, "Should have tool_result warning")

    -- Messages: 1=System, 2=You, 3=Assistant, 4=You (malformed tool_result)
    local user_msg = doc.messages[4]
    assert.is_not_nil(user_msg)
    assert.equals("You", user_msg.role)

    -- Should still parse a tool_result with the raw content
    local tool_result = nil
    for _, seg in ipairs(user_msg.segments) do
      if seg.kind == "tool_result" then
        tool_result = seg
      end
    end
    assert.is_not_nil(tool_result, "Should have tool_result segment despite malformed JSON")
    assert.equals("toolu_01A09q90qw90lq917835lgs0", tool_result.tool_use_id)
  end)

  it("emits warning for unsupported YAML format in tool result", function()
    local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_tool_result_yaml.chat")
    local doc = parser.parse_lines(lines)

    -- Should have a diagnostic warning about YAML not being supported
    assert.is_true(#doc.errors > 0, "Should have parsing diagnostics for unsupported YAML")
    local has_yaml_warning = false
    for _, err in ipairs(doc.errors) do
      if err.type == "tool_result" and err.error:match("yaml") then
        has_yaml_warning = true
      end
    end
    assert.is_true(has_yaml_warning, "Should warn about unsupported YAML parser")

    -- Messages: 1=System, 2=You, 3=Assistant, 4=You (yaml tool_result), 5=Assistant
    local user_msg = doc.messages[4]
    local tool_result = nil
    for _, seg in ipairs(user_msg.segments) do
      if seg.kind == "tool_result" then
        tool_result = seg
      end
    end

    -- Should still have a tool_result with raw YAML content
    assert.is_not_nil(tool_result)
    assert.equals("toolu_01A09q90qw90lq917835lgs0", tool_result.tool_use_id)
    assert.is_true(tool_result.content:match("result") ~= nil, "Should contain raw YAML content")
  end)
end)

describe("Processor Tool Parts", function()
  it("preserves tool_use parts in evaluation", function()
    local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_with_tools.chat")
    local doc = parser.parse_lines(lines)
    local out = processor.evaluate(doc, ctx.from_file("tests/fixtures/tool_calling/conversation_with_tools.chat"))

    -- Messages: 1=System, 2=You, 3=Assistant (with tool_use), 4=You (tool_result), 5=Assistant
    local assistant_msg = out.messages[3]
    local has_tool_use = false
    for _, p in ipairs(assistant_msg.parts) do
      if p.kind == "tool_use" then
        has_tool_use = true
        assert.equals("calculator", p.name)
        assert.equals("toolu_01A09q90qw90lq917835lgs0", p.id)
        assert.equals("15 * 7", p.input.expression)
      end
    end
    assert.is_true(has_tool_use, "Should have tool_use part")
  end)

  it("preserves tool_result parts in evaluation", function()
    local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_with_tools.chat")
    local doc = parser.parse_lines(lines)
    local out = processor.evaluate(doc, ctx.from_file("tests/fixtures/tool_calling/conversation_with_tools.chat"))

    -- Messages: 1=System, 2=You, 3=Assistant, 4=You (tool_result), 5=Assistant
    local user_msg = out.messages[4]
    local has_tool_result = false
    for _, p in ipairs(user_msg.parts) do
      if p.kind == "tool_result" then
        has_tool_result = true
        assert.equals("toolu_01A09q90qw90lq917835lgs0", p.tool_use_id)
        assert.equals("105", p.content)
        assert.equals(false, p.is_error)
      end
    end
    assert.is_true(has_tool_result, "Should have tool_result part")
  end)
end)

describe("Anthropic Provider Tool Support", function()
  local anthropic = require("flemma.provider.providers.anthropic")

  before_each(function()
    tools.clear()
    tools.setup()
  end)

  it("includes tools array in request when tools are registered", function()
    local provider = anthropic.new({ model = "claude-sonnet-4-20250514", max_tokens = 1024, temperature = 0 })

    local lines = {
      "@System: You have access to a calculator.",
      "@You: What is 15 * 7?",
    }
    local prompt = pipeline.run(lines, ctx.from_file("tests/fixtures/doc.chat"))
    local req = provider:build_request(prompt, {})

    assert.is_not_nil(req.tools, "Request should include tools array")
    assert.equals(1, #req.tools)
    assert.equals("calculator", req.tools[1].name)
  end)

  it("includes tool_choice with disable_parallel_tool_use", function()
    local provider = anthropic.new({ model = "claude-sonnet-4-20250514", max_tokens = 1024, temperature = 0 })

    local lines = { "@You: Calculate something" }
    local prompt = pipeline.run(lines, ctx.from_file("tests/fixtures/doc.chat"))
    local req = provider:build_request(prompt, {})

    assert.is_not_nil(req.tool_choice)
    assert.equals("auto", req.tool_choice.type)
    assert.equals(true, req.tool_choice.disable_parallel_tool_use)
  end)

  it("includes tool_use in assistant message content", function()
    local provider = anthropic.new({ model = "claude-sonnet-4-20250514", max_tokens = 1024, temperature = 0 })

    local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_with_tools.chat")
    local prompt = pipeline.run(lines, ctx.from_file("tests/fixtures/tool_calling/conversation_with_tools.chat"))
    local req = provider:build_request(prompt, {})

    local assistant_msg = nil
    for _, msg in ipairs(req.messages) do
      if msg.role == "assistant" then
        assistant_msg = msg
        break
      end
    end

    assert.is_not_nil(assistant_msg)
    local has_tool_use = false
    for _, block in ipairs(assistant_msg.content) do
      if block.type == "tool_use" then
        has_tool_use = true
        assert.equals("toolu_01A09q90qw90lq917835lgs0", block.id)
        assert.equals("calculator", block.name)
        assert.equals("15 * 7", block.input.expression)
      end
    end
    assert.is_true(has_tool_use, "Assistant message should include tool_use block")
  end)

  it("includes tool_result in user message content with correct ordering", function()
    local provider = anthropic.new({ model = "claude-sonnet-4-20250514", max_tokens = 1024, temperature = 0 })

    local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_with_tools.chat")
    local prompt = pipeline.run(lines, ctx.from_file("tests/fixtures/tool_calling/conversation_with_tools.chat"))
    local req = provider:build_request(prompt, {})

    local user_msgs = vim.tbl_filter(function(m)
      return m.role == "user"
    end, req.messages)
    local tool_result_msg = user_msgs[2]

    assert.is_not_nil(tool_result_msg)
    assert.equals("tool_result", tool_result_msg.content[1].type, "tool_result should be first in content array")
    assert.equals("toolu_01A09q90qw90lq917835lgs0", tool_result_msg.content[1].tool_use_id)
    assert.equals("105", tool_result_msg.content[1].content)
  end)

  it("includes is_error in tool_result when error marker is present", function()
    local provider = anthropic.new({ model = "claude-sonnet-4-20250514", max_tokens = 1024, temperature = 0 })

    local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_tool_error.chat")
    local prompt = pipeline.run(lines, ctx.from_file("tests/fixtures/tool_calling/conversation_tool_error.chat"))
    local req = provider:build_request(prompt, {})

    local user_msgs = vim.tbl_filter(function(m)
      return m.role == "user"
    end, req.messages)
    local tool_result_msg = user_msgs[2]

    assert.is_not_nil(tool_result_msg)
    local tool_result = tool_result_msg.content[1]
    assert.equals("tool_result", tool_result.type)
    assert.equals(true, tool_result.is_error)
    assert.is_true(tool_result.content:match("Division by zero") ~= nil)
  end)
end)

describe("Anthropic Streaming Tool Use Response", function()
  local anthropic = require("flemma.provider.providers.anthropic")

  before_each(function()
    tools.clear()
    tools.setup()
  end)

  it("parses tool_use from streaming response", function()
    local provider = anthropic.new({ model = "claude-sonnet-4-20250514", max_tokens = 1024, temperature = 0 })

    local lines = vim.fn.readfile("tests/fixtures/tool_calling/anthropic_tool_use_streaming.txt")
    local accumulated_content = ""
    local response_complete = false

    local callbacks = {
      on_content = function(content)
        accumulated_content = accumulated_content .. content
      end,
      on_response_complete = function()
        response_complete = true
      end,
    }

    for _, line in ipairs(lines) do
      provider:process_response_line(line, callbacks)
    end

    -- Should have emitted tool_use formatted block
    assert.is_true(accumulated_content:match("%*%*Tool Use:%*%*") ~= nil, "Should emit tool_use header")
    assert.is_true(accumulated_content:match("calculator") ~= nil, "Should include tool name")
    assert.is_true(accumulated_content:match("toolu_01MiSdzFh4udQYmCHCVbtDHw") ~= nil, "Should include tool id")
    assert.is_true(accumulated_content:match("15 %* 7") ~= nil, "Should include expression")
    assert.is_true(response_complete, "Should signal response complete")
  end)

  it("parses final text response after tool result", function()
    local provider = anthropic.new({ model = "claude-sonnet-4-20250514", max_tokens = 1024, temperature = 0 })

    local lines = vim.fn.readfile("tests/fixtures/tool_calling/anthropic_final_response_streaming.txt")
    local accumulated_content = ""
    local response_complete = false

    local callbacks = {
      on_content = function(content)
        accumulated_content = accumulated_content .. content
      end,
      on_response_complete = function()
        response_complete = true
      end,
    }

    for _, line in ipairs(lines) do
      provider:process_response_line(line, callbacks)
    end

    -- Should have accumulated the text response
    assert.is_true(accumulated_content:match("15") ~= nil, "Should contain response text")
    assert.is_true(accumulated_content:match("multiplied") ~= nil, "Should contain response text")
    assert.is_true(accumulated_content:match("105") ~= nil, "Should contain answer")
    assert.is_true(response_complete, "Should signal response complete")
  end)

  it("tracks usage from streaming events", function()
    local provider = anthropic.new({ model = "claude-sonnet-4-20250514", max_tokens = 1024, temperature = 0 })

    local lines = vim.fn.readfile("tests/fixtures/tool_calling/anthropic_tool_use_streaming.txt")
    local usage_events = {}

    local callbacks = {
      on_content = function() end,
      on_usage = function(usage)
        table.insert(usage_events, usage)
      end,
    }

    for _, line in ipairs(lines) do
      provider:process_response_line(line, callbacks)
    end

    -- Should have received input tokens from message_start
    local has_input = false
    local has_output = false
    for _, u in ipairs(usage_events) do
      if u.type == "input" then
        has_input = true
        assert.equals(403, u.tokens)
      end
      if u.type == "output" then
        has_output = true
      end
    end
    assert.is_true(has_input, "Should report input tokens")
    assert.is_true(has_output, "Should report output tokens")
  end)
end)

describe("Request Body Validation", function()
  local anthropic = require("flemma.provider.providers.anthropic")

  before_each(function()
    tools.clear()
    tools.setup()
  end)

  it("builds request matching expected structure with tool_result", function()
    local provider = anthropic.new({ model = "claude-sonnet-4-20250514", max_tokens = 4000, temperature = 0 })

    local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_with_tools.chat")
    local prompt = pipeline.run(lines, ctx.from_file("tests/fixtures/tool_calling/conversation_with_tools.chat"))
    local req = provider:build_request(prompt, {})

    -- Validate structure matches expected_tool_result_request.json
    assert.equals("claude-sonnet-4-20250514", req.model)
    assert.equals(4000, req.max_tokens)
    assert.equals(true, req.stream)

    -- Validate tools array
    assert.is_not_nil(req.tools)
    assert.equals(1, #req.tools)
    assert.equals("calculator", req.tools[1].name)
    assert.is_not_nil(req.tools[1].input_schema)
    assert.is_not_nil(req.tools[1].input_schema.properties.expression)

    -- Validate tool_choice
    assert.is_not_nil(req.tool_choice)
    assert.equals("auto", req.tool_choice.type)
    assert.equals(true, req.tool_choice.disable_parallel_tool_use)

    -- Validate message structure
    local user_msgs = vim.tbl_filter(function(m)
      return m.role == "user"
    end, req.messages)
    local assistant_msgs = vim.tbl_filter(function(m)
      return m.role == "assistant"
    end, req.messages)

    -- First user message has text
    assert.equals("text", user_msgs[1].content[1].type)

    -- First assistant message has text and tool_use
    local has_text = false
    local has_tool_use = false
    for _, block in ipairs(assistant_msgs[1].content) do
      if block.type == "text" then
        has_text = true
      end
      if block.type == "tool_use" then
        has_tool_use = true
        assert.equals("calculator", block.name)
        assert.is_not_nil(block.id)
        assert.is_not_nil(block.input)
        assert.equals("15 * 7", block.input.expression)
      end
    end
    assert.is_true(has_text, "Assistant should have text block")
    assert.is_true(has_tool_use, "Assistant should have tool_use block")

    -- Second user message has tool_result first
    assert.equals("tool_result", user_msgs[2].content[1].type)
    assert.is_not_nil(user_msgs[2].content[1].tool_use_id)
    assert.equals("105", user_msgs[2].content[1].content)
  end)
end)

-- ============================================================================
-- OpenAI Provider Tool Calling Tests
-- ============================================================================

describe("OpenAI Provider Request Building with Tools", function()
  local openai = require("flemma.provider.providers.openai")

  before_each(function()
    tools.clear()
    tools.setup()
  end)

  it("includes tools array in OpenAI format", function()
    local provider = openai.new({ model = "gpt-4o-mini", max_tokens = 1024, temperature = 0 })

    local lines = { "@You: Calculate something" }
    local prompt = pipeline.run(lines, ctx.from_file("tests/fixtures/doc.chat"))
    local req = provider:build_request(prompt, {})

    assert.is_not_nil(req.tools, "Request should include tools array")
    assert.equals(1, #req.tools)
    assert.equals("function", req.tools[1].type)
    assert.equals("calculator", req.tools[1]["function"].name)
    assert.is_not_nil(req.tools[1]["function"].parameters)
    assert.is_not_nil(req.tools[1]["function"].parameters.properties.expression)
  end)

  it("includes tool_choice and parallel_tool_calls: false", function()
    local provider = openai.new({ model = "gpt-4o-mini", max_tokens = 1024, temperature = 0 })

    local lines = { "@You: Calculate something" }
    local prompt = pipeline.run(lines, ctx.from_file("tests/fixtures/doc.chat"))
    local req = provider:build_request(prompt, {})

    assert.equals("auto", req.tool_choice)
    assert.equals(false, req.parallel_tool_calls)
  end)

  it("includes tool_calls in assistant message", function()
    local provider = openai.new({ model = "gpt-4o-mini", max_tokens = 1024, temperature = 0 })

    local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_with_tools.chat")
    local prompt = pipeline.run(lines, ctx.from_file("tests/fixtures/tool_calling/conversation_with_tools.chat"))
    local req = provider:build_request(prompt, {})

    local assistant_msg = nil
    for _, msg in ipairs(req.messages) do
      if msg.role == "assistant" then
        assistant_msg = msg
        break
      end
    end

    assert.is_not_nil(assistant_msg)
    assert.is_not_nil(assistant_msg.tool_calls)
    assert.equals(1, #assistant_msg.tool_calls)
    assert.equals("toolu_01A09q90qw90lq917835lgs0", assistant_msg.tool_calls[1].id)
    assert.equals("function", assistant_msg.tool_calls[1].type)
    assert.equals("calculator", assistant_msg.tool_calls[1]["function"].name)
  end)

  it("includes tool results as role:tool messages", function()
    local provider = openai.new({ model = "gpt-4o-mini", max_tokens = 1024, temperature = 0 })

    local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_with_tools.chat")
    local prompt = pipeline.run(lines, ctx.from_file("tests/fixtures/tool_calling/conversation_with_tools.chat"))
    local req = provider:build_request(prompt, {})

    local tool_msgs = vim.tbl_filter(function(m)
      return m.role == "tool"
    end, req.messages)

    assert.equals(1, #tool_msgs)
    assert.equals("toolu_01A09q90qw90lq917835lgs0", tool_msgs[1].tool_call_id)
    assert.equals("105", tool_msgs[1].content)
  end)

  it("prefixes tool result content with [ERROR] when is_error is true", function()
    local provider = openai.new({ model = "gpt-4o-mini", max_tokens = 1024, temperature = 0 })

    local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_tool_error.chat")
    local prompt = pipeline.run(lines, ctx.from_file("tests/fixtures/tool_calling/conversation_tool_error.chat"))
    local req = provider:build_request(prompt, {})

    local tool_msgs = vim.tbl_filter(function(m)
      return m.role == "tool"
    end, req.messages)

    assert.equals(1, #tool_msgs)
    assert.is_true(tool_msgs[1].content:match("^Error: ") ~= nil, "Error content should be prefixed with 'Error: '")
    assert.is_true(tool_msgs[1].content:match("Division by zero") ~= nil, "Should contain original error message")
  end)

  it("orders tool results before follow-up user content in same message", function()
    local provider = openai.new({ model = "gpt-4o-mini", max_tokens = 1024, temperature = 0 })

    local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_tool_result_with_followup.chat")
    local prompt =
      pipeline.run(lines, ctx.from_file("tests/fixtures/tool_calling/conversation_tool_result_with_followup.chat"))
    local req = provider:build_request(prompt, {})

    -- Find indices of tool message and last user message
    local tool_msg_idx = nil
    local followup_user_msg_idx = nil

    for i, msg in ipairs(req.messages) do
      if msg.role == "tool" then
        tool_msg_idx = i
      elseif msg.role == "user" and msg.content and msg.content:match("20 plus 30") then
        followup_user_msg_idx = i
      end
    end

    assert.is_not_nil(tool_msg_idx, "Should have a tool message")
    assert.is_not_nil(followup_user_msg_idx, "Should have a follow-up user message")
    assert.is_true(tool_msg_idx < followup_user_msg_idx, "Tool result should come BEFORE follow-up user message")
  end)
end)

describe("OpenAI Streaming Tool Use Response", function()
  local openai = require("flemma.provider.providers.openai")

  before_each(function()
    tools.clear()
    tools.setup()
  end)

  it("parses tool_calls from streaming response", function()
    local provider = openai.new({ model = "gpt-4o-mini", max_tokens = 1024, temperature = 0 })

    local lines = vim.fn.readfile("tests/fixtures/tool_calling/openai_tool_use_streaming.txt")
    local accumulated_content = ""
    local response_complete = false

    local callbacks = {
      on_content = function(content)
        accumulated_content = accumulated_content .. content
      end,
      on_response_complete = function()
        response_complete = true
      end,
    }

    for _, line in ipairs(lines) do
      provider:process_response_line(line, callbacks)
    end

    assert.is_true(accumulated_content:match("%*%*Tool Use:%*%*") ~= nil, "Should emit tool_use header")
    assert.is_true(accumulated_content:match("calculator") ~= nil, "Should include tool name")
    assert.is_true(accumulated_content:match("call_zKVQISSUvL3HNmgE80n28JcM") ~= nil, "Should include tool id")
    assert.is_true(accumulated_content:match("15 %* 7") ~= nil, "Should include expression")
  end)

  it("parses text content before tool_calls", function()
    local provider = openai.new({ model = "gpt-4o-mini", max_tokens = 1024, temperature = 0 })

    local lines = vim.fn.readfile("tests/fixtures/tool_calling/openai_text_before_tool_streaming.txt")
    local accumulated_content = ""

    local callbacks = {
      on_content = function(content)
        accumulated_content = accumulated_content .. content
      end,
    }

    for _, line in ipairs(lines) do
      provider:process_response_line(line, callbacks)
    end

    assert.is_true(accumulated_content:match("I will calculate") ~= nil, "Should have text before tool call")
    assert.is_true(accumulated_content:match("23") ~= nil, "Should have text content")
    assert.is_true(accumulated_content:match("45") ~= nil, "Should have text content")
    assert.is_true(accumulated_content:match("%*%*Tool Use:%*%*") ~= nil, "Should emit tool_use header")
    assert.is_true(accumulated_content:match("calculator") ~= nil, "Should include tool name")
  end)

  it("parses final text response after tool result", function()
    local provider = openai.new({ model = "gpt-4o-mini", max_tokens = 1024, temperature = 0 })

    local lines = vim.fn.readfile("tests/fixtures/tool_calling/openai_final_response_streaming.txt")
    local accumulated_content = ""
    local response_complete = false

    local callbacks = {
      on_content = function(content)
        accumulated_content = accumulated_content .. content
      end,
      on_response_complete = function()
        response_complete = true
      end,
    }

    for _, line in ipairs(lines) do
      provider:process_response_line(line, callbacks)
    end

    assert.is_true(accumulated_content:match("15") ~= nil, "Should contain response text")
    assert.is_true(accumulated_content:match("multiplied") ~= nil, "Should contain response text")
    assert.is_true(accumulated_content:match("105") ~= nil, "Should contain answer")
  end)
end)

describe("OpenAI Request Body Validation with Tools", function()
  local openai = require("flemma.provider.providers.openai")

  before_each(function()
    tools.clear()
    tools.setup()
  end)

  it("builds request matching expected OpenAI structure with tool_result", function()
    local provider = openai.new({ model = "gpt-4o-mini", max_tokens = 4000, temperature = 0 })

    local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_with_tools.chat")
    local prompt = pipeline.run(lines, ctx.from_file("tests/fixtures/tool_calling/conversation_with_tools.chat"))
    local req = provider:build_request(prompt, {})

    -- Validate structure matches OpenAI format
    assert.equals("gpt-4o-mini", req.model)
    assert.equals(4000, req.max_completion_tokens)
    assert.equals(true, req.stream)

    -- Validate tools array in OpenAI format
    assert.is_not_nil(req.tools)
    assert.equals(1, #req.tools)
    assert.equals("function", req.tools[1].type)
    assert.equals("calculator", req.tools[1]["function"].name)
    assert.is_not_nil(req.tools[1]["function"].parameters)
    assert.is_not_nil(req.tools[1]["function"].parameters.properties.expression)

    -- Validate tool_choice and parallel_tool_calls
    assert.equals("auto", req.tool_choice)
    assert.equals(false, req.parallel_tool_calls)

    -- Validate message structure
    local assistant_msgs = vim.tbl_filter(function(m)
      return m.role == "assistant"
    end, req.messages)
    local tool_msgs = vim.tbl_filter(function(m)
      return m.role == "tool"
    end, req.messages)

    -- Assistant message has tool_calls
    assert.is_not_nil(assistant_msgs[1].tool_calls)
    assert.equals(1, #assistant_msgs[1].tool_calls)
    assert.equals("calculator", assistant_msgs[1].tool_calls[1]["function"].name)
    assert.is_not_nil(assistant_msgs[1].tool_calls[1].id)

    -- Tool message has tool_call_id and content
    assert.equals(1, #tool_msgs)
    assert.is_not_nil(tool_msgs[1].tool_call_id)
    assert.equals("105", tool_msgs[1].content)
  end)
end)
