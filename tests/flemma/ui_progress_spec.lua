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

  describe("cleanup_progress on empty spinner placeholder", function()
    it("removes the @Assistant: line when it is the last line", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "Hello", "", "@Assistant:" })
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.current_request = 1

      ui.cleanup_progress(bufnr)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.same({ "@You:", "Hello", "" }, lines)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("cleanup_progress with existing content", function()
    it("does not modify buffer when last line is not the placeholder", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "Hello", "", "@Assistant:", "Some response" })
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.current_request = 1

      ui.cleanup_progress(bufnr)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.same({ "@You:", "Hello", "", "@Assistant:", "Some response" }, lines)

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
      assert.is_nil(buffer_state.progress_bar)
      assert.is_nil(buffer_state.progress_tick)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("cleanup_progress dismisses progress bar", function()
    local bar_mock

    before_each(function()
      package.loaded["flemma.ui.bar"] = nil
      bar_mock = require("tests.utilities.bar_mock").install_as_flemma_ui_bar()
      package.loaded["flemma.ui"] = nil
      ui = require("flemma.ui")
    end)

    it("calls dismiss on an active progress bar and clears state", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "Hello", "", "@Assistant:" })
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.current_request = 1

      -- Seed a mocked bar as if streaming had opened one
      buffer_state.progress_bar = bar_mock.new({
        bufnr = bufnr,
        position = "bottom left",
        segments = {},
      })

      ui.cleanup_progress(bufnr)

      assert.is_true(bar_mock._handles[1]:is_dismissed())
      assert.is_nil(buffer_state.progress_bar)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("progress bar icon / segment-text split", function()
    local bar_mock

    before_each(function()
      package.loaded["flemma.ui.bar"] = nil
      bar_mock = require("tests.utilities.bar_mock").install_as_flemma_ui_bar()
      package.loaded["flemma.ui"] = nil
      ui = require("flemma.ui")
    end)

    -- Regression guard. Earlier the spinner was baked into the progress body
    -- returned by format_progress_text AND passed as Bar's `icon`. With a
    -- wide gutter the gutter-icon float and the main float then showed the
    -- spinner twice; with a narrow gutter the inline-icon prepend did the
    -- same. The icon and the text must come from separate slots.
    it("never carries the spinner glyph in both Bar.icon and segment text", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "hi", "", "@Assistant:" })
      vim.api.nvim_set_current_buf(bufnr)
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.current_request = 1

      ui.start_progress(bufnr, { timeout = 30 })

      vim.wait(200, function()
        return buffer_state.progress_extmark_id ~= nil
      end)

      -- Streaming phase routes every tick through the Bar (inline virt_text
      -- is cleared), so a Bar handle must be created.
      buffer_state.progress_phase = "streaming"
      buffer_state.progress_char_count = 100

      vim.wait(400, function()
        return #bar_mock._handles > 0
      end)

      assert.is_true(#bar_mock._handles > 0, "progress bar was not created")

      local handle = bar_mock._handles[1]

      -- Collapse constructor opts with every recorded update() into the
      -- latest logical view — the values Bar.render would see on screen.
      local icon = handle.opts.icon
      local segments = handle.opts.segments
      for _, call in ipairs(handle.calls) do
        if call.method == "update" and call.args[1] then
          if call.args[1].icon ~= nil then
            icon = call.args[1].icon
          end
          if call.args[1].segments ~= nil then
            segments = call.args[1].segments
          end
        end
      end

      assert.is_truthy(icon, "Bar should carry an icon (spinner lives in icon slot)")
      assert.is_truthy(segments and segments[1] and segments[1].items[1], "Bar should have a segment text body")
      local text = segments[1].items[1].text or ""
      assert.is_false(
        text:sub(1, #icon) == icon,
        "segment text must not begin with the icon; this duplicates the spinner "
          .. "either in the gutter float (wide gutter) or inline prepend (narrow gutter). "
          .. "icon="
          .. vim.inspect(icon)
          .. " text="
          .. vim.inspect(text)
      )

      ui.cleanup_progress(bufnr)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
