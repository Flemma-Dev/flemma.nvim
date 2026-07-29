--- Tests for flemma.utilities.buffer

describe("flemma.utilities.buffer", function()
  local buffer

  before_each(function()
    package.loaded["flemma.utilities.buffer"] = nil
    buffer = require("flemma.utilities.buffer")
  end)

  describe("get_gutter_width", function()
    it("returns textoff for a valid window", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local winid = vim.api.nvim_open_win(bufnr, false, {
        relative = "editor",
        row = 0,
        col = 0,
        width = 40,
        height = 1,
        style = "minimal",
        focusable = false,
      })
      vim.wo[winid].number = true
      vim.wo[winid].numberwidth = 4

      local width = buffer.get_gutter_width(winid)
      assert.is_true(width >= 4)

      vim.api.nvim_win_close(winid, true)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("returns 0 for an invalid window id", function()
      assert.equals(0, buffer.get_gutter_width(-1))
      assert.equals(0, buffer.get_gutter_width(99999))
    end)
  end)

  describe("create_scratch_buffer", function()
    it("creates a nofile buffer with default options", function()
      local bufnr = buffer.create_scratch_buffer()
      assert.is_true(vim.api.nvim_buf_is_valid(bufnr))
      assert.equals("nofile", vim.bo[bufnr].buftype)
      assert.equals("wipe", vim.bo[bufnr].bufhidden)
      assert.equals(-1, vim.bo[bufnr].undolevels)
      assert.is_true(vim.bo[bufnr].modifiable)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("respects bufhidden override", function()
      local bufnr = buffer.create_scratch_buffer({ bufhidden = "hide" })
      assert.equals("hide", vim.bo[bufnr].bufhidden)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("respects modifiable override", function()
      local bufnr = buffer.create_scratch_buffer({ modifiable = false })
      assert.is_false(vim.bo[bufnr].modifiable)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("buffer content helpers", function()
    local bufnr

    before_each(function()
      bufnr = vim.api.nvim_create_buf(false, true)
    end)

    after_each(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    describe("with_modifiable", function()
      it("allows writes when buffer is not modifiable", function()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "original" })
        vim.bo[bufnr].modifiable = false

        buffer.with_modifiable(bufnr, function()
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "modified" })
        end)

        assert.equals("modified", vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1])
      end)

      it("restores modifiable to false after call", function()
        vim.bo[bufnr].modifiable = false

        buffer.with_modifiable(bufnr, function()
          -- buffer is modifiable here
        end)

        assert.is_false(vim.bo[bufnr].modifiable)
      end)

      it("restores modifiable to true if it was true before", function()
        vim.bo[bufnr].modifiable = true

        buffer.with_modifiable(bufnr, function() end)

        assert.is_true(vim.bo[bufnr].modifiable)
      end)

      it("returns the function's return value", function()
        local result = buffer.with_modifiable(bufnr, function()
          return "hello"
        end)

        assert.equals("hello", result)
      end)

      it("restores modifiable on error and re-raises", function()
        vim.bo[bufnr].modifiable = false

        local ok, err = pcall(buffer.with_modifiable, bufnr, function()
          error("test error")
        end)

        assert.is_false(ok)
        assert.is_truthy(err:match("test error"))
        assert.is_false(vim.bo[bufnr].modifiable)
      end)

      it("handles nested calls", function()
        vim.bo[bufnr].modifiable = false

        buffer.with_modifiable(bufnr, function()
          buffer.with_modifiable(bufnr, function()
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "nested" })
          end)
          -- Inner call restores to true (outer set it to true)
          assert.is_true(vim.bo[bufnr].modifiable)
        end)

        -- Outer call restores to original false
        assert.is_false(vim.bo[bufnr].modifiable)
      end)
    end)

    describe("get_line", function()
      it("returns line by 1-based index", function()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "first", "second", "third" })

        assert.equals("first", buffer.get_line(bufnr, 1))
        assert.equals("second", buffer.get_line(bufnr, 2))
        assert.equals("third", buffer.get_line(bufnr, 3))
      end)

      it("returns empty string for empty buffer first line", function()
        -- New buffer has one empty line
        assert.equals("", buffer.get_line(bufnr, 1))
      end)
    end)

    describe("get_last_line", function()
      it("returns last line content and line count", function()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "first", "second", "third" })

        local content, count = buffer.get_last_line(bufnr)
        assert.equals("third", content)
        assert.equals(3, count)
      end)

      it("returns empty string and count for buffer with only empty line", function()
        -- Default buffer has 1 empty line
        local content, count = buffer.get_last_line(bufnr)
        assert.equals("", content)
        assert.equals(1, count)
      end)

      it("returns correct count usable as append index", function()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2" })

        local _, count = buffer.get_last_line(bufnr)
        -- Appending at count should add after last line
        vim.api.nvim_buf_set_lines(bufnr, count, count, false, { "line3" })
        assert.equals("line3", vim.api.nvim_buf_get_lines(bufnr, 2, 3, false)[1])
      end)
    end)
  end)
end)
