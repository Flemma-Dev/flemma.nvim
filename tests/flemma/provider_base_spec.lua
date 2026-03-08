--- Tests for base provider emission helpers

package.loaded["flemma.provider.base"] = nil

describe("flemma.provider.base", function()
  local base

  before_each(function()
    package.loaded["flemma.provider.base"] = nil
    base = require("flemma.provider.base")
  end)

  --- Create a base provider with metadata for testing
  ---@return flemma.provider.Base
  local function make_provider()
    local provider = base.new({ model = "test" })
    provider:reset()
    provider.metadata = { name = "test", display_name = "Test" }
    return provider
  end

  describe("_get_content_prefix", function()
    it("returns empty string when no content accumulated", function()
      local provider = make_provider()
      assert.equals("", base._get_content_prefix(provider))
    end)

    it("returns double newline when content does not end with newline", function()
      local provider = make_provider()
      provider._response_buffer.content = "some text"
      assert.equals("\n\n", base._get_content_prefix(provider))
    end)

    it("returns single newline when content ends with newline", function()
      local provider = make_provider()
      provider._response_buffer.content = "some text\n"
      assert.equals("\n", base._get_content_prefix(provider))
    end)
  end)

  describe("_emit_tool_use_block", function()
    it("formats tool use block with dynamic fence sizing", function()
      local provider = make_provider()
      local emitted = nil
      local callbacks = { on_content = function(text) emitted = text end }

      base._emit_tool_use_block(provider, "my_tool", "tool_123", '{"key": "value"}', callbacks)

      assert.is_not_nil(emitted)
      assert.truthy(emitted:match("%*%*Tool Use:%*%* `my_tool` %(`tool_123`%)"))
      assert.truthy(emitted:match("```json"))
      assert.truthy(emitted:match('"key"'))
    end)

    it("uses longer fence when JSON contains backticks", function()
      local provider = make_provider()
      local emitted = nil
      local callbacks = { on_content = function(text) emitted = text end }

      base._emit_tool_use_block(provider, "tool", "id", '{"code": "```lua\\nprint()\\n```"}', callbacks)

      -- Fence should be at least 4 backticks since JSON contains 3
      assert.truthy(emitted:match("````"))
    end)

    it("includes content prefix when content exists", function()
      local provider = make_provider()
      provider._response_buffer.content = "prior text"
      local emitted = nil
      local callbacks = { on_content = function(text) emitted = text end }

      base._emit_tool_use_block(provider, "tool", "id", "{}", callbacks)

      assert.truthy(emitted:match("^\n\n%*%*Tool Use"))
    end)
  end)

  describe("_emit_thinking_block", function()
    it("emits thinking block with content and signature", function()
      local provider = make_provider()
      provider._response_buffer.content = "text\n"
      local emitted = nil
      local callbacks = { on_content = function(text) emitted = text end }

      base._emit_thinking_block(provider, "deep thoughts", "sig123", "anthropic", callbacks)

      assert.truthy(emitted:match('<thinking anthropic:signature="sig123">'))
      assert.truthy(emitted:match("deep thoughts"))
      assert.truthy(emitted:match("</thinking>"))
    end)

    it("emits thinking block without signature", function()
      local provider = make_provider()
      provider._response_buffer.content = "text\n"
      local emitted = nil
      local callbacks = { on_content = function(text) emitted = text end }

      base._emit_thinking_block(provider, "deep thoughts", nil, "vertex", callbacks)

      assert.truthy(emitted:match("<thinking>\n"))
      assert.truthy(emitted:match("deep thoughts"))
    end)

    it("emits empty thinking tag when signature present but no content", function()
      local provider = make_provider()
      provider._response_buffer.content = "text\n"
      local emitted = nil
      local callbacks = { on_content = function(text) emitted = text end }

      base._emit_thinking_block(provider, "", "sig123", "openai", callbacks)

      assert.truthy(emitted:match('<thinking openai:signature="sig123">\n</thinking>'))
    end)

    it("does nothing when no content and no signature", function()
      local provider = make_provider()
      local emitted = nil
      local callbacks = { on_content = function(text) emitted = text end }

      base._emit_thinking_block(provider, "", nil, "anthropic", callbacks)

      assert.is_nil(emitted)
    end)

    it("returns empty prefix when no prior content exists", function()
      local provider = make_provider()
      -- No content set — _get_content_prefix returns ""
      local emitted = nil
      local callbacks = { on_content = function(text) emitted = text end }

      base._emit_thinking_block(provider, "thoughts", "sig", "anthropic", callbacks)

      -- Should start directly with <thinking, no leading newlines
      assert.truthy(emitted:match("^<thinking"))
    end)
  end)

  describe("_emit_redacted_thinking", function()
    it("emits redacted thinking block", function()
      local provider = make_provider()
      provider._response_buffer.content = "text\n"
      local emitted = nil
      local callbacks = { on_content = function(text) emitted = text end }

      base._emit_redacted_thinking(provider, "opaque_data", callbacks)

      assert.truthy(emitted:match("<thinking redacted>"))
      assert.truthy(emitted:match("opaque_data"))
      assert.truthy(emitted:match("</thinking>"))
    end)
  end)

  describe("_warn_truncated", function()
    it("calls on_response_complete", function()
      local provider = make_provider()
      local completed = false
      local callbacks = { on_response_complete = function() completed = true end }

      base._warn_truncated(provider, callbacks)

      assert.is_true(completed)
    end)
  end)

  describe("_signal_blocked", function()
    it("calls on_error with provider name and reason", function()
      local provider = make_provider()
      local error_msg = nil
      local callbacks = { on_error = function(msg) error_msg = msg end }

      base._signal_blocked(provider, "refusal", callbacks)

      assert.truthy(error_msg:match("Response blocked by Test"))
      assert.truthy(error_msg:match("refusal"))
    end)
  end)

  describe("_is_error_response", function()
    it("returns true when data.error is present (default)", function()
      local provider = make_provider()
      assert.is_true(base._is_error_response(provider, { error = { message = "bad" } }))
    end)

    it("returns false when no error field", function()
      local provider = make_provider()
      assert.is_false(base._is_error_response(provider, { type = "content" }))
    end)
  end)

  describe("_inject_orphan_results", function()
    it("returns nil when no pending calls", function()
      local provider = make_provider()
      assert.is_nil(base._inject_orphan_results(provider, nil, function() end))
      assert.is_nil(base._inject_orphan_results(provider, {}, function() end))
    end)

    it("calls format_fn for each orphan and returns results", function()
      local provider = make_provider()
      local pending = {
        { id = "id1", name = "tool_a" },
        { id = "id2", name = "tool_b" },
      }
      local results = base._inject_orphan_results(provider, pending, function(orphan)
        return { id = orphan.id }
      end)
      assert.equals(2, #results)
      assert.equals("id1", results[1].id)
      assert.equals("id2", results[2].id)
    end)
  end)
end)
