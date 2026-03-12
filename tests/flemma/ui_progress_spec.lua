-- Tests for progress line functionality (start, cleanup, transition, phase tracking)

describe("progress line", function()
  local state
  local ui

  before_each(function()
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.ui"] = nil
    state = require("flemma.state")
    ui = require("flemma.ui")
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  describe("start_progress and cleanup_progress", function()
    it("creates and cleans up progress extmark on a real buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "Hello" })
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.current_request = 1 -- Simulate active request

      ui.start_progress(bufnr, { timeout = 600 })

      -- Wait for writequeue to flush
      vim.wait(200, function()
        return buffer_state.progress_extmark_id ~= nil
      end)

      assert.is_not_nil(buffer_state.progress_extmark_id)
      assert.equals("waiting", buffer_state.progress_phase)
      assert.equals(0, buffer_state.progress_char_count)
      assert.is_not_nil(buffer_state.progress_started_at)

      -- Cleanup
      ui.cleanup_progress(bufnr)

      assert.is_nil(buffer_state.progress_phase)
      assert.is_nil(buffer_state.progress_timer)
      assert.is_nil(buffer_state.progress_extmark_id)

      -- Verify spinner-namespace extmarks are gone
      local spinner_ns = vim.api.nvim_create_namespace("flemma_spinner")
      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, spinner_ns, 0, -1, {})
      assert.equals(0, #extmarks)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("phase transitions", function()
    it("tracks character count across phases", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local buffer_state = state.get_buffer_state(bufnr)

      buffer_state.progress_phase = "thinking"
      buffer_state.progress_char_count = buffer_state.progress_char_count + 100

      buffer_state.progress_phase = "streaming"
      buffer_state.progress_char_count = buffer_state.progress_char_count + 500

      buffer_state.progress_phase = "buffering"
      buffer_state.progress_char_count = buffer_state.progress_char_count + 2000

      assert.equals("buffering", buffer_state.progress_phase)
      assert.equals(2600, buffer_state.progress_char_count)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("transition_progress_to_active", function()
    it("clears extmark ID so timer recreates as virt_lines", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.progress_extmark_id = 42
      buffer_state.progress_last_rendered_line = 5

      ui.transition_progress_to_active(bufnr)

      assert.is_nil(buffer_state.progress_extmark_id)
      assert.is_nil(buffer_state.progress_last_rendered_line)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("cleanup_progress on empty spinner placeholder", function()
    it("removes the @Assistant: line when it is the last line", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "Hello", "", "@Assistant:" })
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.current_request = 1

      ui.cleanup_progress(bufnr)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      -- The @Assistant: placeholder line should be removed
      for _, line in ipairs(lines) do
        assert.is_not.equals("@Assistant:", line)
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("initial state defaults", function()
    it("initializes progress fields to expected defaults", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local buffer_state = state.get_buffer_state(bufnr)

      assert.is_nil(buffer_state.progress_timer)
      assert.is_nil(buffer_state.progress_phase)
      assert.equals(0, buffer_state.progress_char_count)
      assert.is_nil(buffer_state.progress_started_at)
      assert.is_nil(buffer_state.progress_timeout)
      assert.is_nil(buffer_state.progress_extmark_id)
      assert.is_nil(buffer_state.progress_last_line)
      assert.is_nil(buffer_state.progress_last_rendered_line)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
