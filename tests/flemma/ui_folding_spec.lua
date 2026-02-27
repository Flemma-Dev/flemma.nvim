describe("UI Folding", function()
  local flemma
  local ui
  local ui_preview

  before_each(function()
    -- Invalidate caches to ensure clean setup
    package.loaded["flemma"] = nil
    package.loaded["flemma.ui"] = nil
    package.loaded["flemma.ui.preview"] = nil
    package.loaded["flemma.parser"] = nil
    package.loaded["flemma.config"] = nil

    flemma = require("flemma")
    ui = require("flemma.ui")
    ui_preview = require("flemma.ui.preview")

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
      local fold_level = ui_preview.get_fold_level(2)
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
      local fold_level = ui_preview.get_fold_level(2)
      assert.are.equal(">2", fold_level)
    end)

    it("should return >2 for <thinking redacted> tag", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: response",
        "<thinking redacted>",
        "encrypted-data-here",
        "</thinking>",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Line 2 is <thinking redacted>
      local fold_level = ui_preview.get_fold_level(2)
      assert.are.equal(">2", fold_level)
    end)

    it("should return >2 for empty thinking tag with signature", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: response",
        '<thinking vertex:signature="abc123">',
        "</thinking>",
        "more content",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Line 2 is opening tag, should start a fold
      local fold_level = ui_preview.get_fold_level(2)
      assert.are.equal(">2", fold_level)
      -- Line 3 is closing tag, should end the fold
      fold_level = ui_preview.get_fold_level(3)
      assert.are.equal("<2", fold_level)
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
      local fold_level = ui_preview.get_fold_level(4)
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

      assert.are.equal(">1", ui_preview.get_fold_level(1))
      assert.are.equal(">1", ui_preview.get_fold_level(2))
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
      local fold_level = ui_preview.get_fold_level(2)
      assert.are.equal("<1", fold_level)
    end)

    it("should include trailing empty lines in the message fold", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You: question", -- line 1: >1
        "more content", -- line 2: =
        "", -- line 3: <1 (end of message, trailing empty line)
        "@Assistant: answer", -- line 4: >1
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      assert.are.equal(">1", ui_preview.get_fold_level(1))
      assert.are.equal("=", ui_preview.get_fold_level(2))
      assert.are.equal("<1", ui_preview.get_fold_level(3))
      assert.are.equal(">1", ui_preview.get_fold_level(4))
    end)

    it("should return >2 for frontmatter on line 1", function()
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

      assert.are.equal(">2", ui_preview.get_fold_level(1))
    end)

    it("should return <2 for closing frontmatter fence", function()
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

      assert.are.equal("<2", ui_preview.get_fold_level(3))
    end)

    it("should return >2 for completed tool_use block start", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: I'll check that.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You: **Tool Result:** `toolu_01`",
        "",
        "```",
        "file1.txt",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Tool use header line (line 3) should start a level-2 fold
      assert.are.equal(">2", ui_preview.get_fold_level(3))
      -- Closing fence (line 6) should end the level-2 fold
      assert.are.equal("<2", ui_preview.get_fold_level(6))
    end)

    it("should return >1 for inline tool_result header (graceful degradation)", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: I'll check that.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You: **Tool Result:** `toolu_01`",
        "",
        "```",
        "file1.txt",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Tool result header line (line 8) is also the @You: line (inline header)
      -- For inline headers, fold level stays at >1 (graceful degradation)
      assert.are.equal(">1", ui_preview.get_fold_level(8))
    end)

    it("should return >2 for tool_result on its own line", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: I'll check that.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "file1.txt",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Tool result header (line 10) should start level-2 fold
      assert.are.equal(">2", ui_preview.get_fold_level(10))
      -- Closing fence (line 14) should end level-2 fold
      assert.are.equal("<2", ui_preview.get_fold_level(14))
    end)

    it("should NOT fold in-flight tool_result (pending status)", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: Running a tool.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01`",
        "",
        "```flemma:tool status=pending",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Pending tool result should stay at message level (=), not start a fold
      assert.are.equal("=", ui_preview.get_fold_level(10))
    end)

    it("should NOT fold in-flight tool_result (approved status)", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: Running a tool.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01`",
        "",
        "```flemma:tool status=approved",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      assert.are.equal("=", ui_preview.get_fold_level(10))
    end)

    it("should fold tool_result with denied status", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: Running a tool.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01`",
        "",
        "```flemma:tool status=denied",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      assert.are.equal(">2", ui_preview.get_fold_level(10))
      assert.are.equal("<2", ui_preview.get_fold_level(13))
    end)

    it("should fold tool_result with rejected status", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: Running a tool.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01`",
        "",
        "```flemma:tool status=rejected",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      assert.are.equal(">2", ui_preview.get_fold_level(10))
    end)

    it("should NOT fold tool_use without a matching tool_result", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: I'll check that.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- No matching result — tool_use stays at message level
      assert.are.equal("=", ui_preview.get_fold_level(3))
    end)

    it("should fold multiple tool blocks independently", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: Two tools.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "**Tool Use:** `bash` (`toolu_02`)",
        "```json",
        '{ "command": "pwd" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "file1.txt",
        "```",
        "",
        "**Tool Result:** `toolu_02`",
        "",
        "```",
        "/home/user",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Both tool_use blocks should fold independently
      assert.are.equal(">2", ui_preview.get_fold_level(3))
      assert.are.equal("<2", ui_preview.get_fold_level(6))
      assert.are.equal(">2", ui_preview.get_fold_level(8))
      assert.are.equal("<2", ui_preview.get_fold_level(11))

      -- Both tool_result blocks should fold independently
      assert.are.equal(">2", ui_preview.get_fold_level(15))
      assert.are.equal("<2", ui_preview.get_fold_level(19))
      assert.are.equal(">2", ui_preview.get_fold_level(21))
      assert.are.equal("<2", ui_preview.get_fold_level(25))
    end)
  end)

  describe("fold_completed_blocks (thinking)", function()
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
      vim.wo.foldexpr = "v:lua.require('flemma.ui.preview').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99 -- Start with all folds open

      -- Call the function
      ui.fold_completed_blocks(bufnr)

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
      vim.wo.foldexpr = "v:lua.require('flemma.ui.preview').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99 -- Start with all folds open

      -- Call the function
      ui.fold_completed_blocks(bufnr)

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
        ui.fold_completed_blocks(bufnr)
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
        ui.fold_completed_blocks(bufnr)
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
      vim.wo.foldexpr = "v:lua.require('flemma.ui.preview').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99 -- Start with all folds open

      -- Call the function
      ui.fold_completed_blocks(bufnr)

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
      vim.wo.foldexpr = "v:lua.require('flemma.ui.preview').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99 -- Start with all folds open

      -- Call the function
      ui.fold_completed_blocks(bufnr)

      -- The second thinking block (line 8) should be folded
      local foldclosed_second = vim.fn.foldclosed(8)
      assert.are.equal(8, foldclosed_second, "Second thinking block should be folded")

      -- The first thinking block (line 2) should remain open
      local foldclosed_first = vim.fn.foldclosed(2)
      assert.are.equal(-1, foldclosed_first, "First thinking block should remain open")
    end)

    it("should fold <thinking redacted> block", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: response",
        "<thinking redacted>",
        "encrypted-data-here",
        "</thinking>",
        "actual response",
        "@You: follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Open a window for the buffer and set window-local options
      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.preview').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99 -- Start with all folds open

      -- Call the function
      ui.fold_completed_blocks(bufnr)

      -- Check that the fold exists and is closed
      local foldlevel = vim.fn.foldlevel(2)
      assert.is_true(foldlevel > 0, "Fold should exist at redacted thinking block")

      local foldclosed = vim.fn.foldclosed(2)
      assert.are.equal(2, foldclosed, "Redacted thinking block should be folded at line 2")
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
      vim.wo.foldexpr = "v:lua.require('flemma.ui.preview').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99 -- Start with all folds open

      -- Call the function
      ui.fold_completed_blocks(bufnr)

      -- Check that the fold exists and is closed
      -- Line 2 is the start of the thinking block
      local foldlevel = vim.fn.foldlevel(2)
      assert.is_true(foldlevel > 0, "Fold should exist at thinking block with signature")

      local foldclosed = vim.fn.foldclosed(2)
      assert.are.equal(2, foldclosed, "Thinking block with signature should be folded at line 2")
    end)
  end)

  describe("get_fold_text", function()
    it("should show tool preview for folded tool_use block", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: I'll check that.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls -la" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "file1.txt",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.preview').get_fold_level(v:lnum)"
      vim.wo.foldtext = "v:lua.require('flemma.ui.preview').get_fold_text()"
      vim.wo.foldlevel = 99

      -- Close fold at tool_use block (lines 3-6)
      vim.cmd("3,6 foldclose")

      -- Get fold text
      vim.v.foldstart = 3
      vim.v.foldend = 6
      local fold_text = ui_preview.get_fold_text()
      assert.is_truthy(fold_text:match("bash"), "Fold text should contain tool name")
      assert.is_truthy(fold_text:match("ls %-la"), "Fold text should contain command preview")
      assert.is_truthy(fold_text:match("%(4 lines%)"), "Fold text should show line count")
    end)

    it("should show content preview for folded tool_result block", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: Checking.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "file1.txt",
        "file2.txt",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.preview').get_fold_level(v:lnum)"
      vim.wo.foldtext = "v:lua.require('flemma.ui.preview').get_fold_text()"
      vim.wo.foldlevel = 99

      -- Close fold at tool_result block (lines 10-15)
      vim.cmd("10,15 foldclose")

      vim.v.foldstart = 10
      vim.v.foldend = 15
      local fold_text = ui_preview.get_fold_text()
      assert.is_truthy(fold_text:match("bash"), "Fold text should contain tool name")
      assert.is_truthy(fold_text:match("file1%.txt"), "Fold text should preview result content")
      assert.is_truthy(fold_text:match("%(6 lines%)"), "Fold text should show line count")
    end)
  end)

  describe("fold_completed_blocks", function()
    it("should fold completed tool_use and tool_result blocks", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: Checking.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "file1.txt",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.preview').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99

      -- Call auto-fold
      ui.fold_completed_blocks(bufnr)

      -- Tool use block should be folded
      local tu_foldclosed = vim.fn.foldclosed(3)
      assert.are.equal(3, tu_foldclosed, "Tool use block should be folded at line 3")

      -- Tool result block should be folded
      local tr_foldclosed = vim.fn.foldclosed(10)
      assert.are.equal(10, tr_foldclosed, "Tool result block should be folded at line 10")
    end)

    it("should not fold pending tool blocks", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: Running.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01`",
        "",
        "```flemma:tool status=pending",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.preview').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99

      ui.fold_completed_blocks(bufnr)

      -- Pending tool result should NOT be folded
      local foldclosed = vim.fn.foldclosed(10)
      assert.are.equal(-1, foldclosed, "Pending tool result should not be folded")
    end)

    it("should not escalate fold when block is already closed", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant: Checking.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "file1.txt",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.preview').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99

      -- Pre-close the tool_use fold
      vim.cmd("3,6 foldclose")

      -- Call auto-fold — should not escalate
      ui.fold_completed_blocks(bufnr)

      -- Message fold should remain open (not escalated by double-close)
      local msg_foldclosed = vim.fn.foldclosed(1)
      assert.are.equal(-1, msg_foldclosed, "Message fold should not be escalated")
    end)
  end)

  describe("folding integration", function()
    it("correctly folds a complete conversation with thinking and tools", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "```lua",
        "model = 'claude-sonnet-4-5'",
        "```",
        "",
        "@You: What files are in this directory?",
        "",
        "@Assistant: Let me check.",
        "<thinking>",
        "User wants a directory listing.",
        "</thinking>",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "file1.txt",
        "file2.txt",
        "```",
        "",
        "@Assistant: There are two files: file1.txt and file2.txt.",
        "",
        "@You: Thanks!",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.preview').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 1

      -- With foldlevel=1:
      -- Frontmatter should be folded (level 2)
      assert.are_not.equal(-1, vim.fn.foldclosed(1), "Frontmatter should be folded")
      -- Thinking should be folded (level 2)
      assert.are_not.equal(-1, vim.fn.foldclosed(8), "Thinking should be folded")
      -- Tool use should be folded (level 2)
      assert.are_not.equal(-1, vim.fn.foldclosed(12), "Tool use should be folded")
      -- Tool result should be folded (level 2)
      assert.are_not.equal(-1, vim.fn.foldclosed(19), "Tool result should be folded")
      -- Messages should be open (level 1)
      assert.are.equal(-1, vim.fn.foldclosed(5), "User message should be open")
      assert.are.equal(-1, vim.fn.foldclosed(7), "Assistant message should be open")
      assert.are.equal(-1, vim.fn.foldclosed(26), "Final assistant message should be open")
    end)
  end)
end)
