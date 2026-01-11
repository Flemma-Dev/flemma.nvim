describe("UI Folding", function()
  local flemma
  local ui
  local parser

  before_each(function()
    -- Invalidate caches to ensure clean setup
    package.loaded["flemma"] = nil
    package.loaded["flemma.ui"] = nil
    package.loaded["flemma.parser"] = nil
    package.loaded["flemma.config"] = nil

    flemma = require("flemma")
    ui = require("flemma.ui")
    parser = require("flemma.parser")

    flemma.setup({})

    -- Clean up any buffers created during previous tests
    vim.cmd("silent! %bdelete!")
  end)

  after_each(function()
    -- Clean up any buffers created during the test
    vim.cmd("silent! %bdelete!")
  end)

  describe("get_fold_level", function()
    it("should return >2 for <thinking> tag", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: response",
        "<thinking>",
        "thinking content",
        "</thinking>",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Line 2 is <thinking>
      local fold_level = ui.get_fold_level(2)
      assert.are.equal(">2", fold_level)
    end)

    it("should return >2 for <thinking> tag with vertex:signature attribute", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: response",
        '<thinking vertex:signature="abc123/def+ghi==">',
        "thinking content",
        "</thinking>",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Line 2 is <thinking vertex:signature="...">
      local fold_level = ui.get_fold_level(2)
      assert.are.equal(">2", fold_level)
    end)

    it("should NOT return >2 for self-closing <thinking/> tag", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: response",
        '<thinking vertex:signature="abc123"/>',
        "more content",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Line 2 is self-closing, should not start a fold
      local fold_level = ui.get_fold_level(2)
      assert.are_not.equal(">2", fold_level)
    end)

    it("should return <2 for </thinking> tag", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: response",
        "<thinking>",
        "thinking content",
        "</thinking>",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Line 4 is </thinking>
      local fold_level = ui.get_fold_level(4)
      assert.are.equal("<2", fold_level)
    end)

    it("should return >1 for role markers", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You: question",
        "@Assistant: response",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      assert.are.equal(">1", ui.get_fold_level(1))
      assert.are.equal(">1", ui.get_fold_level(2))
    end)

    it("should return <1 before next role marker", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You: question",
        "more content",
        "@Assistant: response",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Line 2 should be <1 because line 3 starts a new message
      local fold_level = ui.get_fold_level(2)
      assert.are.equal("<1", fold_level)
    end)

    it("should return >3 for frontmatter on line 1", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "```lua",
        "x = 5",
        "```",
        "@You: question",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      assert.are.equal(">3", ui.get_fold_level(1))
    end)

    it("should return <3 for closing frontmatter fence", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "```lua",
        "x = 5",
        "```",
        "@You: question",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      assert.are.equal("<3", ui.get_fold_level(3))
    end)
  end)

  describe("fold_last_thinking_block", function()
    it("should fold thinking block when last message is @You:", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: response",
        "<thinking>",
        "thought process here",
        "</thinking>",
        "actual response",
        "@You: follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Open a window for the buffer and set window-local options
      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99 -- Start with all folds open

      -- Call the function
      ui.fold_last_thinking_block(bufnr)

      -- Check that the fold exists and is closed
      -- Line 2 is the start of the thinking block
      local foldlevel = vim.fn.foldlevel(2)
      assert.is_true(foldlevel > 0, "Fold should exist at thinking block")

      local foldclosed = vim.fn.foldclosed(2)
      assert.are.equal(2, foldclosed, "Thinking block should be folded at line 2")
    end)

    it("should not fold when last message is not @You:", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You: question",
        "@Assistant: response",
        "<thinking>",
        "thought process",
        "</thinking>",
        "answer",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Open a window for the buffer and set window-local options
      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99 -- Start with all folds open

      -- Call the function
      ui.fold_last_thinking_block(bufnr)

      -- The thinking block should not be folded since the last message is @Assistant:
      local foldclosed = vim.fn.foldclosed(3)
      assert.are.equal(-1, foldclosed, "Thinking block should not be folded")
    end)

    it("should not crash when there is no thinking block", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: response without thinking",
        "@You: follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Open a window for the buffer
      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)

      -- Should not crash
      assert.has_no.errors(function()
        ui.fold_last_thinking_block(bufnr)
      end)
    end)

    it("should not crash with empty buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      -- Open a window for the buffer
      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)

      -- Should not crash
      assert.has_no.errors(function()
        ui.fold_last_thinking_block(bufnr)
      end)
    end)

    it("should handle thinking block with frontmatter", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "```lua",
        "model = 'claude-sonnet-4-5'",
        "```",
        "@Assistant: response",
        "<thinking>",
        "thought process",
        "</thinking>",
        "answer",
        "@You: follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Open a window for the buffer and set window-local options
      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99 -- Start with all folds open

      -- Call the function
      ui.fold_last_thinking_block(bufnr)

      -- Check that the fold exists and is closed
      -- Line 5 is the start of the thinking block
      local foldlevel = vim.fn.foldlevel(5)
      assert.is_true(foldlevel > 0, "Fold should exist at thinking block")

      local foldclosed = vim.fn.foldclosed(5)
      assert.are.equal(5, foldclosed, "Thinking block should be folded at line 5")
    end)

    it("should handle multiple thinking blocks and only fold the last one", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: first response",
        "<thinking>",
        "first thought",
        "</thinking>",
        "first answer",
        "@You: another question",
        "@Assistant: second response",
        "<thinking>",
        "second thought",
        "</thinking>",
        "second answer",
        "@You: follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Open a window for the buffer and set window-local options
      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99 -- Start with all folds open

      -- Call the function
      ui.fold_last_thinking_block(bufnr)

      -- The second thinking block (line 8) should be folded
      local foldclosed_second = vim.fn.foldclosed(8)
      assert.are.equal(8, foldclosed_second, "Second thinking block should be folded")

      -- The first thinking block (line 2) should remain open
      local foldclosed_first = vim.fn.foldclosed(2)
      assert.are.equal(-1, foldclosed_first, "First thinking block should remain open")
    end)

    it("should fold thinking block with vertex:signature attribute", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: response",
        '<thinking vertex:signature="abc123/def+ghi==">',
        "thought process here",
        "</thinking>",
        "actual response",
        "@You: follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Open a window for the buffer and set window-local options
      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99 -- Start with all folds open

      -- Call the function
      ui.fold_last_thinking_block(bufnr)

      -- Check that the fold exists and is closed
      -- Line 2 is the start of the thinking block
      local foldlevel = vim.fn.foldlevel(2)
      assert.is_true(foldlevel > 0, "Fold should exist at thinking block with signature")

      local foldclosed = vim.fn.foldclosed(2)
      assert.are.equal(2, foldclosed, "Thinking block with signature should be folded at line 2")
    end)
  end)
end)
