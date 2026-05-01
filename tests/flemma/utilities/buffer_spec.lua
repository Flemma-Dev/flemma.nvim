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
end)
