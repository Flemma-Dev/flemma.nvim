describe("Bufferline integration", function()
  local bufferline_integration

  before_each(function()
    vim.cmd("silent! %bdelete!")

    -- Invalidate module caches for isolation
    package.loaded["flemma"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.integrations.bufferline"] = nil

    -- Initialize flemma
    require("flemma").setup({})

    -- Load the integration module fresh (re-registers autocmds)
    bufferline_integration = require("flemma.integrations.bufferline")
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  describe("highlight registration", function()
    it("should define FlemmaBusy highlight on require", function()
      local hl = vim.api.nvim_get_hl(0, { name = "FlemmaBusy", link = false })
      assert.is_not_nil(next(hl))
    end)
  end)

  describe("dual-mode detection", function()
    it("should act as callback when opts contains path", function()
      local result = bufferline_integration.get_element_icon({ path = "/tmp/test.chat", filetype = "chat" })
      -- Not busy, should return nil
      assert.is_nil(result)
    end)

    it("should act as factory when opts contains only icon", function()
      local result = bufferline_integration.get_element_icon({ icon = "+" })
      assert.is_function(result)
    end)

    it("should act as factory when called with no args", function()
      local result = bufferline_integration.get_element_icon()
      assert.is_function(result)
    end)

    it("should support chaining factory calls", function()
      local handler = bufferline_integration.get_element_icon({ icon = "A" })({ icon = "B" })
      assert.is_function(handler)
    end)
  end)

  describe("icon resolution", function()
    it("should return nil for non-busy chat buffers", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(bufnr, "/tmp/test.chat")
      vim.bo[bufnr].filetype = "chat"

      local icon = bufferline_integration.get_element_icon({
        path = "/tmp/test.chat",
        filetype = "chat",
      })
      assert.is_nil(icon)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should return busy icon after FlemmaRequestSending", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(bufnr, "/tmp/busy.chat")
      vim.bo[bufnr].filetype = "chat"

      -- Simulate request sending
      vim.api.nvim_exec_autocmds("User", {
        pattern = "FlemmaRequestSending",
        data = { bufnr = bufnr },
      })

      local icon, hl = bufferline_integration.get_element_icon({
        path = "/tmp/busy.chat",
        filetype = "chat",
      })
      assert.are.equal("󰔟", icon)
      assert.are.equal("FlemmaBusy", hl)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should return nil after FlemmaRequestFinished", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(bufnr, "/tmp/done.chat")
      vim.bo[bufnr].filetype = "chat"

      -- Send then finish
      vim.api.nvim_exec_autocmds("User", {
        pattern = "FlemmaRequestSending",
        data = { bufnr = bufnr },
      })
      vim.api.nvim_exec_autocmds("User", {
        pattern = "FlemmaRequestFinished",
        data = { bufnr = bufnr, status = "completed" },
      })

      local icon = bufferline_integration.get_element_icon({
        path = "/tmp/done.chat",
        filetype = "chat",
      })
      assert.is_nil(icon)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should use custom icon from factory", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(bufnr, "/tmp/custom.chat")
      vim.bo[bufnr].filetype = "chat"

      vim.api.nvim_exec_autocmds("User", {
        pattern = "FlemmaRequestSending",
        data = { bufnr = bufnr },
      })

      local handler = bufferline_integration.get_element_icon({ icon = "+" })
      local icon, hl = handler({
        path = "/tmp/custom.chat",
        filetype = "chat",
      })
      assert.are.equal("+", icon)
      assert.are.equal("FlemmaBusy", hl)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should use chained icon override", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(bufnr, "/tmp/chain.chat")
      vim.bo[bufnr].filetype = "chat"

      vim.api.nvim_exec_autocmds("User", {
        pattern = "FlemmaRequestSending",
        data = { bufnr = bufnr },
      })

      local handler = bufferline_integration.get_element_icon({ icon = "A" })({ icon = "B" })
      local icon = handler({
        path = "/tmp/chain.chat",
        filetype = "chat",
      })
      assert.are.equal("B", icon)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("filetype filtering", function()
    it("should return nil for non-chat filetype", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(bufnr, "/tmp/test.lua")
      vim.bo[bufnr].filetype = "lua"

      -- Mark as busy (shouldn't matter for non-chat)
      vim.api.nvim_exec_autocmds("User", {
        pattern = "FlemmaRequestSending",
        data = { bufnr = bufnr },
      })

      local icon = bufferline_integration.get_element_icon({
        path = "/tmp/test.lua",
        filetype = "lua",
      })
      assert.is_nil(icon)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should fall back to .chat extension when filetype is nil", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(bufnr, "/tmp/fallback.chat")

      vim.api.nvim_exec_autocmds("User", {
        pattern = "FlemmaRequestSending",
        data = { bufnr = bufnr },
      })

      local icon = bufferline_integration.get_element_icon({
        path = "/tmp/fallback.chat",
      })
      assert.are.equal("󰔟", icon)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("edge cases", function()
    it("should return nil for unknown path (bufnr resolves to -1)", function()
      local icon = bufferline_integration.get_element_icon({
        path = "/tmp/nonexistent.chat",
        filetype = "chat",
      })
      assert.is_nil(icon)
    end)

    it("should handle BufWipeout cleanup", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(bufnr, "/tmp/wiped.chat")
      vim.bo[bufnr].filetype = "chat"

      -- Mark as busy
      vim.api.nvim_exec_autocmds("User", {
        pattern = "FlemmaRequestSending",
        data = { bufnr = bufnr },
      })

      -- Verify busy before wipe
      local icon = bufferline_integration.get_element_icon({
        path = "/tmp/wiped.chat",
        filetype = "chat",
      })
      assert.are.equal("󰔟", icon)

      -- Wipe the buffer (triggers BufWipeout autocmd which clears busy state)
      vim.api.nvim_buf_delete(bufnr, { force = true })

      -- Use the test-only accessor to verify the entry was cleaned up
      assert.is_nil(bufferline_integration._get_busy_count()[bufnr])
    end)

    it("should track multiple busy buffers independently", function()
      local buf1 = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(buf1, "/tmp/a.chat")
      vim.bo[buf1].filetype = "chat"

      local buf2 = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(buf2, "/tmp/b.chat")
      vim.bo[buf2].filetype = "chat"

      -- Only buf1 is busy
      vim.api.nvim_exec_autocmds("User", {
        pattern = "FlemmaRequestSending",
        data = { bufnr = buf1 },
      })

      local icon1 = bufferline_integration.get_element_icon({
        path = "/tmp/a.chat",
        filetype = "chat",
      })
      local icon2 = bufferline_integration.get_element_icon({
        path = "/tmp/b.chat",
        filetype = "chat",
      })

      assert.are.equal("󰔟", icon1)
      assert.is_nil(icon2)

      vim.api.nvim_buf_delete(buf1, { force = true })
      vim.api.nvim_buf_delete(buf2, { force = true })
    end)

    it("should use nesting counter for overlapping events", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(bufnr, "/tmp/nested.chat")
      vim.bo[bufnr].filetype = "chat"

      local opts = { path = "/tmp/nested.chat", filetype = "chat" }

      -- Request starts (count=1)
      vim.api.nvim_exec_autocmds("User", {
        pattern = "FlemmaRequestSending",
        data = { bufnr = bufnr },
      })
      assert.are.equal("󰔟", bufferline_integration.get_element_icon(opts))

      -- Tool starts inside the request (count=2)
      vim.api.nvim_exec_autocmds("User", {
        pattern = "FlemmaToolExecuting",
        data = { bufnr = bufnr, tool_name = "bash", tool_id = "t1" },
      })
      assert.are.equal("󰔟", bufferline_integration.get_element_icon(opts))
      assert.are.equal(2, bufferline_integration._get_busy_count()[bufnr])

      -- Tool finishes (count=1, still busy)
      vim.api.nvim_exec_autocmds("User", {
        pattern = "FlemmaToolFinished",
        data = { bufnr = bufnr, tool_name = "bash", tool_id = "t1", status = "success" },
      })
      assert.are.equal("󰔟", bufferline_integration.get_element_icon(opts))
      assert.are.equal(1, bufferline_integration._get_busy_count()[bufnr])

      -- Request finishes (count=0, no longer busy)
      vim.api.nvim_exec_autocmds("User", {
        pattern = "FlemmaRequestFinished",
        data = { bufnr = bufnr, status = "completed" },
      })
      assert.is_nil(bufferline_integration.get_element_icon(opts))
      assert.is_nil(bufferline_integration._get_busy_count()[bufnr])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should not go below zero on extra finish events", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(bufnr, "/tmp/extra.chat")
      vim.bo[bufnr].filetype = "chat"

      -- Finish without a prior send
      vim.api.nvim_exec_autocmds("User", {
        pattern = "FlemmaRequestFinished",
        data = { bufnr = bufnr, status = "completed" },
      })

      -- Counter should be nil (cleaned up), not negative
      assert.is_nil(bufferline_integration._get_busy_count()[bufnr])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should show busy during tool execution alone", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_buf_set_name(bufnr, "/tmp/tool.chat")
      vim.bo[bufnr].filetype = "chat"

      local opts = { path = "/tmp/tool.chat", filetype = "chat" }

      vim.api.nvim_exec_autocmds("User", {
        pattern = "FlemmaToolExecuting",
        data = { bufnr = bufnr, tool_name = "read", tool_id = "t2" },
      })
      assert.are.equal("󰔟", bufferline_integration.get_element_icon(opts))

      vim.api.nvim_exec_autocmds("User", {
        pattern = "FlemmaToolFinished",
        data = { bufnr = bufnr, tool_name = "read", tool_id = "t2", status = "success" },
      })
      assert.is_nil(bufferline_integration.get_element_icon(opts))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
