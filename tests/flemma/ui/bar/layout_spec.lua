describe("flemma.ui.bar.layout", function()
  local layout

  before_each(function()
    package.loaded["flemma.ui.bar.layout"] = nil
    layout = require("flemma.ui.bar.layout")
  end)

  describe("measure_item_widths", function()
    it("should return correct display widths for all items", function()
      local segments = {
        {
          key = "identity",
          items = {
            { key = "model_name", text = "gpt-4o", priority = 90 },
            { key = "provider_name", text = "(openai)", priority = 70 },
          },
        },
        {
          key = "request",
          items = {
            { key = "input_tokens", text = "1,611\xE2\x86\x91", priority = 50 },
            { key = "output_tokens", text = "200\xE2\x86\x93", priority = 50 },
          },
        },
      }

      local widths = layout.measure_item_widths(segments)

      assert.are.equal(6, widths.model_name) -- "gpt-4o"
      assert.are.equal(8, widths.provider_name) -- "(openai)"
      assert.are.equal(6, widths.input_tokens) -- "1,611↑"
      assert.are.equal(4, widths.output_tokens) -- "200↓"
    end)
  end)

  describe("render", function()
    it("should render a single segment with all items", function()
      local segments = {
        {
          key = "identity",
          items = {
            { key = "model_name", text = "gpt-4o", priority = 90 },
            { key = "provider_name", text = "(openai)", priority = 70 },
          },
        },
      }

      local result = layout.render(segments, 120)

      assert.is_not_nil(result)
      assert.has_match("gpt%-4o  %(openai%)", result.text)
    end)

    it("should render multiple segments with separators", function()
      local segments = {
        {
          key = "identity",
          items = {
            { key = "model_name", text = "gpt-4o", priority = 90 },
            { key = "provider_name", text = "(openai)", priority = 70 },
          },
        },
        {
          key = "request",
          items = {
            { key = "request_cost", text = "$0.01", priority = 80 },
            { key = "cache_percent", text = "Cache 75%", priority = 75 },
          },
        },
      }

      local result = layout.render(segments, 120)

      -- Should contain separator between segments
      assert.has_match("gpt%-4o  %(openai%)  \xE2\x94\x82  %$0%.01  Cache 75%%", result.text)
    end)

    it("should drop lowest-priority items when width is scarce", function()
      local segments = {
        {
          key = "identity",
          items = {
            { key = "model_name", text = "gpt-4o", priority = 90 },
            { key = "provider_name", text = "(openai)", priority = 70 },
          },
        },
        {
          key = "request",
          items = {
            { key = "request_cost", text = "$0.01", priority = 80 },
          },
        },
      }

      -- Width too small for all items: prefix (3) + model (6) + sep (3) + cost (5) + space (1) + provider (8) = 26
      -- Drop provider (priority 70) first
      local result = layout.render(segments, 19)

      assert.has_match("gpt%-4o", result.text)
      assert.has_match("%$0%.01", result.text)
      assert.has_no_match("openai", result.text)
    end)

    it("should treat equal-priority items as a group", function()
      local segments = {
        {
          key = "identity",
          items = {
            { key = "model_name", text = "gpt-4o", priority = 90 },
          },
        },
        {
          key = "request",
          items = {
            { key = "request_input_tokens", text = "1,610\xE2\x86\x91", priority = 50 },
            { key = "request_output_tokens", text = "600\xE2\x86\x93", priority = 50 },
          },
        },
      }

      -- Width enough for model + both tokens
      local wide_result = layout.render(segments, 120)
      assert.has_match("1,610\xE2\x86\x91", wide_result.text)
      assert.has_match("600\xE2\x86\x93", wide_result.text)

      -- Width too small for both tokens — both should be dropped together
      -- prefix (2) + model (6) = 8, tokens would add sep (3) + 6 + 1 + 4 = 22 total
      local narrow_result = layout.render(segments, 15)
      assert.has_no_match("\xE2\x86\x91", narrow_result.text)
      assert.has_no_match("\xE2\x86\x93", narrow_result.text)
    end)

    it("should remove segment and separator when all items hidden", function()
      local segments = {
        {
          key = "identity",
          items = {
            { key = "model_name", text = "gpt-4o", priority = 90 },
          },
        },
        {
          key = "session",
          label = "Session",
          items = {
            { key = "session_input_tokens", text = "4,374\xE2\x86\x91", priority = 20 },
            { key = "session_output_tokens", text = "603\xE2\x86\x93", priority = 20 },
          },
        },
      }

      -- Width only fits prefix + model — session items should be dropped along with separator
      -- prefix (3) + model (6) = 9
      local result = layout.render(segments, 13)

      assert.has_match("gpt%-4o", result.text)
      assert.has_no_match("\xE2\x94\x82", result.text) -- no separator
      assert.has_no_match("Session", result.text) -- no label
    end)

    it("should show segment label when segment has visible items", function()
      local segments = {
        {
          key = "identity",
          items = {
            { key = "model_name", text = "gpt-4o", priority = 90 },
          },
        },
        {
          key = "session",
          label = "Session",
          items = {
            { key = "session_cost", text = "$0.05", priority = 60 },
          },
        },
      }

      local result = layout.render(segments, 120)

      assert.has_match("Session  %$0%.05", result.text)
    end)

    it("should track highlight positions in rendered line", function()
      local segments = {
        {
          key = "identity",
          items = {
            { key = "model_name", text = "gpt-4o", priority = 90 },
          },
        },
        {
          key = "request",
          items = {
            {
              key = "cache_percent",
              text = "Cache 75%",
              priority = 75,
              highlight = {
                group = "FlemmaNotificationsCacheGood",
                offset = 6, -- byte offset of "75%" within "Cache 75%"
                length = 3, -- byte length of "75%"
              },
            },
          },
        },
      }

      local result = layout.render(segments, 120)

      assert.are.equal(1, #result.highlights)
      assert.are.equal("FlemmaNotificationsCacheGood", result.highlights[1].group)
      -- The highlight should point to "75%" in the rendered line
      local highlighted_text = result.text:sub(result.highlights[1].col_start + 1, result.highlights[1].col_end)
      assert.are.equal("75%", highlighted_text)
    end)

    it("should right-pad text with spaces to fill available width", function()
      local segments = {
        {
          key = "identity",
          items = {
            { key = "model_name", text = "gpt-4o", priority = 90 },
          },
        },
      }

      local result = layout.render(segments, 20)

      -- Text should be padded to exactly 20 display chars
      assert.are.equal(20, vim.fn.strdisplaywidth(result.text))
    end)

    it("should handle empty segments gracefully", function()
      local result = layout.render({}, 120)

      assert.are.equal(120, vim.fn.strdisplaywidth(result.text))
      assert.are.equal(0, #result.highlights)
    end)

    it("should pad items to minimum widths when item_widths provided", function()
      local segments = {
        {
          key = "request",
          items = {
            { key = "input_tokens", text = "1,611\xE2\x86\x91", priority = 50 },
            { key = "output_tokens", text = "200\xE2\x86\x93", priority = 50 },
          },
        },
      }

      -- Render with item_widths that are wider than natural text
      -- "1,611↑" is 6 display chars, "200↓" is 4 display chars
      -- Set minimum widths to 9 for input and 7 for output
      local result = layout.render(segments, 120, { input_tokens = 9, output_tokens = 7 })

      -- The rendered text should contain the original text plus padding spaces
      -- Total: 9 + 1 (space) + 7 = 17 display chars of content
      -- Verify the display width accounts for padding
      assert.has_match("1,611\xE2\x86\x91", result.text)
      assert.has_match("200\xE2\x86\x93", result.text)

      -- Without item_widths, content would be 6 + 1 + 4 = 11 display chars
      local unpadded = layout.render(segments, 120)
      -- Padded version should be wider in content area
      -- Both are right-padded to 120, but the content portion differs
      local padded_content = result.text:match("^(.-)%s*$")
      local unpadded_content = unpadded.text:match("^(.-)%s*$")
      assert.is_true(vim.fn.strdisplaywidth(padded_content) > vim.fn.strdisplaywidth(unpadded_content))
    end)

    it("should produce correct highlight offsets with padded preceding items", function()
      local segments = {
        {
          key = "request",
          items = {
            { key = "input_tokens", text = "1,611\xE2\x86\x91", priority = 50 },
            {
              key = "cache_percent",
              text = "Cache 75%",
              priority = 75,
              highlight = {
                group = "FlemmaNotificationsCacheGood",
                offset = 6,
                length = 3,
              },
            },
          },
        },
      }

      -- Pad input_tokens to 12 display chars (natural is 6)
      local result = layout.render(segments, 120, { input_tokens = 12 })

      assert.are.equal(1, #result.highlights)
      assert.are.equal("FlemmaNotificationsCacheGood", result.highlights[1].group)
      -- The highlight should still point to "75%" in the rendered line
      local highlighted_text = result.text:sub(result.highlights[1].col_start + 1, result.highlights[1].col_end)
      assert.are.equal("75%", highlighted_text)
    end)

    it("should drop items when padding causes overflow", function()
      local segments = {
        {
          key = "identity",
          items = {
            { key = "model_name", text = "gpt-4o", priority = 90 },
          },
        },
        {
          key = "request",
          items = {
            { key = "input_tokens", text = "100\xE2\x86\x91", priority = 50 },
          },
        },
      }

      -- Without padding: prefix(2) + gpt-4o(6) + sep(3) + 100↑(4) = 15 — fits in 19
      local fits = layout.render(segments, 19)
      assert.has_match("100\xE2\x86\x91", fits.text)

      -- With padding to 10: prefix(2) + gpt-4o(6) + sep(3) + padded(10) = 21 — exceeds 19
      local overflows = layout.render(segments, 19, { input_tokens = 10 })
      assert.has_no_match("\xE2\x86\x91", overflows.text)
      assert.has_match("gpt%-4o", overflows.text)
    end)

    it("should align separators across two segment sets with merged widths", function()
      -- Simulate two notifications with different token widths
      local segments_a = {
        {
          key = "identity",
          items = {
            { key = "model_name", text = "gpt-4o", priority = 90 },
          },
        },
        {
          key = "request",
          items = {
            { key = "input_tokens", text = "1,611\xE2\x86\x91", priority = 50 },
            { key = "output_tokens", text = "200\xE2\x86\x93", priority = 50 },
          },
        },
      }

      local segments_b = {
        {
          key = "identity",
          items = {
            { key = "model_name", text = "gpt-4o", priority = 90 },
          },
        },
        {
          key = "request",
          items = {
            { key = "input_tokens", text = "2,618\xE2\x86\x91", priority = 50 },
            { key = "output_tokens", text = "1,400\xE2\x86\x93", priority = 50 },
          },
        },
      }

      -- Compute merged widths (max per key)
      local widths_a = layout.measure_item_widths(segments_a)
      local widths_b = layout.measure_item_widths(segments_b)

      local merged = {}
      for key, w in pairs(widths_a) do
        merged[key] = w
      end
      for key, w in pairs(widths_b) do
        merged[key] = math.max(merged[key] or 0, w)
      end

      local result_a = layout.render(segments_a, 120, merged)
      local result_b = layout.render(segments_b, 120, merged)

      -- Find the separator "│" byte position in each rendered line
      local sep_pos_a = result_a.text:find("\xE2\x94\x82")
      local sep_pos_b = result_b.text:find("\xE2\x94\x82")
      assert.is_not_nil(sep_pos_a)
      assert.is_not_nil(sep_pos_b)
      assert.are.equal(sep_pos_a, sep_pos_b)
    end)

    it("should keep high-priority items from low-priority segments", function()
      local segments = {
        {
          key = "identity",
          items = {
            { key = "model_name", text = "gpt-4o", priority = 90 },
          },
        },
        {
          key = "request",
          items = {
            { key = "request_cost", text = "$0.01", priority = 80 },
            { key = "thinking_tokens", text = "25\xE2\x81\x82 thinking", priority = 35 },
          },
        },
        {
          key = "session",
          label = "Session",
          items = {
            { key = "session_cost", text = "$0.05", priority = 60 },
          },
        },
      }

      -- Width enough for model + request cost + session cost, but not thinking
      -- prefix(3) + gpt-4o(6) + sep(3) + $0.01(5) + sep(3) + Session(7) + space(1) + $0.05(5) = 33
      local result = layout.render(segments, 35)

      assert.has_match("gpt%-4o", result.text)
      assert.has_match("%$0%.01", result.text)
      assert.has_match("Session %$0%.05", result.text)
      assert.has_no_match("thinking", result.text)
    end)

    it("should omit emoji prefix when skip_prefix is true", function()
      local segments = {
        {
          key = "identity",
          items = {
            { key = "model_name", text = "gpt-4o", priority = 90 },
          },
        },
      }

      local with_prefix = layout.render(segments, 120)
      local without_prefix = layout.render(segments, 120, nil, { skip_prefix = true })

      -- With prefix: starts with ℹ character
      assert.has_match("^\xE2\x84\xB9", with_prefix.text)
      -- Without prefix: starts directly with content
      assert.has_match("^gpt%-4o", without_prefix.text)
    end)

    it("should fit more items when prefix is skipped (2 columns reclaimed)", function()
      local segments = {
        {
          key = "identity",
          items = {
            { key = "model_name", text = "gpt-4o", priority = 90 },
          },
        },
        {
          key = "request",
          items = {
            { key = "request_cost", text = "$0.01", priority = 80 },
          },
        },
      }

      -- Width that fits model + cost only without prefix:
      -- gpt-4o(6) + sep(3) + $0.01(5) = 14
      -- With prefix that would need 14 + 2 = 16 — won't fit in 15
      local with_prefix = layout.render(segments, 15)
      assert.has_no_match("%$0%.01", with_prefix.text)

      -- Same width but skip_prefix — now 14 fits in 15
      local without_prefix = layout.render(segments, 15, nil, { skip_prefix = true })
      assert.has_match("%$0%.01", without_prefix.text)
    end)

    it("should produce correct highlight offsets when prefix is skipped", function()
      local segments = {
        {
          key = "identity",
          items = {
            { key = "model_name", text = "gpt-4o", priority = 90 },
          },
        },
        {
          key = "request",
          items = {
            {
              key = "cache_percent",
              text = "Cache 75%",
              priority = 75,
              highlight = {
                group = "FlemmaNotificationsCacheGood",
                offset = 6,
                length = 3,
              },
            },
          },
        },
      }

      local result = layout.render(segments, 120, nil, { skip_prefix = true })

      assert.are.equal(1, #result.highlights)
      assert.are.equal("FlemmaNotificationsCacheGood", result.highlights[1].group)
      -- Highlight should still point to "75%" — byte offset starts at 0 (no prefix)
      local highlighted_text = result.text:sub(result.highlights[1].col_start + 1, result.highlights[1].col_end)
      assert.are.equal("75%", highlighted_text)
    end)
  end)

  describe("relaxed spacing", function()
    it("should use double spacing when width allows", function()
      local segments = {
        {
          key = "identity",
          items = {
            { key = "model_name", text = "gpt-4o", priority = 90 },
            { key = "provider_name", text = "(openai)", priority = 10 },
          },
        },
        {
          key = "request",
          items = {
            { key = "request_cost", text = "$0.01", priority = 80 },
          },
        },
      }

      local result = layout.render(segments, 120)

      -- Wide width: relaxed spacing with double spaces and wide separator
      assert.has_match("gpt%-4o  %(openai%)  \xE2\x94\x82  %$0%.01", result.text)
    end)

    it("should fall back to normal spacing when width is tight", function()
      local segments = {
        {
          key = "identity",
          items = {
            { key = "model_name", text = "gpt-4o", priority = 90 },
          },
        },
        {
          key = "request",
          items = {
            { key = "request_cost", text = "$0.01", priority = 80 },
          },
        },
      }

      -- Normal: prefix(2) + gpt-4o(6) + sep(3) + $0.01(5) = 16
      -- Relaxed: prefix(2) + gpt-4o(6) + sep(5) + $0.01(5) = 18
      -- Width 17: fits normal but not relaxed
      local result = layout.render(segments, 17)

      assert.has_match("gpt%-4o", result.text)
      assert.has_match("%$0%.01", result.text)
      -- Should use normal separator (3 display chars), not relaxed (5)
      assert.has_match(" \xE2\x94\x82 ", result.text)
      assert.has_no_match("  \xE2\x94\x82  ", result.text)
    end)
  end)

  describe("exported constants", function()
    it("should expose PREFIX and PREFIX_DISPLAY_WIDTH", function()
      assert.is_not_nil(layout.PREFIX)
      assert.is_not_nil(layout.PREFIX_DISPLAY_WIDTH)
      assert.are.equal("string", type(layout.PREFIX))
      assert.are.equal("number", type(layout.PREFIX_DISPLAY_WIDTH))
      assert.are.equal(2, layout.PREFIX_DISPLAY_WIDTH)
    end)
  end)

  describe("apply_rendered_highlights", function()
    it("clears the namespace and sets one extmark per highlight", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello world" })
      local ns = vim.api.nvim_create_namespace("test_layout_hl")

      layout.apply_rendered_highlights(bufnr, ns, {
        { group = "Error", col_start = 0, col_end = 5 },
        { group = "Comment", col_start = 6, col_end = 11 },
      })

      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
      assert.equals(2, #marks)
      assert.equals("Error", marks[1][4].hl_group)
      assert.equals("Comment", marks[2][4].hl_group)

      -- Second call clears prior marks
      layout.apply_rendered_highlights(bufnr, ns, {
        { group = "Search", col_start = 0, col_end = 11 },
      })
      marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
      assert.equals(1, #marks)
      assert.equals("Search", marks[1][4].hl_group)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
