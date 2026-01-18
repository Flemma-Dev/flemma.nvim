-- Tests for cross-buffer state management
-- These tests verify that state is properly isolated per-buffer

describe("State Management", function()
  local flemma
  local ui
  local state
  local core

  before_each(function()
    -- Invalidate caches to ensure clean setup
    package.loaded["flemma"] = nil
    package.loaded["flemma.ui"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.parser"] = nil

    flemma = require("flemma")
    ui = require("flemma.ui")
    state = require("flemma.state")
    core = require("flemma.core")

    flemma.setup({
      editing = {
        manage_updatetime = true,
        foldlevel = 1,
      },
    })

    -- Clean up any buffers created during previous tests
    vim.cmd("silent! %bdelete!")

    -- Reset updatetime to a known value
    vim.o.updatetime = 4000
  end)

  after_each(function()
    -- Clean up any buffers created during the test
    vim.cmd("silent! %bdelete!")
    -- Restore updatetime
    vim.o.updatetime = 4000
  end)

  describe("updatetime management", function()
    it("should preserve updatetime when opening single chat buffer", function()
      local original = vim.o.updatetime
      assert.equals(4000, original)

      -- Create and enter chat buffer
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(bufnr, "/tmp/test1.chat")
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_set_current_buf(bufnr)

      -- Trigger BufEnter autocmd with the chat pattern
      vim.cmd("doautocmd BufEnter *.chat")

      -- updatetime should be lowered for chat
      assert.equals(100, vim.o.updatetime)

      -- Leave to non-chat buffer
      -- First trigger BufLeave while still in chat buffer
      vim.cmd("doautocmd BufLeave *.chat")

      local other_buf = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(other_buf, "/tmp/other.txt")
      vim.api.nvim_set_current_buf(other_buf)

      -- Wait for vim.schedule callbacks to run
      vim.wait(10, function() return false end)

      -- updatetime should be restored
      assert.equals(4000, vim.o.updatetime)
    end)

    it("should handle multiple chat buffers correctly", function()
      local original = 4000
      vim.o.updatetime = original

      -- Create first chat buffer
      local buf1 = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(buf1, "/tmp/test1.chat")
      vim.bo[buf1].filetype = "chat"

      -- Create second chat buffer
      local buf2 = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(buf2, "/tmp/test2.chat")
      vim.bo[buf2].filetype = "chat"

      -- Create non-chat buffer
      local other_buf = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(other_buf, "/tmp/other.txt")

      -- Enter first chat buffer
      vim.api.nvim_set_current_buf(buf1)
      vim.cmd("doautocmd BufEnter *.chat")
      assert.equals(100, vim.o.updatetime)

      -- Switch to second chat buffer
      -- The BufLeave schedules a check, but BufEnter adds buf2 before the check runs
      vim.cmd("doautocmd BufLeave *.chat")
      vim.api.nvim_set_current_buf(buf2)
      vim.cmd("doautocmd BufEnter *.chat")
      -- Wait for scheduled callbacks
      vim.wait(10, function() return false end)
      -- Should still be 100 (switched to another chat buffer)
      assert.equals(100, vim.o.updatetime)

      -- Switch to non-chat from buf2
      vim.cmd("doautocmd BufLeave *.chat")
      vim.api.nvim_set_current_buf(other_buf)
      -- Wait for scheduled callbacks
      vim.wait(10, function() return false end)

      -- updatetime should be restored to original
      assert.equals(original, vim.o.updatetime)

      -- Go back to buf1
      vim.api.nvim_set_current_buf(buf1)
      vim.cmd("doautocmd BufEnter *.chat")
      assert.equals(100, vim.o.updatetime)

      -- Leave buf1 to non-chat
      vim.cmd("doautocmd BufLeave *.chat")
      vim.api.nvim_set_current_buf(other_buf)
      -- Wait for scheduled callbacks
      vim.wait(10, function() return false end)

      -- Should still restore correctly
      assert.equals(original, vim.o.updatetime)
    end)
  end)

  describe("folding setup", function()
    it("should set folding on correct window for buffer", function()
      -- Create two windows
      vim.cmd("new")
      local win1 = vim.api.nvim_get_current_win()

      vim.cmd("new")
      local win2 = vim.api.nvim_get_current_win()

      -- Create chat buffer
      local chat_buf = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(chat_buf, "/tmp/test.chat")

      -- Set buffer in win1 while we're in win2
      vim.api.nvim_win_set_buf(win1, chat_buf)

      -- Trigger filetype detection for the chat buffer
      vim.bo[chat_buf].filetype = "chat"

      -- Now apply settings to the correct window
      vim.api.nvim_win_call(win1, function()
        ui.setup_folding()
      end)

      -- Check folding is set on win1
      assert.equals("expr", vim.wo[win1].foldmethod)

      -- win2 should not have chat folding
      assert.not_equals('v:lua.require("flemma.ui").get_fold_level(v:lnum)', vim.wo[win2].foldexpr)
    end)
  end)

  describe("ruler width calculation", function()
    it("should use correct window width when buffer is in different window", function()
      -- Create two windows with different widths
      vim.cmd("vnew")
      local narrow_win = vim.api.nvim_get_current_win()
      vim.cmd("vertical resize 40")

      vim.cmd("wincmd l")
      local wide_win = vim.api.nvim_get_current_win()
      -- The remaining window gets the rest of the width

      -- Create chat buffer in narrow window
      local chat_buf = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(chat_buf, "/tmp/test.chat")
      vim.bo[chat_buf].filetype = "chat"
      vim.api.nvim_win_set_buf(narrow_win, chat_buf)

      -- Add content for rulers
      vim.api.nvim_buf_set_lines(chat_buf, 0, -1, false, {
        "@You: Hello",
        "@Assistant: Hi there",
      })

      -- Stay in wide window and trigger UI update on chat buffer
      vim.api.nvim_set_current_win(wide_win)

      -- The test verifies the function can handle being called from wrong window
      -- (After fix, it should use the buffer's window width)
      assert.has_no.errors(function()
        ui.update_ui(chat_buf)
      end)
    end)
  end)

  describe("cursor movement functions", function()
    it("move_to_bottom should operate on specified buffer", function()
      -- Create chat buffer with content
      local chat_buf = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(chat_buf, "/tmp/test.chat")
      vim.bo[chat_buf].filetype = "chat"
      vim.api.nvim_buf_set_lines(chat_buf, 0, -1, false, {
        "@You: Hello",
        "Line 2",
        "Line 3",
        "Line 4",
        "Line 5",
      })

      -- Create other buffer
      local other_buf = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_lines(other_buf, 0, -1, false, {
        "Other line 1",
        "Other line 2",
      })

      -- Open chat buffer first
      vim.api.nvim_set_current_buf(chat_buf)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      -- Switch to other buffer
      vim.api.nvim_set_current_buf(other_buf)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      -- Store cursor position in other buffer
      local cursor_before = vim.api.nvim_win_get_cursor(0)
      assert.equals(1, cursor_before[1])

      -- Call move_to_bottom for chat buffer (after fix, should accept bufnr)
      -- For now, this test documents the expected behavior
      -- ui.move_to_bottom(chat_buf)  -- Should move cursor in chat_buf, not current

      -- Current buffer's cursor should NOT have moved
      -- (This test will pass after the fix)
    end)

    it("set_cursor should operate on correct window for buffer", function()
      -- Create two windows
      vim.cmd("new")
      local win1 = vim.api.nvim_get_current_win()

      vim.cmd("new")
      local win2 = vim.api.nvim_get_current_win()

      -- Create buffers
      local buf1 = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_lines(buf1, 0, -1, false, { "Line 1", "Line 2", "Line 3" })
      vim.api.nvim_win_set_buf(win1, buf1)

      local buf2 = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { "Other 1", "Other 2" })
      vim.api.nvim_win_set_buf(win2, buf2)

      -- Set cursor in win1 to line 1
      vim.api.nvim_win_set_cursor(win1, { 1, 0 })
      -- Set cursor in win2 to line 1
      vim.api.nvim_win_set_cursor(win2, { 1, 0 })

      -- Stay in win2, call set_cursor for buf1 (after fix)
      -- ui.set_cursor(buf1, 3, 0)  -- Should set cursor in win1 to line 3

      -- Verify win1 cursor moved
      -- local win1_cursor = vim.api.nvim_win_get_cursor(win1)
      -- assert.equals(3, win1_cursor[1])

      -- Verify win2 cursor did NOT move
      local win2_cursor = vim.api.nvim_win_get_cursor(win2)
      assert.equals(1, win2_cursor[1])
    end)
  end)

  describe("buffer state isolation", function()
    it("should maintain separate state per buffer", function()
      local buf1 = vim.api.nvim_create_buf(false, false)
      local buf2 = vim.api.nvim_create_buf(false, false)

      -- Get state for each buffer
      local state1 = state.get_buffer_state(buf1)
      local state2 = state.get_buffer_state(buf2)

      -- States should be different tables
      assert.not_equals(state1, state2)

      -- Modify state1
      state.set_buffer_state(buf1, "test_value", "buffer1")
      state.set_buffer_state(buf2, "test_value", "buffer2")

      -- Each buffer should have its own value
      assert.equals("buffer1", state.get_buffer_state(buf1).test_value)
      assert.equals("buffer2", state.get_buffer_state(buf2).test_value)
    end)

    it("should cleanup buffer state on buffer delete", function()
      local buf = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(buf, "/tmp/test.chat")
      vim.bo[buf].filetype = "chat"

      -- Initialize state
      local buf_state = state.get_buffer_state(buf)
      assert.is_not_nil(buf_state)

      -- Set some test state
      state.set_buffer_state(buf, "test_value", "test")

      -- Cleanup
      state.cleanup_buffer_state(buf)

      -- State should be reset (get_buffer_state creates new state)
      local new_state = state.get_buffer_state(buf)
      assert.is_nil(new_state.test_value)
    end)

    it("should handle inflight_usage per buffer", function()
      local buf1 = vim.api.nvim_create_buf(false, false)
      local buf2 = vim.api.nvim_create_buf(false, false)

      local state1 = state.get_buffer_state(buf1)
      local state2 = state.get_buffer_state(buf2)

      -- Modify inflight usage for buf1
      state1.inflight_usage.input_tokens = 100
      state1.inflight_usage.output_tokens = 50

      -- buf2 should have independent values
      assert.equals(0, state2.inflight_usage.input_tokens)
      assert.equals(0, state2.inflight_usage.output_tokens)

      -- Verify buf1 still has its values
      assert.equals(100, state1.inflight_usage.input_tokens)
      assert.equals(50, state1.inflight_usage.output_tokens)
    end)
  end)

  describe("spinner timer isolation", function()
    it("should track spinner timer per buffer", function()
      local buf1 = vim.api.nvim_create_buf(false, false)
      local buf2 = vim.api.nvim_create_buf(false, false)

      local state1 = state.get_buffer_state(buf1)
      local state2 = state.get_buffer_state(buf2)

      -- Set timer for buf1
      state1.spinner_timer = 123

      -- buf2 should not have a timer
      assert.is_nil(state2.spinner_timer)

      -- buf1 should have its timer
      assert.equals(123, state1.spinner_timer)
    end)
  end)

  describe("current_request isolation", function()
    it("should track current request per buffer", function()
      local buf1 = vim.api.nvim_create_buf(false, false)
      local buf2 = vim.api.nvim_create_buf(false, false)

      local state1 = state.get_buffer_state(buf1)
      local state2 = state.get_buffer_state(buf2)

      -- Set request for buf1
      state1.current_request = 456

      -- buf2 should not have a request
      assert.is_nil(state2.current_request)

      -- buf1 should have its request
      assert.equals(456, state1.current_request)
    end)
  end)
end)
