local busted = require("plenary.busted")
local ui = require("flemma.ui")

-- Test helpers
local function with_chat_buf(lines, fn)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].filetype = "chat"
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or { "@System:", "", "@You: Hello", "", "@Assistant: Reply" })
  local win = vim.api.nvim_get_current_win()
  local ok, err = pcall(fn, bufnr, win)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
  if not ok then
    error(err)
  end
end

local function wait_until(cond, timeout)
  timeout = timeout or 400
  local ok = vim.wait(timeout, function()
    return cond()
  end, 10)
  return ok
end

local function set_scrolloff(win, val)
  vim.api.nvim_set_option_value("scrolloff", val, { win = win })
end

local function set_height(win, h)
  pcall(vim.api.nvim_win_set_height, win, h)
end

local function goto_bottom(bufnr, win)
  vim.api.nvim_win_set_buf(win, bufnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_win_set_cursor(win, { line_count, 0 })
  vim.api.nvim_win_call(win, function()
    vim.cmd("normal! zb")
  end)
end

local function goto_line(win, lnum)
  vim.api.nvim_win_set_cursor(win, { lnum, 0 })
end

local function cursor_line(win)
  return vim.api.nvim_win_get_cursor(win)[1]
end

local function top_line(win)
  return vim.fn.line("w0", win)
end

local function bottom_line(win)
  return vim.fn.line("w$", win)
end

local function visible(win, lnum)
  return lnum >= top_line(win) and lnum <= bottom_line(win)
end

local function add_you_prompt(bufnr)
  local last = vim.api.nvim_buf_line_count(bufnr)
  local last_line = ""
  if last > 0 then
    last_line = (vim.api.nvim_buf_get_lines(bufnr, last - 1, last, false)[1] or "")
  end
  local to_insert = last_line == "" and { "@You: " } or { "", "@You: " }
  vim.api.nvim_buf_set_lines(bufnr, last, last, false, to_insert)
  return last + (#to_insert == 1 and 1 or 2)
end

local function capture_state(bufnr, opts)
  return ui.capture_viewport_state(bufnr, opts or {})
end

describe("Smart scrolling & cursor positioning", function()
  before_each(function()
    vim.o.foldenable = false
  end)

  it("User at bottom when sending -> cursor moves to @You", function()
    with_chat_buf(
      vim.tbl_map(function(i)
        return "line " .. i
      end, vim.fn.range(1, 30)),
      function(bufnr, win)
        set_scrolloff(win, 0)
        set_height(win, 12)
        goto_bottom(bufnr, win)

        local viewport_state = capture_state(bufnr, { will_restore_insert = false })

        local you_lnum = add_you_prompt(bufnr)
        ui.scroll_to_reveal_you_prompt(bufnr, you_lnum, viewport_state)

        assert.is_true(wait_until(function()
          return cursor_line(win) == you_lnum
        end))
        assert.is_true(visible(win, you_lnum))
      end
    )
  end)

  it("User not at bottom when sending -> cursor does NOT move", function()
    with_chat_buf(
      vim.tbl_map(function(i)
        return "line " .. i
      end, vim.fn.range(1, 40)),
      function(bufnr, win)
        set_scrolloff(win, 3)
        set_height(win, 15)
        goto_line(win, 5)
        local orig_cursor = cursor_line(win)
        local orig_top = top_line(win)

        local viewport_state = capture_state(bufnr, { will_restore_insert = false })
        assert.is_false(viewport_state.was_at_bottom)

        local you_lnum = add_you_prompt(bufnr)
        ui.scroll_to_reveal_you_prompt(bufnr, you_lnum, viewport_state)

        vim.wait(200)
        assert.equal(orig_cursor, cursor_line(win))
        assert.equal(orig_top, top_line(win))
        assert.is_false(visible(win, you_lnum))
      end
    )
  end)

  it("User at bottom but navigates away during request -> does NOT move", function()
    with_chat_buf(
      vim.tbl_map(function(i)
        return "line " .. i
      end, vim.fn.range(1, 35)),
      function(bufnr, win)
        set_scrolloff(win, 0)
        goto_bottom(bufnr, win)
        local viewport_state = capture_state(bufnr, { will_restore_insert = false })

        goto_line(win, 10)
        local orig_cursor = cursor_line(win)
        local orig_top = top_line(win)

        local you_lnum = add_you_prompt(bufnr)
        ui.scroll_to_reveal_you_prompt(bufnr, you_lnum, viewport_state)

        vim.wait(200)
        assert.equal(orig_cursor, cursor_line(win))
        assert.equal(orig_top, top_line(win))
        assert.is_false(visible(win, you_lnum))
      end
    )
  end)

  it("User in insert mode (will restore) -> ALWAYS moves even if not at bottom", function()
    with_chat_buf(
      vim.tbl_map(function(i)
        return "line " .. i
      end, vim.fn.range(1, 25)),
      function(bufnr, win)
        set_scrolloff(win, 2)
        goto_line(win, 5)

        local viewport_state = capture_state(bufnr, { will_restore_insert = true })

        local you_lnum = add_you_prompt(bufnr)
        ui.scroll_to_reveal_you_prompt(bufnr, you_lnum, viewport_state)

        assert.is_true(wait_until(function()
          return cursor_line(win) == you_lnum
        end))
        assert.is_true(visible(win, you_lnum))
      end
    )
  end)

  it("User scrolls up during assistant response -> does NOT hijack", function()
    with_chat_buf(
      vim.tbl_map(function(i)
        return "line " .. i
      end, vim.fn.range(1, 45)),
      function(bufnr, win)
        set_scrolloff(win, 1)
        goto_bottom(bufnr, win)
        local viewport_state = capture_state(bufnr, { will_restore_insert = false })

        goto_line(win, 8)
        local orig_cursor = cursor_line(win)
        local orig_top = top_line(win)

        local you_lnum = add_you_prompt(bufnr)
        ui.scroll_to_reveal_you_prompt(bufnr, you_lnum, viewport_state)

        vim.wait(200)
        assert.equal(orig_cursor, cursor_line(win))
        assert.equal(orig_top, top_line(win))
        assert.is_false(visible(win, you_lnum))
      end
    )
  end)

  it("Assistant Thinking added while at bottom -> reveals the line", function()
    with_chat_buf(
      vim.tbl_map(function(i)
        return "line " .. i
      end, vim.fn.range(1, 25)),
      function(bufnr, win)
        set_scrolloff(win, 0)
        set_height(win, 10)
        goto_bottom(bufnr, win)

        local viewport_state = capture_state(bufnr, { will_restore_insert = false })
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "@Assistant: Thinking..." })
        local thinking_lnum = vim.api.nvim_buf_line_count(bufnr)

        ui.reveal_thinking(bufnr, thinking_lnum, viewport_state)

        assert.is_true(visible(win, thinking_lnum))
      end
    )
  end)

  it("Assistant Thinking added while not at bottom -> ALWAYS reveals", function()
    with_chat_buf(
      vim.tbl_map(function(i)
        return "line " .. i
      end, vim.fn.range(1, 30)),
      function(bufnr, win)
        set_scrolloff(win, 2)
        set_height(win, 12)
        goto_line(win, 8)

        local viewport_state = capture_state(bufnr, { will_restore_insert = false })
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "@Assistant: Thinking..." })
        local thinking_lnum = vim.api.nvim_buf_line_count(bufnr)

        ui.reveal_thinking(bufnr, thinking_lnum, viewport_state)

        assert.is_true(visible(win, thinking_lnum))
      end
    )
  end)

  it("Insert mode: user navigates away during request -> STILL moves to @You", function()
    with_chat_buf(
      vim.tbl_map(function(i)
        return "line " .. i
      end, vim.fn.range(1, 30)),
      function(bufnr, win)
        set_scrolloff(win, 1)
        set_height(win, 12)
        goto_bottom(bufnr, win)
        local viewport_state = capture_state(bufnr, { will_restore_insert = true })

        goto_line(win, 8)

        local you_lnum = add_you_prompt(bufnr)
        ui.scroll_to_reveal_you_prompt(bufnr, you_lnum, viewport_state)

        assert.is_true(wait_until(function()
          return cursor_line(win) == you_lnum
        end))
        assert.is_true(visible(win, you_lnum))
      end
    )
  end)

  it("Cursor placed after colon and trailing spaces for @You", function()
    with_chat_buf(
      vim.tbl_map(function(i)
        return "line " .. i
      end, vim.fn.range(1, 20)),
      function(bufnr, win)
        set_scrolloff(win, 0)
        goto_bottom(bufnr, win)
        local viewport_state = capture_state(bufnr, { will_restore_insert = false })

        local you_lnum = add_you_prompt(bufnr)
        ui.scroll_to_reveal_you_prompt(bufnr, you_lnum, viewport_state)

        assert.is_true(wait_until(function()
          return cursor_line(win) == you_lnum
        end))

        local col = vim.api.nvim_win_get_cursor(win)[2]
        local line = vim.api.nvim_buf_get_lines(bufnr, you_lnum - 1, you_lnum, false)[1]
        local colon_pos = line:find(":%s*")
        assert.is_not_nil(colon_pos)
        assert.is_true(col >= colon_pos)
      end
    )
  end)
end)
