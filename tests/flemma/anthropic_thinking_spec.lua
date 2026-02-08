--- Test file for Anthropic provider extended thinking functionality
local pipeline = require("flemma.pipeline")
local ctx = require("flemma.context")

describe("Anthropic Provider Extended Thinking", function()
  local anthropic = require("flemma.provider.providers.anthropic")

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  describe("build_request", function()
    it("should include thinking config when thinking_budget >= 1024", function()
      local provider = anthropic.new({
        model = "claude-sonnet-4-5-20250929",
        thinking_budget = 10000,
        max_tokens = 16000,
        temperature = 0.7,
      })

      local prompt = {
        system = "You are helpful.",
        history = {
          { role = "user", parts = { { kind = "text", text = "Hello" } } },
        },
      }

      local request = provider:build_request(prompt, {})

      assert.is_not_nil(request.thinking, "Request should include thinking config")
      assert.are.equal("enabled", request.thinking.type)
      assert.are.equal(10000, request.thinking.budget_tokens)
      assert.is_nil(request.temperature, "Temperature should be removed when thinking is enabled")
    end)

    it("should not include thinking config when thinking_budget is nil", function()
      local provider = anthropic.new({
        model = "claude-sonnet-4-5-20250929",
        max_tokens = 4000,
        temperature = 0.7,
      })

      local prompt = {
        system = "You are helpful.",
        history = {
          { role = "user", parts = { { kind = "text", text = "Hello" } } },
        },
      }

      local request = provider:build_request(prompt, {})

      assert.is_nil(request.thinking, "Request should not include thinking config when budget is nil")
      assert.are.equal(0.7, request.temperature, "Temperature should be preserved when thinking is disabled")
    end)

    it("should not include thinking config when thinking_budget is 0", function()
      local provider = anthropic.new({
        model = "claude-sonnet-4-5-20250929",
        thinking_budget = 0,
        max_tokens = 4000,
        temperature = 0.7,
      })

      local prompt = {
        system = "You are helpful.",
        history = {
          { role = "user", parts = { { kind = "text", text = "Hello" } } },
        },
      }

      local request = provider:build_request(prompt, {})

      assert.is_nil(request.thinking, "Request should not include thinking config when budget is 0")
      assert.are.equal(0.7, request.temperature, "Temperature should be preserved when thinking is disabled")
    end)

    it("should not include thinking config when thinking_budget is below 1024", function()
      local provider = anthropic.new({
        model = "claude-sonnet-4-5-20250929",
        thinking_budget = 500,
        max_tokens = 4000,
        temperature = 0.7,
      })

      local prompt = {
        system = "You are helpful.",
        history = {
          { role = "user", parts = { { kind = "text", text = "Hello" } } },
        },
      }

      local request = provider:build_request(prompt, {})

      assert.is_nil(request.thinking, "Request should not include thinking config when budget < 1024")
      assert.are.equal(0.7, request.temperature, "Temperature should be preserved when thinking is invalid")
    end)

    it("should floor thinking_budget to integer", function()
      local provider = anthropic.new({
        model = "claude-sonnet-4-5-20250929",
        thinking_budget = 2048.7,
        max_tokens = 4000,
      })

      local prompt = {
        system = "You are helpful.",
        history = {
          { role = "user", parts = { { kind = "text", text = "Hello" } } },
        },
      }

      local request = provider:build_request(prompt, {})

      assert.is_not_nil(request.thinking)
      assert.are.equal(2048, request.thinking.budget_tokens, "Budget should be floored to integer")
    end)
  end)

  describe("process_response_line", function()
    it("should accumulate thinking deltas and emit at message_stop", function()
      local provider = anthropic.new({
        model = "claude-sonnet-4-5-20250929",
        thinking_budget = 2048,
        max_tokens = 4000,
      })

      local content_parts = {}
      local completed = false
      local callbacks = {
        on_content = function(content)
          table.insert(content_parts, content)
        end,
        on_response_complete = function()
          completed = true
        end,
      }

      -- Simulate content_block_start for thinking
      provider:process_response_line(
        'data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}',
        callbacks
      )

      -- Simulate thinking deltas
      provider:process_response_line(
        'data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Let me think..."}}',
        callbacks
      )
      provider:process_response_line(
        'data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":" about this."}}',
        callbacks
      )

      -- Simulate content_block_stop for thinking
      provider:process_response_line('data: {"type":"content_block_stop","index":0}', callbacks)

      -- No content should have been emitted yet (thinking is deferred)
      assert.are.equal(0, #content_parts, "No content should be emitted during thinking")

      -- Simulate content_block_start for text
      provider:process_response_line(
        'data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}',
        callbacks
      )

      -- Simulate text deltas
      provider:process_response_line(
        'data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello!"}}',
        callbacks
      )

      -- Text content should be emitted immediately
      assert.are.equal(1, #content_parts)
      assert.are.equal("Hello!", content_parts[1])

      -- Simulate content_block_stop for text
      provider:process_response_line('data: {"type":"content_block_stop","index":1}', callbacks)

      -- Simulate message_stop - this should emit the accumulated thinking
      provider:process_response_line('data: {"type":"message_stop"}', callbacks)

      -- Now we should have text + thinking block
      assert.are.equal(2, #content_parts)
      assert.is_truthy(content_parts[2]:match("<thinking>"))
      assert.is_truthy(content_parts[2]:match("Let me think... about this."))
      assert.is_truthy(content_parts[2]:match("</thinking>"))
      assert.is_true(completed)
    end)

    it("should not emit thinking block when no thinking was accumulated", function()
      local provider = anthropic.new({
        model = "claude-sonnet-4-5-20250929",
        max_tokens = 4000,
      })

      local content_parts = {}
      local completed = false
      local callbacks = {
        on_content = function(content)
          table.insert(content_parts, content)
        end,
        on_response_complete = function()
          completed = true
        end,
      }

      -- Simulate text content only (no thinking)
      provider:process_response_line(
        'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}',
        callbacks
      )
      provider:process_response_line(
        'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Just text."}}',
        callbacks
      )
      provider:process_response_line('data: {"type":"content_block_stop","index":0}', callbacks)
      provider:process_response_line('data: {"type":"message_stop"}', callbacks)

      -- Only text content, no thinking block
      assert.are.equal(1, #content_parts)
      assert.are.equal("Just text.", content_parts[1])
      assert.is_true(completed)
    end)

    it("should track current block type correctly", function()
      local provider = anthropic.new({
        model = "claude-sonnet-4-5-20250929",
        thinking_budget = 2048,
        max_tokens = 4000,
      })

      local callbacks = { on_content = function() end }

      -- Initially nil
      assert.is_nil(provider._response_buffer.extra.current_block_type)

      -- After content_block_start for thinking
      provider:process_response_line(
        'data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}',
        callbacks
      )
      assert.are.equal("thinking", provider._response_buffer.extra.current_block_type)

      -- After content_block_stop
      provider:process_response_line('data: {"type":"content_block_stop","index":0}', callbacks)
      assert.is_nil(provider._response_buffer.extra.current_block_type)

      -- After content_block_start for text
      provider:process_response_line(
        'data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}',
        callbacks
      )
      assert.are.equal("text", provider._response_buffer.extra.current_block_type)
    end)

    it("should capture signature and include in thinking tag", function()
      local provider = anthropic.new({
        model = "claude-sonnet-4-5-20250929",
        thinking_budget = 2048,
        max_tokens = 4000,
      })

      local lines = vim.fn.readfile("tests/fixtures/tool_calling/anthropic_thinking_with_signature_streaming.txt")
      local accumulated_content = ""
      local callbacks = {
        on_content = function(content)
          accumulated_content = accumulated_content .. content
        end,
        on_response_complete = function() end,
        on_usage = function() end,
      }

      for _, line in ipairs(lines) do
        provider:process_response_line(line, callbacks)
      end

      -- Should include thinking tag with anthropic:signature attribute (structural check)
      assert.is_truthy(
        accumulated_content:match('<thinking anthropic:signature="[^"]+">'),
        "Should emit thinking tag with anthropic:signature"
      )
      assert.is_truthy(accumulated_content:match("</thinking>"))
      -- Should have text content outside the thinking block
      local text_outside_thinking = accumulated_content:gsub("<thinking.-</thinking>", "")
      assert.is_truthy(vim.trim(text_outside_thinking) ~= "", "Should have text response outside thinking block")
    end)

    it("should capture redacted thinking and emit as <thinking redacted> block", function()
      local provider = anthropic.new({
        model = "claude-sonnet-4-5-20250929",
        thinking_budget = 2048,
        max_tokens = 4000,
      })

      local lines = vim.fn.readfile("tests/fixtures/tool_calling/anthropic_redacted_thinking_streaming.txt")
      local accumulated_content = ""
      local callbacks = {
        on_content = function(content)
          accumulated_content = accumulated_content .. content
        end,
        on_response_complete = function() end,
        on_usage = function() end,
      }

      for _, line in ipairs(lines) do
        provider:process_response_line(line, callbacks)
      end

      -- Should have visible thinking with signature
      assert.is_truthy(
        accumulated_content:match('<thinking anthropic:signature="sig%-visible%-abc123">'),
        "Should emit visible thinking with signature"
      )
      assert.is_truthy(accumulated_content:match("Visible thinking."))

      -- Should have redacted thinking block
      assert.is_truthy(accumulated_content:match("<thinking redacted>"), "Should emit <thinking redacted> tag")
      assert.is_truthy(
        accumulated_content:match("encrypted%-redacted%-data%-xyz789"),
        "Should include redacted data as content"
      )

      -- Should have text response
      assert.is_truthy(accumulated_content:match("Here is my response."))
    end)
  end)

  describe("build_request", function()
    it("should include thinking blocks with signature in content array", function()
      local provider = anthropic.new({
        model = "claude-sonnet-4-5-20250929",
        thinking_budget = 2048,
        max_tokens = 4000,
      })

      local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_with_anthropic_signature.chat")
      local prompt =
        pipeline.run(lines, ctx.from_file("tests/fixtures/tool_calling/conversation_with_anthropic_signature.chat"))
      local req = provider:build_request(prompt, {})

      -- Find the assistant message
      local assistant_msg = nil
      for _, msg in ipairs(req.messages) do
        if msg.role == "assistant" then
          assistant_msg = msg
          break
        end
      end

      assert.is_not_nil(assistant_msg, "Should have assistant message")

      -- Should have thinking block first, then text (structural assertions)
      local has_thinking = false
      local thinking_idx = nil
      local text_idx = nil
      for idx, block in ipairs(assistant_msg.content) do
        if block.type == "thinking" then
          has_thinking = true
          thinking_idx = idx
          assert.is_truthy(block.signature and #block.signature > 0, "Should have non-empty signature")
          assert.is_truthy(block.thinking and #block.thinking > 0, "Should have non-empty thinking content")
        elseif block.type == "text" then
          text_idx = text_idx or idx
        end
      end

      assert.is_true(has_thinking, "Should include thinking block with signature")
      assert.is_true(thinking_idx < text_idx, "Thinking should precede text in content array")
    end)

    it("should include redacted thinking blocks in content array", function()
      local provider = anthropic.new({
        model = "claude-sonnet-4-5-20250929",
        thinking_budget = 2048,
        max_tokens = 4000,
      })

      local lines = vim.fn.readfile("tests/fixtures/tool_calling/conversation_with_redacted_thinking.chat")
      local prompt =
        pipeline.run(lines, ctx.from_file("tests/fixtures/tool_calling/conversation_with_redacted_thinking.chat"))
      local req = provider:build_request(prompt, {})

      -- Find the assistant message
      local assistant_msg = nil
      for _, msg in ipairs(req.messages) do
        if msg.role == "assistant" then
          assistant_msg = msg
          break
        end
      end

      assert.is_not_nil(assistant_msg)

      -- Should have thinking, redacted_thinking, then text
      local has_thinking = false
      local has_redacted = false
      local redacted_idx = nil
      local text_idx = nil
      for idx, block in ipairs(assistant_msg.content) do
        if block.type == "thinking" then
          has_thinking = true
        elseif block.type == "redacted_thinking" then
          has_redacted = true
          redacted_idx = idx
          assert.are.equal("encrypted-redacted-data-xyz789", block.data)
        elseif block.type == "text" then
          text_idx = text_idx or idx
        end
      end

      assert.is_true(has_thinking, "Should include thinking block")
      assert.is_true(has_redacted, "Should include redacted_thinking block")
      assert.is_true(redacted_idx < text_idx, "Redacted thinking should precede text")
    end)

    it("should skip thinking blocks without signature (backward compat)", function()
      local provider = anthropic.new({
        model = "claude-sonnet-4-5-20250929",
        thinking_budget = 2048,
        max_tokens = 4000,
      })

      local prompt = {
        system = "You are helpful.",
        history = {
          { role = "user", parts = { { kind = "text", text = "Hello" } } },
          {
            role = "assistant",
            parts = {
              { kind = "thinking", content = "old thinking without signature" },
              { kind = "text", text = "The answer." },
            },
          },
          { role = "user", parts = { { kind = "text", text = "Follow up" } } },
        },
      }

      local req = provider:build_request(prompt, {})

      -- Find assistant message
      local assistant_msg = nil
      for _, msg in ipairs(req.messages) do
        if msg.role == "assistant" then
          assistant_msg = msg
          break
        end
      end

      assert.is_not_nil(assistant_msg)

      -- Should only have text, no thinking block
      for _, block in ipairs(assistant_msg.content) do
        assert.is_not_equal("thinking", block.type, "Should not include thinking without signature")
      end
    end)
  end)

  describe("reset", function()
    it("should reset thinking accumulation state", function()
      local provider = anthropic.new({
        model = "claude-sonnet-4-5-20250929",
        thinking_budget = 2048,
        max_tokens = 4000,
      })

      -- Manually set some state
      provider._response_buffer.extra.accumulated_thinking = "some thinking"
      provider._response_buffer.extra.accumulated_signature = "some-sig"
      provider._response_buffer.extra.redacted_thinking_blocks = { "data1" }
      provider._response_buffer.extra.current_block_type = "thinking"

      -- Reset
      provider:reset()

      -- State should be cleared
      assert.are.equal("", provider._response_buffer.extra.accumulated_thinking)
      assert.are.equal("", provider._response_buffer.extra.accumulated_signature)
      assert.are.same({}, provider._response_buffer.extra.redacted_thinking_blocks)
      assert.is_nil(provider._response_buffer.extra.current_block_type)
    end)
  end)
end)
