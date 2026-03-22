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
end)
