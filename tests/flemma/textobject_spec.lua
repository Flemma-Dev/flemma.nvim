describe("Flemma Text Objects", function()
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

  local function setup_buffer_and_cursor()
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@System: System prompt.", -- line 1
      "", -- line 2
      "@You: First line of message.", -- line 3
      "Second line of message.", -- line 4
      "Third line of message.", -- line 5
      "", -- line 6
      "@Assistant: Another message.", -- line 7
    })
    -- Place cursor in the middle of the "You" message
    vim.api.nvim_win_set_cursor(0, { 4, 5 })
    vim.bo[bufnr].filetype = "chat"
    return bufnr
  end

  it("selects inner message with 'im'", function()
    -- Arrange
    local bufnr = setup_buffer_and_cursor()

    -- Act
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("vim", true, false, true), "x", false)
    vim.wait(100) -- Wait for keys to be processed

    -- Assert
    local start_pos = vim.fn.getpos("v")
    local end_pos = vim.fn.getpos(".")

    -- Expected start: line 3, column 7 (after "@You: ")
    assert.are.same({ 3, 7 }, { start_pos[2], start_pos[3] })
    -- Expected end: line 5, end of line
    assert.are.same({ 5, 23 }, { end_pos[2], end_pos[3] })
  end)

  it("selects around message with 'am'", function()
    -- Arrange
    local bufnr = setup_buffer_and_cursor()

    -- Act
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("vam", true, false, true), "x", false)
    vim.wait(100) -- Wait for keys to be processed

    -- Assert
    local start_pos = vim.fn.getpos("v")
    local end_pos = vim.fn.getpos(".")

    -- Expected start: line 3, column 1
    assert.are.same({ 3, 1 }, { start_pos[2], start_pos[3] })
    -- Expected end: line 6, column 1 (on an empty line)
    assert.are.same({ 6, 1 }, { end_pos[2], end_pos[3] })
  end)
end)
