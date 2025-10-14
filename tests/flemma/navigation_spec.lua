describe("Flemma Navigation Commands", function()
  local flemma

  before_each(function()
    -- Invalidate the main flemma module cache to ensure a clean setup for each test
    package.loaded["flemma"] = nil
    flemma = require("flemma")
    -- Setup with default configuration.
    flemma.setup({})

    -- Clean up any buffers created during previous tests
    vim.cmd("silent! %bdelete!")
  end)

  after_each(function()
    -- Clean up any buffers created during the test
    vim.cmd("silent! %bdelete!")
  end)

  it("FlemmaNextMessage moves cursor to the next message", function()
    -- Arrange: Create a new buffer with multiple messages
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@System: System prompt.",
      "",
      "@You: First message.",
      "",
      "@Assistant: Second message.",
      "",
      "@You: Third message.",
    })

    -- Arrange: Set cursor at the beginning of the file (line 1, col 0)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    -- Act & Assert: First jump
    vim.cmd("FlemmaNextMessage")
    local pos1 = vim.api.nvim_win_get_cursor(0)
    assert.are.same({ 3, 6 }, { pos1[1], pos1[2] }, "Failed to jump to the first message") -- @You: |First message.

    -- Act & Assert: Second jump
    vim.cmd("FlemmaNextMessage")
    local pos2 = vim.api.nvim_win_get_cursor(0)
    assert.are.same({ 5, 12 }, { pos2[1], pos2[2] }, "Failed to jump to the second message") -- @Assistant: |Second message.

    -- Act & Assert: Third jump
    vim.cmd("FlemmaNextMessage")
    local pos3 = vim.api.nvim_win_get_cursor(0)
    assert.are.same({ 7, 6 }, { pos3[1], pos3[2] }, "Failed to jump to the third message") -- @You: |Third message.

    -- Act & Assert: No more jumps
    vim.cmd("FlemmaNextMessage")
    local pos4 = vim.api.nvim_win_get_cursor(0)
    assert.are.same({ 7, 6 }, { pos4[1], pos4[2] }, "Cursor should not move past the last message")
  end)

  it("FlemmaPrevMessage moves cursor to the previous message", function()
    -- Arrange: Create a new buffer with multiple messages
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@System: System prompt.",
      "",
      "@You: First message.",
      "",
      "@Assistant: Second message.",
      "",
      "@You: Third message.",
    })

    -- Arrange: Set cursor at the end of the file
    vim.api.nvim_win_set_cursor(0, { 7, 0 })

    -- Act & Assert: First jump back
    vim.cmd("FlemmaPrevMessage")
    local pos1 = vim.api.nvim_win_get_cursor(0)
    assert.are.same({ 5, 12 }, { pos1[1], pos1[2] }, "Failed to jump back to the second message") -- @Assistant: |Second message.

    -- Act & Assert: Second jump back
    vim.cmd("FlemmaPrevMessage")
    local pos2 = vim.api.nvim_win_get_cursor(0)
    assert.are.same({ 3, 6 }, { pos2[1], pos2[2] }, "Failed to jump back to the first message") -- @You: |First message.

    -- Act & Assert: Third jump back
    vim.cmd("FlemmaPrevMessage")
    local pos3 = vim.api.nvim_win_get_cursor(0)
    assert.are.same({ 1, 9 }, { pos3[1], pos3[2] }, "Failed to jump back to the system message") -- @System: |System prompt.

    -- Act & Assert: No more jumps
    vim.cmd("FlemmaPrevMessage")
    local pos4 = vim.api.nvim_win_get_cursor(0)
    assert.are.same({ 1, 9 }, { pos4[1], pos4[2] }, "Cursor should not move before the first message")
  end)
end)
