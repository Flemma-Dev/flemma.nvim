describe("flemma.ui.bar", function()
  local Bar

  before_each(function()
    package.loaded["flemma.ui.bar"] = nil
    package.loaded["flemma.ui.bar.layout"] = nil
    Bar = require("flemma.ui.bar")
  end)

  describe("Bar.new", function()
    it("returns a pre-dismissed handle when bufnr is invalid", function()
      local bar = Bar.new({ bufnr = 99999, position = "top", segments = {} })
      assert.is_true(bar:is_dismissed())
    end)

    it("returns a handle with core fields populated", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local bar = Bar.new({ bufnr = bufnr, position = "top", segments = {} })
      assert.is_false(bar:is_dismissed())
      assert.equals(bufnr, bar.bufnr)
      assert.equals("top", bar.position)
      bar:dismiss()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("dismiss", function()
    it("is idempotent and fires on_dismiss exactly once", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local calls = 0
      local bar = Bar.new({
        bufnr = bufnr,
        position = "top",
        segments = {},
        on_dismiss = function()
          calls = calls + 1
        end,
      })
      bar:dismiss()
      bar:dismiss()
      assert.equals(1, calls)
      assert.is_true(bar:is_dismissed())
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("dismissed-handle no-op semantics", function()
    it("methods silently no-op after dismiss", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local bar = Bar.new({ bufnr = bufnr, position = "top", segments = {} })
      bar:dismiss()
      -- None of these should error
      bar:set_icon("x")
      bar:set_segments({})
      bar:set_highlight("Normal")
      bar:update({ icon = "y" })
      assert.is_true(bar:is_dismissed())
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("mutual exclusion", function()
    local function make_visible_buf()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "x" })
      vim.api.nvim_set_current_buf(bufnr)
      return bufnr
    end

    it("top dismisses existing top left and top right", function()
      local bufnr = make_visible_buf()
      local tl = Bar.new({ bufnr = bufnr, position = "top left", segments = {} })
      local tr = Bar.new({ bufnr = bufnr, position = "top right", segments = {} })
      local top = Bar.new({ bufnr = bufnr, position = "top", segments = {} })
      assert.is_true(tl:is_dismissed())
      assert.is_true(tr:is_dismissed())
      assert.is_false(top:is_dismissed())
      top:dismiss()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("top and bottom coexist", function()
      local bufnr = make_visible_buf()
      local t = Bar.new({ bufnr = bufnr, position = "top", segments = {} })
      local b = Bar.new({ bufnr = bufnr, position = "bottom", segments = {} })
      assert.is_false(t:is_dismissed())
      assert.is_false(b:is_dismissed())
      t:dismiss()
      b:dismiss()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("left and right corners on same side coexist", function()
      local bufnr = make_visible_buf()
      local tl = Bar.new({ bufnr = bufnr, position = "top left", segments = {} })
      local tr = Bar.new({ bufnr = bufnr, position = "top right", segments = {} })
      assert.is_false(tl:is_dismissed())
      assert.is_false(tr:is_dismissed())
      tl:dismiss()
      tr:dismiss()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("rendering", function()
    local function segments_with(text)
      return {
        {
          key = "seg",
          items = {
            { key = "item", text = text, priority = 1 },
          },
        },
      }
    end

    local function make_visible_buf()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello" })
      vim.api.nvim_set_current_buf(bufnr)
      return bufnr
    end

    it("opens a floating window at 'top' with segments present", function()
      local bufnr = make_visible_buf()
      local bar = Bar.new({ bufnr = bufnr, position = "top", segments = segments_with("abc") })
      assert.is_truthy(bar._float_winid)
      assert.is_true(vim.api.nvim_win_is_valid(bar._float_winid))
      local cfg = vim.api.nvim_win_get_config(bar._float_winid)
      local row = type(cfg.row) == "table" and cfg.row[false] or cfg.row
      assert.equals(0, row)
      bar:dismiss()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("opens at H-1 row for 'bottom left'", function()
      local bufnr = make_visible_buf()
      local winid = vim.fn.bufwinid(bufnr)
      local h = vim.api.nvim_win_get_height(winid)
      local bar = Bar.new({ bufnr = bufnr, position = "bottom left", segments = segments_with("abc") })
      local cfg = vim.api.nvim_win_get_config(bar._float_winid)
      local row = type(cfg.row) == "table" and cfg.row[false] or cfg.row
      assert.equals(h - 1, row)
      bar:dismiss()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("does not open floats when buffer is invisible", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local bar = Bar.new({ bufnr = bufnr, position = "top", segments = segments_with("abc") })
      assert.is_false(bar:is_dismissed())
      assert.is_nil(bar._float_winid)
      bar:dismiss()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("opens a gutter-icon float when gutter is wide enough and icon is set", function()
      local bufnr = make_visible_buf()
      local winid = vim.fn.bufwinid(bufnr)
      vim.wo[winid].number = true
      vim.wo[winid].numberwidth = 4
      local bar = Bar.new({
        bufnr = bufnr,
        position = "top left",
        segments = segments_with("abc"),
        icon = "ℹ ",
      })
      assert.is_truthy(bar._gutter_winid)
      assert.is_true(vim.api.nvim_win_is_valid(bar._gutter_winid))
      bar:dismiss()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("reuses the same float winid across re-renders", function()
      local bufnr = make_visible_buf()
      local bar = Bar.new({ bufnr = bufnr, position = "top", segments = segments_with("abc") })
      local winid1 = bar._float_winid
      bar:set_segments(segments_with("def"))
      assert.equals(winid1, bar._float_winid)
      assert.is_true(vim.api.nvim_win_is_valid(winid1))
      bar:dismiss()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    -- Regression guard. layout.render right-pads to available_width; without
    -- trimming, Bar measured the padded width and every corner-position bar
    -- stretched to cover the whole window. Corner positions must hug the
    -- natural content width.
    it("sizes 'bottom left' float to content, not full window", function()
      local bufnr = make_visible_buf()
      local winid = vim.fn.bufwinid(bufnr)
      local W = vim.api.nvim_win_get_width(winid)
      local bar = Bar.new({ bufnr = bufnr, position = "bottom left", segments = segments_with("hi") })
      local cfg = vim.api.nvim_win_get_config(bar._float_winid)
      assert.is_true(
        cfg.width < W,
        "bottom-left float width (" .. cfg.width .. ") should be less than window width (" .. W .. ")"
      )
      assert.is_true(
        cfg.width < 20,
        "bottom-left float width (" .. cfg.width .. ") should hug the 2-char content 'hi', not the pad"
      )
      bar:dismiss()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("sizes 'top' (full-width) float to the whole window", function()
      local bufnr = make_visible_buf()
      local winid = vim.fn.bufwinid(bufnr)
      local W = vim.api.nvim_win_get_width(winid)
      local bar = Bar.new({ bufnr = bufnr, position = "top", segments = segments_with("hi") })
      local cfg = vim.api.nvim_win_get_config(bar._float_winid)
      assert.equals(W, cfg.width, "top (full-width) bar should span the whole window")
      bar:dismiss()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    -- Narrow-gutter inline-icon ordering. The pre-refactor narrow-gutter
    -- branch rendered `<G spaces> + <spinner> + " " + <body>`, so the spinner
    -- glyph landed at col G — right at the gutter / buffer-text boundary.
    -- The post-refactor _render initially prepended the icon AFTER the G_pad,
    -- placing it at col 0 instead. Visible regression for users with
    -- line numbers narrow enough (G in 1..icon_width) to fall through to the
    -- narrow-gutter fallback.
    it("places inline icon at col G, not col 0, when narrow gutter forces fallback", function()
      local bufnr = make_visible_buf()
      local winid = vim.fn.bufwinid(bufnr)
      vim.wo[winid].signcolumn = "no"
      vim.wo[winid].foldcolumn = "0"
      vim.wo[winid].relativenumber = false
      vim.wo[winid].number = true
      vim.wo[winid].numberwidth = 2
      vim.cmd("redraw")

      local G = require("flemma.utilities.buffer").get_gutter_width(winid)
      -- numberwidth=2 with single-digit line numbers should give G=2.
      -- If the environment ends up with a wider gutter (e.g. signcolumn
      -- forced on by other tests' state), the icon would route through the
      -- gutter-float branch and bypass the inline-prepend code path this
      -- test is meant to guard. Skip in that case rather than asserting
      -- on a different code path.
      if G < 1 or G > 2 then
        bufnr = bufnr -- noop, just keep the buffer for cleanup
      else
        local bar = Bar.new({
          bufnr = bufnr,
          position = "bottom left",
          segments = segments_with("body"),
          icon = "X", -- normalize_icon → "X " (2 display cols)
        })
        local text = vim.api.nvim_buf_get_lines(bar._float_bufnr, 0, -1, false)[1] or ""
        local expected_prefix = string.rep(" ", G) .. "X "
        assert.equals(
          expected_prefix,
          text:sub(1, #expected_prefix),
          ("G=%d expected text to start with %q (G_pad + icon); got %q"):format(G, expected_prefix, text)
        )
        bar:dismiss()
      end
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    -- Right-anchored breathing-room mirror. Left-anchored bars get one
    -- column of trailing FlemmaProgressBar bg between content and any buffer
    -- text continuing to their right (the +1 in the width formula). Right-
    -- anchored bars are flush against the window's right border, so the
    -- equivalent breathing room must instead sit on the LEFT — between the
    -- icon/content and any buffer text continuing to the float's left side.
    it("right-anchored floats start with a leading space (mirror breathing)", function()
      for _, position in ipairs({ "top right", "bottom right" }) do
        local bufnr = make_visible_buf()
        local bar = Bar.new({
          bufnr = bufnr,
          position = position,
          segments = segments_with("hello"),
          icon = "⣯",
        })
        local text = vim.api.nvim_buf_get_lines(bar._float_bufnr, 0, -1, false)[1] or ""
        assert.equals(
          " ",
          text:sub(1, 1),
          ("position=%q: right-anchored float should start with a leading space; got %q"):format(position, text)
        )
        bar:dismiss()
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    -- Parametric no-clipping invariant. Caught a real bug: narrow-gutter
    -- corner positions sized the float to T+G+1 (omitting icon_width), so a
    -- 2-col inline icon prefix clipped the trailing character of the body.
    -- For every position × gutter × icon combination, every visible glyph in
    -- the displayed line must fit inside the float's width.
    --
    -- Explicit gutter control matters: prior tests in this file set
    -- vim.wo[winid].number = true and the window state leaks into later
    -- tests. Without an explicit gutter reset, this assertion silently
    -- exercises only the wide-gutter branch and misses the narrow-gutter
    -- bug it is meant to guard against.
    it("never clips the displayed line across positions, gutters, and icons", function()
      local positions = {
        "top",
        "bottom",
        "top left",
        "top right",
        "bottom left",
        "bottom right",
      }
      local gutter_widths = { 0, 4 }
      local icons = { false, "⣯" } -- two-column inline icon when set
      for _, position in ipairs(positions) do
        for _, gutter in ipairs(gutter_widths) do
          for _, icon in ipairs(icons) do
            local bufnr = make_visible_buf()
            local winid = vim.fn.bufwinid(bufnr)
            -- Reset window state so the previous test's `number = true`
            -- can't leak in and mask the narrow-gutter code path.
            vim.wo[winid].number = false
            vim.wo[winid].relativenumber = false
            vim.wo[winid].signcolumn = "no"
            vim.wo[winid].foldcolumn = "0"
            if gutter > 0 then
              vim.wo[winid].number = true
              vim.wo[winid].numberwidth = gutter
            end
            vim.cmd("redraw")

            local opts = {
              bufnr = bufnr,
              position = position,
              segments = segments_with("100 characters · 1s"),
            }
            if icon then
              opts.icon = icon
            end
            local bar = Bar.new(opts)
            local cfg = vim.api.nvim_win_get_config(bar._float_winid)
            local text = vim.api.nvim_buf_get_lines(bar._float_bufnr, 0, -1, false)[1] or ""
            local text_width = vim.api.nvim_strwidth(text)
            assert.is_true(
              cfg.width >= text_width,
              ("position=%q gutter=%d icon=%q: float width (%d) clips text width (%d): %q"):format(
                position,
                gutter,
                tostring(icon),
                cfg.width,
                text_width,
                text
              )
            )
            bar:dismiss()
            vim.api.nvim_buf_delete(bufnr, { force = true })
          end
        end
      end
    end)
  end)

  describe("on_shown firing rule", function()
    it("fires exactly once on first render of a visible buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "x" })
      vim.api.nvim_set_current_buf(bufnr)
      local count = 0
      local bar = Bar.new({
        bufnr = bufnr,
        position = "top",
        segments = { { key = "s", items = { { key = "i", text = "x", priority = 1 } } } },
        on_shown = function()
          count = count + 1
        end,
      })
      assert.equals(1, count)
      bar:set_segments({ { key = "s", items = { { key = "i", text = "y", priority = 1 } } } })
      assert.equals(1, count)
      bar:dismiss()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    -- Replaces the deleted notifications.lua test "should defer notification
    -- until buffer becomes visible". A Bar created on a hidden buffer must
    -- (a) keep on_shown silent, (b) fire on_shown exactly once when the
    -- buffer becomes visible via BufWinEnter / WinEnter. usage.show wires
    -- the auto-dismiss timer to on_shown, so any regression here would let
    -- the timer start on a still-invisible bar.
    it("fires once when a hidden-at-construction buffer becomes visible", function()
      local hidden_bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(hidden_bufnr, 0, -1, false, { "hidden" })
      -- Construct Bar BEFORE making the buffer current so the buffer is
      -- truly hidden at first render.
      local count = 0
      local bar = Bar.new({
        bufnr = hidden_bufnr,
        position = "top",
        segments = { { key = "s", items = { { key = "i", text = "x", priority = 1 } } } },
        on_shown = function()
          count = count + 1
        end,
      })
      assert.equals(0, count, "on_shown should not have fired while buffer is hidden")
      assert.is_nil(bar._float_winid, "no float should be open while buffer is hidden")

      -- Make the buffer visible — Bar's BufWinEnter autocmd should fire
      -- _render(), which finally opens the float and triggers on_shown.
      vim.api.nvim_set_current_buf(hidden_bufnr)
      vim.wait(50, function()
        return count > 0
      end)
      assert.equals(1, count, "on_shown should fire exactly once on first visible render")
      assert.is_truthy(bar._float_winid, "float should be open after buffer becomes visible")

      bar:dismiss()
      vim.api.nvim_buf_delete(hidden_bufnr, { force = true })
    end)

    it("does not fire when bar is dismissed before becoming visible", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local count = 0
      local bar = Bar.new({
        bufnr = bufnr,
        position = "top",
        segments = {},
        on_shown = function()
          count = count + 1
        end,
      })
      assert.equals(0, count)
      bar:dismiss()
      assert.equals(0, count)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("lifecycle autocmds", function()
    local function open_visible_bufnr()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello" })
      vim.api.nvim_set_current_buf(bufnr)
      return bufnr
    end

    it("BufWipeout auto-dismisses", function()
      local bufnr = open_visible_bufnr()
      local bar = Bar.new({
        bufnr = bufnr,
        position = "top",
        segments = { { key = "s", items = { { key = "i", text = "x", priority = 1 } } } },
      })
      vim.api.nvim_buf_delete(bufnr, { force = true })
      assert.is_true(bar:is_dismissed())
    end)

    it("re-renders on WinResized", function()
      local bufnr = open_visible_bufnr()
      local bar = Bar.new({
        bufnr = bufnr,
        position = "top",
        segments = { { key = "s", items = { { key = "i", text = "x", priority = 1 } } } },
      })
      local winid1 = bar._float_winid
      vim.api.nvim_exec_autocmds("VimResized", {})
      assert.equals(winid1, bar._float_winid)
      assert.is_true(vim.api.nvim_win_is_valid(winid1))
      bar:dismiss()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
