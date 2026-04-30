--- Test file for base provider thinking helpers (is_native_thinking, is_foreign_thinking, wrap_foreign_thinking)
describe("Base Provider Thinking Helpers", function()
  local base = require("flemma.provider.base")

  ---@param overrides? table
  ---@return flemma.provider.Base
  local function make_provider(overrides)
    local provider = {
      metadata = { name = "test_provider" },
      parameters = { thinking = { level = "high", foreign = "preserve" } },
    }
    if overrides then
      for k, v in pairs(overrides) do
        provider[k] = v
      end
    end
    return provider --[[@as flemma.provider.Base]]
  end

  describe("is_native_thinking", function()
    it("returns true for matching signature provider", function()
      local provider = make_provider()
      local segment = {
        kind = "thinking",
        content = "some thinking",
        signature = { provider = "test_provider", value = "sig123" },
      }
      assert.is_true(base.is_native_thinking(provider, segment))
    end)

    it("returns false for foreign signature provider", function()
      local provider = make_provider()
      local segment = {
        kind = "thinking",
        content = "some thinking",
        signature = { provider = "other_provider", value = "sig456" },
      }
      assert.is_false(base.is_native_thinking(provider, segment))
    end)

    it("returns false when no signature", function()
      local provider = make_provider()
      local segment = {
        kind = "thinking",
        content = "some thinking",
      }
      assert.is_false(base.is_native_thinking(provider, segment))
    end)
  end)

  describe("is_foreign_thinking", function()
    it("returns true for foreign signature with content", function()
      local provider = make_provider()
      local segment = {
        kind = "thinking",
        content = "foreign thoughts",
        signature = { provider = "other_provider", value = "sig789" },
      }
      assert.is_true(base.is_foreign_thinking(provider, segment))
    end)

    it("returns true for unsigned thinking with content", function()
      local provider = make_provider()
      local segment = {
        kind = "thinking",
        content = "unsigned thoughts",
      }
      assert.is_true(base.is_foreign_thinking(provider, segment))
    end)

    it("returns false for native thinking", function()
      local provider = make_provider()
      local segment = {
        kind = "thinking",
        content = "my own thinking",
        signature = { provider = "test_provider", value = "sig_native" },
      }
      assert.is_false(base.is_foreign_thinking(provider, segment))
    end)

    it("returns false for redacted thinking", function()
      local provider = make_provider()
      local segment = {
        kind = "thinking",
        content = "redacted data",
        redacted = true,
      }
      assert.is_false(base.is_foreign_thinking(provider, segment))
    end)

    it("returns false for empty content", function()
      local provider = make_provider()
      local segment = {
        kind = "thinking",
        content = "",
        signature = { provider = "other_provider", value = "sig_empty" },
      }
      assert.is_false(base.is_foreign_thinking(provider, segment))
    end)

    it("returns false for whitespace-only content", function()
      local provider = make_provider()
      local segment = {
        kind = "thinking",
        content = "   \n  \t  ",
        signature = { provider = "other_provider", value = "sig_ws" },
      }
      assert.is_false(base.is_foreign_thinking(provider, segment))
    end)
  end)

  describe("wrap_foreign_thinking", function()
    it("returns nil when foreign is drop", function()
      local provider = make_provider({
        parameters = { thinking = { level = "high", foreign = "drop" } },
      })
      local segments = {
        { kind = "thinking", content = "some thoughts" },
      }
      assert.is_nil(base.wrap_foreign_thinking(provider, segments))
    end)

    it("returns nil when thinking is nil", function()
      local provider = make_provider({
        parameters = {},
      })
      local segments = {
        { kind = "thinking", content = "some thoughts" },
      }
      assert.is_nil(base.wrap_foreign_thinking(provider, segments))
    end)

    it("wraps single foreign segment in thinking tags", function()
      local provider = make_provider()
      local segments = {
        { kind = "thinking", content = "foreign reasoning here" },
      }
      local result = base.wrap_foreign_thinking(provider, segments)
      assert.equals("<thinking>\nforeign reasoning here\n</thinking>", result)
    end)

    it("concatenates multiple foreign segments with double newline and trims each", function()
      local provider = make_provider()
      local segments = {
        { kind = "thinking", content = "  first thought  " },
        { kind = "thinking", content = "  second thought  " },
      }
      local result = base.wrap_foreign_thinking(provider, segments)
      assert.equals("<thinking>\nfirst thought\n\nsecond thought\n</thinking>", result)
    end)

    it("returns nil when no foreign segments found", function()
      local provider = make_provider()
      local segments = {
        { kind = "thinking", content = "native", signature = { provider = "test_provider", value = "s1" } },
      }
      assert.is_nil(base.wrap_foreign_thinking(provider, segments))
    end)

    it("skips redacted blocks", function()
      local provider = make_provider()
      local segments = {
        { kind = "thinking", content = "redacted data", redacted = true },
        { kind = "thinking", content = "usable foreign thought" },
      }
      local result = base.wrap_foreign_thinking(provider, segments)
      assert.equals("<thinking>\nusable foreign thought\n</thinking>", result)
    end)

    it("skips non-thinking segments", function()
      local provider = make_provider()
      local segments = {
        { kind = "text", text = "not thinking" },
        { kind = "thinking", content = "actual foreign thought" },
      }
      local result = base.wrap_foreign_thinking(provider, segments)
      assert.equals("<thinking>\nactual foreign thought\n</thinking>", result)
    end)

    it("returns nil when all segments are redacted", function()
      local provider = make_provider()
      local segments = {
        { kind = "thinking", content = "redacted1", redacted = true },
        { kind = "thinking", content = "redacted2", redacted = true },
      }
      assert.is_nil(base.wrap_foreign_thinking(provider, segments))
    end)
  end)
end)
