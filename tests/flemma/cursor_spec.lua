describe("cursor engine", function()
  local cursor
  local state_module

  before_each(function()
    package.loaded["flemma.cursor"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.schema"] = nil
    cursor = require("flemma.cursor")
    state_module = require("flemma.state")
    -- Initialize config facade with defaults
    local config_facade = require("flemma.config")
    config_facade.init(require("flemma.config.schema"))
    config_facade.apply(config_facade.LAYERS.SETUP, {
      editing = { manage_updatetime = true },
    })
  end)

  describe("request_move with force=true", function()
    it("moves cursor immediately", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@System:",
        "You are helpful.",
        "@You:",
        "Hello",
        "@Assistant:",
        "Hi there!",
        "@You:",
        "",
      })
      -- Open the buffer in current window
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      cursor.request_move(bufnr, { line = 7, col = 0, force = true })

      local pos = vim.api.nvim_win_get_cursor(0)
      assert.are.same({ 7, 0 }, pos)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("clamps to buffer bounds", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2" })
      vim.api.nvim_set_current_buf(bufnr)

      cursor.request_move(bufnr, { line = 999, col = 0, force = true })

      local pos = vim.api.nvim_win_get_cursor(0)
      assert.are.same({ 2, 0 }, pos)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("resolves bottom=true to last line", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c", "d" })
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      cursor.request_move(bufnr, { line = 1, bottom = true, force = true })

      local pos = vim.api.nvim_win_get_cursor(0)
      assert.are.same({ 4, 0 }, pos)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("clears any pending deferred move", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })
      vim.api.nvim_set_current_buf(bufnr)

      -- Request a deferred move first
      cursor.request_move(bufnr, { line = 2 })
      local bs = state_module.get_buffer_state(bufnr)
      assert.is_not_nil(bs.cursor_pending)

      -- Force move clears it
      cursor.request_move(bufnr, { line = 3, force = true })
      assert.is_nil(bs.cursor_pending)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("request_move deferred (no force)", function()
    it("places extmark without moving cursor", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      cursor.request_move(bufnr, { line = 3 })

      -- Cursor should NOT have moved
      local pos = vim.api.nvim_win_get_cursor(0)
      assert.are.same({ 1, 0 }, pos)

      -- But pending state should exist
      local bs = state_module.get_buffer_state(bufnr)
      assert.is_not_nil(bs.cursor_pending)
      assert.are.equal(false, bs.cursor_pending.bottom)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("extmark tracks position through insertions", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "target", "d" })
      vim.api.nvim_set_current_buf(bufnr)

      -- Request move to line 3 ("target")
      cursor.request_move(bufnr, { line = 3 })

      -- Insert 2 lines above the target
      vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "new1", "new2" })

      -- Extmark should now be at line 5 (3 + 2)
      local bs = state_module.get_buffer_state(bufnr)
      local extmark_pos = vim.api.nvim_buf_get_extmark_by_id(
        bufnr,
        vim.api.nvim_create_namespace("flemma_cursor_target"),
        bs.cursor_pending.extmark_id,
        {}
      )
      assert.are.equal(4, extmark_pos[1]) -- 0-indexed line 4 = 1-indexed line 5

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("coalesces multiple deferred requests to last one", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c", "d", "e" })
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      cursor.request_move(bufnr, { line = 2 })
      cursor.request_move(bufnr, { line = 3 })
      cursor.request_move(bufnr, { line = 5 })

      -- Only one pending target should exist (the last one)
      local bs = state_module.get_buffer_state(bufnr)
      assert.is_not_nil(bs.cursor_pending)

      -- Force-evaluate the pending move to verify it goes to line 5
      cursor._evaluate_pending(bufnr)

      local pos = vim.api.nvim_win_get_cursor(0)
      assert.are.same({ 5, 0 }, pos)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("cancel_pending", function()
    it("clears pending state and extmark", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })
      vim.api.nvim_set_current_buf(bufnr)

      cursor.request_move(bufnr, { line = 3 })
      local bs = state_module.get_buffer_state(bufnr)
      assert.is_not_nil(bs.cursor_pending)

      cursor.cancel_pending(bufnr)
      assert.is_nil(bs.cursor_pending)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("tail mode", function()
    it("engages and queries tail mode", function()
      local bufnr = vim.api.nvim_create_buf(false, true)

      assert.is_false(cursor.is_tailing(bufnr))
      cursor.tail(bufnr)
      assert.is_true(cursor.is_tailing(bufnr))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("disengages tail mode", function()
      local bufnr = vim.api.nvim_create_buf(false, true)

      cursor.tail(bufnr)
      cursor.untail(bufnr)
      assert.is_false(cursor.is_tailing(bufnr))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("untail is a no-op when already off", function()
      local bufnr = vim.api.nvim_create_buf(false, true)

      cursor.untail(bufnr)
      assert.is_false(cursor.is_tailing(bufnr))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("is buffer-scoped", function()
      local buf_a = vim.api.nvim_create_buf(false, true)
      local buf_b = vim.api.nvim_create_buf(false, true)

      cursor.tail(buf_a)

      assert.is_true(cursor.is_tailing(buf_a))
      assert.is_false(cursor.is_tailing(buf_b))

      vim.api.nvim_buf_delete(buf_a, { force = true })
      vim.api.nvim_buf_delete(buf_b, { force = true })
    end)

    it("follow scrolls to bottom when tailing", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c", "d", "e" })
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      cursor.tail(bufnr)
      cursor.follow(bufnr)

      local pos = vim.api.nvim_win_get_cursor(0)
      assert.are.same({ 5, 0 }, pos)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("follow is a no-op when not tailing", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c", "d", "e" })
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      cursor.follow(bufnr)

      local pos = vim.api.nvim_win_get_cursor(0)
      assert.are.same({ 2, 0 }, pos)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("follow tracks a growing buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "Hello" })
      vim.api.nvim_set_current_buf(bufnr)

      cursor.tail(bufnr)

      -- Simulate first streaming chunk
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "@Assistant:", "chunk 1" })
      cursor.follow(bufnr)
      assert.are.equal(vim.api.nvim_buf_line_count(bufnr), vim.api.nvim_win_get_cursor(0)[1])

      -- Simulate second streaming chunk (buffer grows)
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "chunk 2", "chunk 3" })
      cursor.follow(bufnr)
      assert.are.equal(vim.api.nvim_buf_line_count(bufnr), vim.api.nvim_win_get_cursor(0)[1])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("detects breakaway via drift when user moves above follow target", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c", "d", "e" })
      vim.api.nvim_set_current_buf(bufnr)

      cursor.tail(bufnr)

      -- First follow: scrolls to bottom, sets target
      cursor.follow(bufnr)
      assert.are.same({ 5, 0 }, vim.api.nvim_win_get_cursor(0))
      assert.is_true(cursor.is_tailing(bufnr))

      -- Simulate user moving up (between event loop ticks, before CursorMoved fires)
      vim.api.nvim_win_set_cursor(0, { 3, 0 })

      -- Buffer grows (new on_content chunk)
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "f", "g" })

      -- Next follow detects cursor drifted below target — breakaway
      cursor.follow(bufnr)
      assert.is_false(cursor.is_tailing(bufnr))
      -- Cursor should NOT have moved to bottom
      assert.are.same({ 3, 0 }, vim.api.nvim_win_get_cursor(0))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("does not false-breakaway when buffer grows below cursor", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })
      vim.api.nvim_set_current_buf(bufnr)

      cursor.tail(bufnr)
      cursor.follow(bufnr)
      assert.are.same({ 3, 0 }, vim.api.nvim_win_get_cursor(0))

      -- Buffer grows (content appended below, cursor doesn't move)
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "d", "e", "f" })
      -- Cursor is still at line 3 (= previous target), buffer has 6 lines

      -- follow should NOT breakaway — cursor is at the target, buffer just grew
      cursor.follow(bufnr)
      assert.is_true(cursor.is_tailing(bufnr))
      assert.are.same({ 6, 0 }, vim.api.nvim_win_get_cursor(0))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("does not false-breakaway after undo shrinks buffer below stale target", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c", "d", "e", "f", "g", "h" })
      vim.api.nvim_set_current_buf(bufnr)

      cursor.tail(bufnr)

      -- Simulate first response: follow sets target to line 8
      cursor.follow(bufnr)
      assert.are.equal(8, vim.api.nvim_win_get_cursor(0)[1])

      -- Simulate undo: buffer shrinks drastically
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b" })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      -- Re-send: tail() must clear stale target even though auto_scroll is already true
      cursor.tail(bufnr)
      assert.is_true(cursor.is_tailing(bufnr))

      -- New response: follow should work, not false-breakaway
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "@Assistant:", "response" })
      cursor.follow(bufnr)

      assert.is_true(cursor.is_tailing(bufnr))
      assert.are.equal(vim.api.nvim_buf_line_count(bufnr), vim.api.nvim_win_get_cursor(0)[1])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("idle timer reset", function()
    it("resets timer when CursorMoved fires", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      cursor.setup()
      cursor.request_move(bufnr, { line = 3 })

      -- Simulate user moving cursor (fires CursorMoved)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = bufnr })

      -- Timer was reset — pending move still exists, cursor not at target
      local bs = state_module.get_buffer_state(bufnr)
      assert.is_not_nil(bs.cursor_pending)
      local pos = vim.api.nvim_win_get_cursor(0)
      assert.are.same({ 2, 0 }, pos)

      cursor.cancel_pending(bufnr)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("breakaway", function()
    it("disengages tail when user moves away from bottom during request", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local bufname = vim.fn.tempname() .. ".chat"
      vim.api.nvim_buf_set_name(bufnr, bufname)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c", "d", "e" })
      vim.api.nvim_set_current_buf(bufnr)

      cursor.setup()
      cursor.tail(bufnr)

      local buffer_state = state_module.get_buffer_state(bufnr)
      buffer_state.current_request = 1

      -- Start at bottom, then user moves to line 2
      vim.api.nvim_win_set_cursor(0, { 5, 0 })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { pattern = bufname })

      assert.is_false(cursor.is_tailing(bufnr))

      buffer_state.current_request = nil
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("does not disengage when cursor is at the last line", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local bufname = vim.fn.tempname() .. ".chat"
      vim.api.nvim_buf_set_name(bufnr, bufname)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })
      vim.api.nvim_set_current_buf(bufnr)

      cursor.setup()
      cursor.tail(bufnr)

      local buffer_state = state_module.get_buffer_state(bufnr)
      buffer_state.current_request = 1

      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { pattern = bufname })

      assert.is_true(cursor.is_tailing(bufnr))

      buffer_state.current_request = nil
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("does not disengage when no active request", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local bufname = vim.fn.tempname() .. ".chat"
      vim.api.nvim_buf_set_name(bufnr, bufname)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c", "d", "e" })
      vim.api.nvim_set_current_buf(bufnr)

      cursor.setup()
      cursor.tail(bufnr)

      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { pattern = bufname })

      assert.is_true(cursor.is_tailing(bufnr))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("re-attach", function()
    it("re-engages tail when user moves to last line during request", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local bufname = vim.fn.tempname() .. ".chat"
      vim.api.nvim_buf_set_name(bufnr, bufname)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c", "d", "e" })
      vim.api.nvim_set_current_buf(bufnr)

      cursor.setup()

      local buffer_state = state_module.get_buffer_state(bufnr)
      buffer_state.current_request = 1

      vim.api.nvim_win_set_cursor(0, { 5, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { pattern = bufname })

      assert.is_true(cursor.is_tailing(bufnr))

      buffer_state.current_request = nil
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("does not re-engage when no active request", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local bufname = vim.fn.tempname() .. ".chat"
      vim.api.nvim_buf_set_name(bufnr, bufname)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })
      vim.api.nvim_set_current_buf(bufnr)

      cursor.setup()

      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { pattern = bufname })

      assert.is_false(cursor.is_tailing(bufnr))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("round-trips breakaway and re-attach correctly", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local bufname = vim.fn.tempname() .. ".chat"
      vim.api.nvim_buf_set_name(bufnr, bufname)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c", "d", "e" })
      vim.api.nvim_set_current_buf(bufnr)

      cursor.setup()
      cursor.tail(bufnr)

      local buffer_state = state_module.get_buffer_state(bufnr)
      buffer_state.current_request = 1

      -- Breakaway: move to line 2
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { pattern = bufname })
      assert.is_false(cursor.is_tailing(bufnr))

      -- Re-attach: move to last line
      vim.api.nvim_win_set_cursor(0, { 5, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { pattern = bufname })
      assert.is_true(cursor.is_tailing(bufnr))

      -- Breakaway again
      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { pattern = bufname })
      assert.is_false(cursor.is_tailing(bufnr))

      buffer_state.current_request = nil
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
