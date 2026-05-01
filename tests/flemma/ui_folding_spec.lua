describe("UI Folding", function()
  local flemma
  local folding

  before_each(function()
    -- Invalidate caches to ensure clean setup
    package.loaded["flemma"] = nil
    package.loaded["flemma.ui"] = nil
    package.loaded["flemma.ui.preview"] = nil
    package.loaded["flemma.ui.folding"] = nil
    package.loaded["flemma.ui.folding.merge"] = nil
    package.loaded["flemma.ui.folding.rules.frontmatter"] = nil
    package.loaded["flemma.ui.folding.rules.thinking"] = nil
    package.loaded["flemma.ui.folding.rules.tool_blocks"] = nil
    package.loaded["flemma.ui.folding.rules.messages"] = nil
    package.loaded["flemma.ast"] = nil
    package.loaded["flemma.ast.nodes"] = nil
    package.loaded["flemma.ast.query"] = nil
    package.loaded["flemma.parser"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.tools.context"] = nil
    package.loaded["flemma.tools.injector"] = nil

    flemma = require("flemma")
    folding = require("flemma.ui.folding")

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
        "@Assistant:",
        "response",
        "<thinking>",
        "thinking content",
        "</thinking>",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Line 3 is <thinking>
      local fold_level = folding.get_fold_level(3)
      assert.are.equal(">2", fold_level)
    end)

    it("should return >2 for <thinking> tag with vertex:signature attribute", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "response",
        '<thinking vertex:signature="abc123/def+ghi==">',
        "thinking content",
        "</thinking>",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Line 3 is <thinking vertex:signature="...">
      local fold_level = folding.get_fold_level(3)
      assert.are.equal(">2", fold_level)
    end)

    it("should return >2 for <thinking redacted> tag", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "response",
        "<thinking redacted>",
        "encrypted-data-here",
        "</thinking>",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Line 3 is <thinking redacted>
      local fold_level = folding.get_fold_level(3)
      assert.are.equal(">2", fold_level)
    end)

    it("should return >2 for empty thinking tag with signature", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "response",
        '<thinking vertex:signature="abc123">',
        "</thinking>",
        "more content",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Line 3 is opening tag, should start a fold
      local fold_level = folding.get_fold_level(3)
      assert.are.equal(">2", fold_level)
      -- Line 4 is closing tag, should end the fold
      fold_level = folding.get_fold_level(4)
      assert.are.equal("<2", fold_level)
    end)

    it("should return <2 for </thinking> tag", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "response",
        "<thinking>",
        "thinking content",
        "</thinking>",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Line 5 is </thinking>
      local fold_level = folding.get_fold_level(5)
      assert.are.equal("<2", fold_level)
    end)

    it("should return >1 for role markers", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You:",
        "question",
        "@Assistant:",
        "response",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      assert.are.equal(">1", folding.get_fold_level(1))
      assert.are.equal(">1", folding.get_fold_level(3))
    end)

    it("should return <1 before next role marker", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You:",
        "question",
        "more content",
        "@Assistant:",
        "response",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Line 3 should be <1 because line 4 starts a new message
      local fold_level = folding.get_fold_level(3)
      assert.are.equal("<1", fold_level)
    end)

    it("should include trailing empty lines in the message fold", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You:",
        "question", -- lines 1-2: >1, =
        "more content", -- line 3: =
        "", -- line 4: <1 (end of message, trailing empty line)
        "@Assistant:",
        "answer", -- lines 5-6: >1
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      assert.are.equal(">1", folding.get_fold_level(1))
      assert.are.equal("=", folding.get_fold_level(2))
      assert.are.equal("=", folding.get_fold_level(3))
      assert.are.equal("<1", folding.get_fold_level(4))
      assert.are.equal(">1", folding.get_fold_level(5))
    end)

    it("should include blank separator in fold when AST snapshot is stale (streaming scenario)", function()
      -- Regression test: when :Flemma send is called, create_ast_snapshot_before_send
      -- captures @You: with end_line=2 (pre-send buffer had only 2 lines). Then
      -- start_progress appends "" + "@Assistant:", making line 3 a blank separator.
      -- During incremental parsing the snapshot preserves end_line=2, so line 3 fell
      -- outside any fold. The merge step must fix up the last frozen message's end_line.
      local parser = require("flemma.parser")
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      -- Pre-send buffer state
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@You:", "Hi!" })

      -- Snapshot taken before start_progress writes blank + @Assistant:
      parser.create_ast_snapshot_before_send(bufnr)

      -- start_progress appends blank separator then @Assistant: placeholder
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "", "@Assistant:" })

      -- Buffer is now: line 1 "@You:", line 2 "Hi!", line 3 "", line 4 "@Assistant:"
      -- The blank separator (line 3) must be inside the @You: fold
      assert.are.equal(">1", folding.get_fold_level(1), "@You: should start message fold")
      assert.are.equal("=", folding.get_fold_level(2), "Hi! should be inside fold")
      assert.are.equal("<1", folding.get_fold_level(3), "blank separator should end @You: fold")
      assert.are.equal(">1", folding.get_fold_level(4), "@Assistant: should start message fold")

      parser.clear_ast_snapshot_before_send(bufnr)
    end)

    it("should return >2 for frontmatter on line 1", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.wo.conceallevel = 0

      local lines = {
        "```lua",
        "x = 5",
        "```",
        "@You:",
        "question",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      assert.are.equal(">2", folding.get_fold_level(1))
    end)

    it("should return <2 for closing frontmatter fence", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.wo.conceallevel = 0

      local lines = {
        "```lua",
        "x = 5",
        "```",
        "@You:",
        "question",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      assert.are.equal("<2", folding.get_fold_level(3))
    end)

    it("should skip frontmatter fold when conceallevel >= 1", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.wo.conceallevel = 2

      local lines = {
        "```lua",
        "x = 5",
        "```",
        "@You:",
        "question",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      assert.are.equal("=", folding.get_fold_level(1), "opening fence should not start a fold when conceallevel>=1")
      assert.are.equal("=", folding.get_fold_level(3), "closing fence should not end a fold when conceallevel>=1")
    end)

    it("should invalidate fold cache when conceallevel toggles", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.wo.conceallevel = 0

      local lines = {
        "```lua",
        "x = 5",
        "```",
        "@You:",
        "question",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      assert.are.equal(">2", folding.get_fold_level(1), "sanity: fold present at conceallevel=0")

      vim.wo.conceallevel = 2

      assert.are.equal("=", folding.get_fold_level(1), "fold should disappear once conceallevel flips to 2")
    end)

    it("should return >2 for completed tool_use block start", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "I'll check that.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You:",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "file1.txt",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Tool use header line (line 4) should start a level-2 fold
      assert.are.equal(">2", folding.get_fold_level(4))
      -- Closing fence (line 7) should end the level-2 fold
      assert.are.equal("<2", folding.get_fold_level(7))
    end)

    it("should return >1 for inline tool_result header (graceful degradation)", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "I'll check that.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You:",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "file1.txt",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- @You: role marker on line 9 starts a message fold
      assert.are.equal(">1", folding.get_fold_level(9))
      -- Tool result header on line 10 (now on its own line) starts a level-2 fold
      assert.are.equal(">2", folding.get_fold_level(10))
    end)

    it("should return >2 for tool_result on its own line", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "I'll check that.",
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

      -- Tool result header (line 11) should start level-2 fold
      assert.are.equal(">2", folding.get_fold_level(11))
      -- Closing fence (line 15) should end level-2 fold
      assert.are.equal("<2", folding.get_fold_level(15))
    end)

    it("should NOT fold in-flight tool_result (pending status)", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "Running a tool.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01` (pending)",
        "",
        "```",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Pending tool result should stay at message level (=), not start a fold
      assert.are.equal("=", folding.get_fold_level(10))
    end)

    it("should NOT fold in-flight tool_result (approved status)", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "Running a tool.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01` (approved)",
        "",
        "```",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      assert.are.equal("=", folding.get_fold_level(10))
    end)

    it("should fold tool_result with denied status", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "Running a tool.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01` (denied)",
        "",
        "```",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      assert.are.equal(">2", folding.get_fold_level(11))
      assert.are.equal("<2", folding.get_fold_level(14))
    end)

    it("should fold tool_result with rejected status", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "Running a tool.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01` (rejected)",
        "",
        "```",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      assert.are.equal(">2", folding.get_fold_level(11))
    end)

    it("should fold tool_result with error status", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "Running a tool.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "bad_cmd" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01` (error)",
        "",
        "```",
        "command not found: bad_cmd",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      assert.are.equal(">2", folding.get_fold_level(11))
    end)

    it("should NOT fold tool_use without a matching tool_result", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "I'll check that.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- No matching result — tool_use stays at message level
      assert.are.equal("=", folding.get_fold_level(3))
    end)

    it("should fold multiple tool blocks independently", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "Two tools.",
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

      -- Tool_use 1 fold extends to absorb trailing blank line (adjacent to tool_use 2)
      assert.are.equal(">2", folding.get_fold_level(4))
      assert.are.equal("<2", folding.get_fold_level(8))
      -- Tool_use 2 fold stays at its own end (last in sequence)
      assert.are.equal(">2", folding.get_fold_level(9))
      assert.are.equal("<2", folding.get_fold_level(12))

      -- Tool_result 1 fold extends to absorb trailing blank line (adjacent to tool_result 2)
      assert.are.equal(">2", folding.get_fold_level(16))
      assert.are.equal("<2", folding.get_fold_level(21))
      -- Tool_result 2 fold stays at its own end (last in sequence)
      assert.are.equal(">2", folding.get_fold_level(22))
      assert.are.equal("<2", folding.get_fold_level(26))
    end)

    it("should not extend fold when text separates tool blocks", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "Here is some text between tool blocks.",
        "",
        "**Tool Use:** `bash` (`toolu_02`)",
        "```json",
        '{ "command": "pwd" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01`",
        "```",
        "file1.txt",
        "```",
        "",
        "Some commentary between results.",
        "",
        "**Tool Result:** `toolu_02`",
        "```",
        "/home/user",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Tool_use 1 fold should NOT extend (non-whitespace text separates from tool_use 2)
      assert.are.equal(">2", folding.get_fold_level(3))
      assert.are.equal("<2", folding.get_fold_level(6))
      -- Tool_use 2 fold stays at its own end
      assert.are.equal(">2", folding.get_fold_level(10))
      assert.are.equal("<2", folding.get_fold_level(13))

      -- Tool_result 1 fold should NOT extend (non-whitespace text separates from tool_result 2)
      assert.are.equal(">2", folding.get_fold_level(17))
      assert.are.equal("<2", folding.get_fold_level(20))
      -- Tool_result 2 fold stays at its own end
      assert.are.equal(">2", folding.get_fold_level(24))
      assert.are.equal("<2", folding.get_fold_level(27))
    end)

    it("should not extend fold when next tool block is not foldable", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
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
        "```",
        "file1.txt",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Tool_use 1 has a terminal result, tool_use 2 does NOT
      -- Tool_use 1 fold should NOT extend (next tool_use is not foldable)
      assert.are.equal(">2", folding.get_fold_level(3))
      assert.are.equal("<2", folding.get_fold_level(6))
      -- Tool_use 2 should NOT fold at all (no terminal result)
      assert.are.equal("=", folding.get_fold_level(8))
    end)
  end)

  describe("fold_completed_blocks (thinking)", function()
    it("should fold thinking block when last message is @You:", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "response",
        "<thinking>",
        "thought process here",
        "</thinking>",
        "actual response",
        "@You:",
        "follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Open a window for the buffer and set window-local options
      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99 -- Start with all folds open

      -- Call the function
      folding.fold_completed_blocks(bufnr)

      -- Check that the fold exists and is closed
      -- Line 3 is the start of the thinking block
      local foldlevel = vim.fn.foldlevel(3)
      assert.is_true(foldlevel > 0, "Fold should exist at thinking block")

      local foldclosed = vim.fn.foldclosed(3)
      assert.are.equal(3, foldclosed, "Thinking block should be folded at line 3")
    end)

    it("should not fold when last message is not @You:", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You:",
        "question",
        "@Assistant:",
        "response",
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
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99 -- Start with all folds open

      -- Call the function
      folding.fold_completed_blocks(bufnr)

      -- The thinking block should not be folded since the last message is @Assistant:
      local foldclosed = vim.fn.foldclosed(5)
      assert.are.equal(-1, foldclosed, "Thinking block should not be folded")
    end)

    it("should not crash when there is no thinking block", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "response without thinking",
        "@You:",
        "follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Open a window for the buffer
      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)

      -- Should not crash
      assert.has_no.errors(function()
        folding.fold_completed_blocks(bufnr)
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
        folding.fold_completed_blocks(bufnr)
      end)
    end)

    it("should handle thinking block with frontmatter", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "```lua",
        "model = 'claude-sonnet-4-5'",
        "```",
        "@Assistant:",
        "response",
        "<thinking>",
        "thought process",
        "</thinking>",
        "answer",
        "@You:",
        "follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Open a window for the buffer and set window-local options
      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99 -- Start with all folds open

      -- Call the function
      folding.fold_completed_blocks(bufnr)

      -- Check that the fold exists and is closed
      -- Line 6 is the start of the thinking block
      local foldlevel = vim.fn.foldlevel(6)
      assert.is_true(foldlevel > 0, "Fold should exist at thinking block")

      local foldclosed = vim.fn.foldclosed(6)
      assert.are.equal(6, foldclosed, "Thinking block should be folded at line 6")
    end)

    it("should handle multiple thinking blocks and only fold the last one", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "first response",
        "<thinking>",
        "first thought",
        "</thinking>",
        "first answer",
        "@You:",
        "another question",
        "@Assistant:",
        "second response",
        "<thinking>",
        "second thought",
        "</thinking>",
        "second answer",
        "@You:",
        "follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Open a window for the buffer and set window-local options
      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99 -- Start with all folds open

      -- Call the function
      folding.fold_completed_blocks(bufnr)

      -- The second thinking block (line 11) should be folded
      local foldclosed_second = vim.fn.foldclosed(11)
      assert.are.equal(11, foldclosed_second, "Second thinking block should be folded")

      -- The first thinking block (line 3) should remain open
      local foldclosed_first = vim.fn.foldclosed(3)
      assert.are.equal(-1, foldclosed_first, "First thinking block should remain open")
    end)

    it("should fold <thinking redacted> block", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "response",
        "<thinking redacted>",
        "encrypted-data-here",
        "</thinking>",
        "actual response",
        "@You:",
        "follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Open a window for the buffer and set window-local options
      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99 -- Start with all folds open

      -- Call the function
      folding.fold_completed_blocks(bufnr)

      -- Check that the fold exists and is closed
      local foldlevel = vim.fn.foldlevel(3)
      assert.is_true(foldlevel > 0, "Fold should exist at redacted thinking block")

      local foldclosed = vim.fn.foldclosed(3)
      assert.are.equal(3, foldclosed, "Redacted thinking block should be folded at line 3")
    end)

    it("should fold thinking block with vertex:signature attribute", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "response",
        '<thinking vertex:signature="abc123/def+ghi==">',
        "thought process here",
        "</thinking>",
        "actual response",
        "@You:",
        "follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Open a window for the buffer and set window-local options
      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99 -- Start with all folds open

      -- Call the function
      folding.fold_completed_blocks(bufnr)

      -- Check that the fold exists and is closed
      -- Line 3 is the start of the thinking block
      local foldlevel = vim.fn.foldlevel(3)
      assert.is_true(foldlevel > 0, "Fold should exist at thinking block with signature")

      local foldclosed = vim.fn.foldclosed(3)
      assert.are.equal(3, foldclosed, "Thinking block with signature should be folded at line 3")
    end)
  end)

  describe("get_fold_text", function()
    ---Join chunk texts into a single string for content assertions
    ---@param chunks {[1]:string, [2]:string}[]
    ---@return string
    local function chunks_to_string(chunks)
      local parts = {}
      for _, chunk in ipairs(chunks) do
        table.insert(parts, chunk[1])
      end
      return table.concat(parts)
    end

    ---Find a chunk containing the given text pattern
    ---@param chunks {[1]:string, [2]:string}[]
    ---@param pattern string
    ---@return {[1]:string, [2]:string}|nil
    local function find_chunk(chunks, pattern)
      for _, chunk in ipairs(chunks) do
        if chunk[1]:match(pattern) then
          return chunk
        end
      end
      return nil
    end

    it("should return chunk list for folded tool_use block", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "I'll check that.",
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
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldtext = "v:lua.require('flemma.ui.folding').get_fold_text()"
      vim.wo.foldlevel = 99

      -- Close fold at tool_use block (lines 4-7)
      vim.cmd("4,7 foldclose")

      vim.v.foldstart = 4
      vim.v.foldend = 7
      local chunks = folding.get_fold_text()

      -- Should return a list of chunks, not a string
      assert.is_table(chunks, "get_fold_text should return a table of chunks")
      assert.is_table(chunks[1], "Each chunk should be a {text, hl_group} tuple")

      local text = chunks_to_string(chunks)
      assert.is_truthy(text:match("Tool Use: "), "Fold text should contain 'Tool Use: '")
      assert.is_truthy(text:match("bash"), "Fold text should contain tool name")
      assert.is_truthy(text:match("ls %-la"), "Fold text should contain command preview")
      assert.is_truthy(text:match("%(4 lines%)"), "Fold text should show line count")

      -- Verify highlight groups
      local icon_chunk = find_chunk(chunks, "⬡")
      assert.is_not_nil(icon_chunk, "Should have tool_use icon chunk")
      assert.are.equal("FlemmaToolIcon", icon_chunk[2])
      assert.is_nil(find_chunk(chunks, "⬢"), "tool_use should not use the tool_result icon")

      local title_chunk = find_chunk(chunks, "Tool Use:")
      assert.is_not_nil(title_chunk, "Should have title chunk")
      assert.are.equal("FlemmaToolUseTitle", title_chunk[2])

      local name_chunk = find_chunk(chunks, "^bash")
      assert.is_not_nil(name_chunk, "Should have name chunk")
      assert.are.equal("FlemmaToolName", name_chunk[2])

      local meta_chunk = chunks[#chunks]
      assert.is_truthy(meta_chunk[1]:match("%(4 lines%)"), "Last chunk should be line count")
      assert.are.equal("FlemmaFoldMeta", meta_chunk[2])
    end)

    it("should return chunk list for folded tool_result block", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "Checking.",
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
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldtext = "v:lua.require('flemma.ui.folding').get_fold_text()"
      vim.wo.foldlevel = 99

      -- Close fold at tool_result block (lines 11-16)
      vim.cmd("11,16 foldclose")

      vim.v.foldstart = 11
      vim.v.foldend = 16
      local chunks = folding.get_fold_text()

      assert.is_table(chunks, "get_fold_text should return a table of chunks")

      local text = chunks_to_string(chunks)
      assert.is_truthy(text:match("Tool Result: "), "Fold text should contain 'Tool Result: '")
      assert.is_truthy(text:match("bash"), "Fold text should contain tool name")
      assert.is_truthy(text:match("file1%.txt"), "Fold text should preview result content")
      assert.is_truthy(text:match("%(6 lines%)"), "Fold text should show line count")

      -- Verify highlight groups
      local icon_chunk = find_chunk(chunks, "⬢")
      assert.is_not_nil(icon_chunk, "Should have tool_result icon chunk")
      assert.are.equal("FlemmaToolIcon", icon_chunk[2])
      assert.is_nil(find_chunk(chunks, "⬡"), "tool_result should not use the tool_use icon")

      local title_chunk = find_chunk(chunks, "Tool Result:")
      assert.is_not_nil(title_chunk, "Should have title chunk")
      assert.are.equal("FlemmaToolResultTitle", title_chunk[2])

      local meta_chunk = chunks[#chunks]
      assert.is_truthy(meta_chunk[1]:match("%(6 lines%)"), "Last chunk should be line count")
      assert.are.equal("FlemmaFoldMeta", meta_chunk[2])
    end)

    it("should return chunk list for folded message", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You:",
        "What files are here?",
        "@Assistant:",
        "Let me check those files for you.",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldtext = "v:lua.require('flemma.ui.folding').get_fold_text()"
      vim.wo.foldlevel = 99

      vim.v.foldstart = 3
      vim.v.foldend = 4
      local chunks = folding.get_fold_text()

      assert.is_table(chunks, "get_fold_text should return a table of chunks")

      local text = chunks_to_string(chunks)
      assert.is_truthy(text:match("Assistant"), "Fold text should contain role name")

      -- Verify role highlight groups — with rulers enabled, the role name is a separate chunk
      local role_chunk = find_chunk(chunks, "Assistant")
      assert.is_not_nil(role_chunk, "Should have role chunk")
      assert.are.equal("FlemmaRoleAssistantName", role_chunk[2])

      local meta_chunk = chunks[#chunks]
      assert.are.equal("FlemmaFoldMeta", meta_chunk[2])
    end)

    it("uses fg-only role highlight for content chunks so line_hl_group bg shows through", function()
      -- Rationale: FlemmaUser/FlemmaSystem/FlemmaAssistant link to Normal/Special/Normal
      -- and inherit Normal's bg. Using them on fold-text chunks would stamp Normal bg
      -- over FlemmaLineUser/System/Assistant, creating visual discontinuity across a
      -- folded message. The fg-only FlemmaRole* variants let line_hl_group provide
      -- a uniform tint. Mirror of the pattern used by FlemmaThinkingFoldPreview.
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You:",
        "Hello, who are you?",
        "@Assistant:",
        "I am Claude.",
        "@System:",
        "You are a helpful assistant.",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldtext = "v:lua.require('flemma.ui.folding').get_fold_text()"
      vim.wo.foldlevel = 99

      ---Collect the hl groups of every chunk except the role name and the (N lines) suffix
      ---@param foldstart integer
      ---@param foldend integer
      ---@return string[]
      local function content_hls(foldstart, foldend)
        vim.v.foldstart = foldstart
        vim.v.foldend = foldend
        local chunks = folding.get_fold_text()
        local hls = {}
        for i, chunk in ipairs(chunks) do
          -- Skip ruler (i==1), role name (i==2), and final (N lines) suffix
          if i > 2 and i < #chunks then
            table.insert(hls, chunk[2])
          end
        end
        return hls
      end

      local you_hls = content_hls(1, 2)
      assert.is_true(#you_hls > 0, "@You fold should produce content chunks")
      for _, hl in ipairs(you_hls) do
        assert.are_not.equal("FlemmaUser", hl, "@You content must not use FlemmaUser (brings in Normal bg)")
      end
      assert.is_true(
        vim.tbl_contains(you_hls, "FlemmaRoleUser"),
        "@You fold should use fg-only FlemmaRoleUser for content chunks"
      )

      local asst_hls = content_hls(3, 4)
      for _, hl in ipairs(asst_hls) do
        assert.are_not.equal("FlemmaAssistant", hl, "@Assistant content must not use FlemmaAssistant")
      end
      assert.is_true(
        vim.tbl_contains(asst_hls, "FlemmaRoleAssistant"),
        "@Assistant fold should use fg-only FlemmaRoleAssistant for content chunks"
      )

      local sys_hls = content_hls(5, 6)
      for _, hl in ipairs(sys_hls) do
        assert.are_not.equal("FlemmaSystem", hl, "@System content must not use FlemmaSystem")
      end
      assert.is_true(
        vim.tbl_contains(sys_hls, "FlemmaRoleSystem"),
        "@System fold should use fg-only FlemmaRoleSystem for content chunks"
      )
    end)

    it("should return chunk list for folded thinking block", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "response",
        "<thinking>",
        "thinking content here",
        "</thinking>",
        "actual response",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldtext = "v:lua.require('flemma.ui.folding').get_fold_text()"
      vim.wo.foldlevel = 99

      vim.cmd("3,5 foldclose")

      vim.v.foldstart = 3
      vim.v.foldend = 5
      local chunks = folding.get_fold_text()

      assert.is_table(chunks, "get_fold_text should return a table of chunks")

      local text = chunks_to_string(chunks)
      assert.is_truthy(text:match("<thinking>"), "Should contain opening tag")
      assert.is_truthy(text:match("thinking content"), "Should contain preview")
      assert.is_truthy(text:match("</thinking>"), "Should contain closing tag")
      assert.is_truthy(text:match("%(3 lines%)"), "Should show line count")

      -- Verify highlight groups
      local tag_chunk = find_chunk(chunks, "<thinking")
      assert.is_not_nil(tag_chunk, "Should have thinking tag chunk")
      assert.are.equal("FlemmaThinkingTag", tag_chunk[2])

      local meta_chunk = chunks[#chunks]
      assert.are.equal("FlemmaFoldMeta", meta_chunk[2])
    end)
  end)

  describe("fold_completed_blocks", function()
    it("should fold completed tool_use and tool_result blocks", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "Checking.",
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
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99

      -- Call auto-fold
      folding.fold_completed_blocks(bufnr)

      -- Tool use block should be folded
      local tu_foldclosed = vim.fn.foldclosed(4)
      assert.are.equal(4, tu_foldclosed, "Tool use block should be folded at line 4")

      -- Tool result block should be folded
      local tr_foldclosed = vim.fn.foldclosed(11)
      assert.are.equal(11, tr_foldclosed, "Tool result block should be folded at line 11")
    end)

    it("should not fold pending tool blocks", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "Running.",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "```json",
        '{ "command": "ls" }',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01` (pending)",
        "",
        "```",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99

      folding.fold_completed_blocks(bufnr)

      -- Pending tool result should NOT be folded
      local foldclosed = vim.fn.foldclosed(10)
      assert.are.equal(-1, foldclosed, "Pending tool result should not be folded")
    end)

    it("should not escalate fold when block is already closed", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "Checking.",
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
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99

      -- Pre-close the tool_use fold
      vim.cmd("4,7 foldclose")

      -- Call auto-fold — should not escalate
      folding.fold_completed_blocks(bufnr)

      -- Message fold should remain open (not escalated by double-close)
      local msg_foldclosed = vim.fn.foldclosed(1)
      assert.are.equal(-1, msg_foldclosed, "Message fold should not be escalated")
    end)
  end)

  describe("auto_close configuration", function()
    it("should respect auto_close.thinking = false", function()
      -- Reconfigure with thinking auto-close disabled
      package.loaded["flemma"] = nil
      package.loaded["flemma.ui.folding"] = nil
      package.loaded["flemma.ui.folding.merge"] = nil
      package.loaded["flemma.ui.folding.rules.frontmatter"] = nil
      package.loaded["flemma.ui.folding.rules.thinking"] = nil
      package.loaded["flemma.ui.folding.rules.tool_blocks"] = nil
      package.loaded["flemma.ui.folding.rules.messages"] = nil
      package.loaded["flemma.ast"] = nil
      package.loaded["flemma.ast.nodes"] = nil
      package.loaded["flemma.ast.query"] = nil
      flemma = require("flemma")
      flemma.setup({ editing = { auto_close = { thinking = false } } })
      folding = require("flemma.ui.folding")

      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "response",
        "<thinking>",
        "thought process here",
        "</thinking>",
        "actual response",
        "@You:",
        "follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99

      folding.fold_completed_blocks(bufnr)

      -- Thinking block should remain open
      local foldclosed = vim.fn.foldclosed(2)
      assert.are.equal(-1, foldclosed, "Thinking block should remain open when auto_close.thinking = false")
    end)

    it("should respect auto_close.tool_use = false", function()
      package.loaded["flemma"] = nil
      package.loaded["flemma.ui.folding"] = nil
      package.loaded["flemma.ui.folding.merge"] = nil
      package.loaded["flemma.ui.folding.rules.frontmatter"] = nil
      package.loaded["flemma.ui.folding.rules.thinking"] = nil
      package.loaded["flemma.ui.folding.rules.tool_blocks"] = nil
      package.loaded["flemma.ui.folding.rules.messages"] = nil
      package.loaded["flemma.ast"] = nil
      package.loaded["flemma.ast.nodes"] = nil
      package.loaded["flemma.ast.query"] = nil
      flemma = require("flemma")
      flemma.setup({ editing = { auto_close = { tool_use = false, tool_result = false } } })
      folding = require("flemma.ui.folding")

      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "Checking.",
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
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99

      folding.fold_completed_blocks(bufnr)

      -- Tool blocks should remain open
      local tu_foldclosed = vim.fn.foldclosed(3)
      assert.are.equal(-1, tu_foldclosed, "Tool use block should remain open when auto_close.tool_use = false")

      local tr_foldclosed = vim.fn.foldclosed(10)
      assert.are.equal(-1, tr_foldclosed, "Tool result block should remain open when auto_close.tool_result = false")
    end)

    it("should not re-close a fold that was already auto-closed", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "response",
        "<thinking>",
        "thought process here",
        "</thinking>",
        "actual response",
        "@You:",
        "follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99

      -- First call: should auto-close the thinking block
      folding.fold_completed_blocks(bufnr)
      assert.are.equal(3, vim.fn.foldclosed(3), "Thinking block should be folded after first call")

      -- User opens the fold manually
      vim.cmd("3 foldopen")
      assert.are.equal(-1, vim.fn.foldclosed(3), "Thinking block should be open after user opens it")

      -- Second call: should NOT re-close because the ID is already in auto_closed_folds
      folding.fold_completed_blocks(bufnr)
      assert.are.equal(-1, vim.fn.foldclosed(3), "Thinking block should stay open after second auto-close call")
    end)
  end)

  describe("highest foldlevel wins", function()
    it("should keep >2 when messages rule runs after thinking rule on same line", function()
      -- This test validates that the fold map uses highest-foldlevel-wins
      -- rather than first-writer-wins. If a thinking block starts on the
      -- same line that a message starts, >2 should beat >1 regardless of
      -- rule evaluation order.
      local utils = require("flemma.ui.folding.merge")
      local fold_map = {}

      -- Simulate messages rule writing >1 first
      utils.set_fold(fold_map, 5, ">1")
      -- Then thinking rule writes >2 on the same line
      utils.set_fold(fold_map, 5, ">2")

      assert.are.equal(">2", fold_map[5])
    end)

    it("should not downgrade >2 to >1", function()
      local utils = require("flemma.ui.folding.merge")
      local fold_map = {}

      -- Higher level first
      utils.set_fold(fold_map, 10, ">2")
      -- Lower level attempt
      utils.set_fold(fold_map, 10, ">1")

      assert.are.equal(">2", fold_map[10])
    end)

    it("should keep <2 over <1 on the same line", function()
      local utils = require("flemma.ui.folding.merge")
      local fold_map = {}

      utils.set_fold(fold_map, 7, "<1")
      utils.set_fold(fold_map, 7, "<2")

      assert.are.equal("<2", fold_map[7])
    end)
  end)

  describe("registry", function()
    it("should register a custom fold rule", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You:",
        "question",
        "@Assistant:",
        "response",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Register a custom rule that marks line 2 at level 3
      folding.register({
        name = "custom",
        auto_close = false,
        populate = function(_, fold_map)
          local utils = require("flemma.ui.folding.merge")
          utils.set_fold(fold_map, 2, ">3")
        end,
        get_closeable_ranges = function(_)
          return {}
        end,
      })

      -- The custom rule's >3 should beat the messages rule's >1 on line 2
      local fold_level = folding.get_fold_level(2)
      assert.are.equal(">3", fold_level)
    end)

    it("should invalidate cache when a rule is registered after first evaluation", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You:",
        "question",
        "@Assistant:",
        "response",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Prime the cache — only builtins are registered at this point
      assert.are.equal(">1", folding.get_fold_level(1))

      -- Register a rule that overrides line 2 AFTER cache was built
      folding.register({
        name = "late_override",
        auto_close = false,
        populate = function(_, fold_map)
          local utils = require("flemma.ui.folding.merge")
          utils.set_fold(fold_map, 2, ">3")
        end,
        get_closeable_ranges = function(_)
          return {}
        end,
      })

      -- Must see the new rule's effect despite the cache being primed earlier
      assert.are.equal(">3", folding.get_fold_level(2))
    end)

    it("should load built-in rules lazily", function()
      -- Clear and re-require to reset state
      package.loaded["flemma.ui.folding"] = nil
      package.loaded["flemma.ui.folding.merge"] = nil
      package.loaded["flemma.ui.folding.rules.frontmatter"] = nil
      package.loaded["flemma.ui.folding.rules.thinking"] = nil
      package.loaded["flemma.ui.folding.rules.tool_blocks"] = nil
      package.loaded["flemma.ui.folding.rules.messages"] = nil
      package.loaded["flemma.ast"] = nil
      package.loaded["flemma.ast.nodes"] = nil
      package.loaded["flemma.ast.query"] = nil
      local fresh_folding = require("flemma.ui.folding")

      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You:",
        "question",
        "@Assistant:",
        "response",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Built-in rules should be loaded on first call to get_fold_level
      local fold_level = fresh_folding.get_fold_level(1)
      assert.are.equal(">1", fold_level)
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
        "@You:",
        "What files are in this directory?",
        "",
        "@Assistant:",
        "Let me check.",
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
        "@Assistant:",
        "There are two files: file1.txt and file2.txt.",
        "",
        "@You:",
        "Thanks!",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.conceallevel = 0
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 1

      -- With foldlevel=1:
      -- Frontmatter should be folded (level 2)
      assert.are_not.equal(-1, vim.fn.foldclosed(1), "Frontmatter should be folded")
      -- Thinking should be folded (level 2)
      assert.are_not.equal(-1, vim.fn.foldclosed(10), "Thinking should be folded")
      -- Tool use should be folded (level 2)
      assert.are_not.equal(-1, vim.fn.foldclosed(14), "Tool use should be folded")
      -- Tool result should be folded (level 2)
      assert.are_not.equal(-1, vim.fn.foldclosed(21), "Tool result should be folded")
      -- Messages should be open (level 1)
      assert.are.equal(-1, vim.fn.foldclosed(5), "User message should be open")
      assert.are.equal(-1, vim.fn.foldclosed(8), "Assistant message should be open")
      assert.are.equal(-1, vim.fn.foldclosed(28), "Final assistant message should be open")
    end)
  end)

  describe("rule registry", function()
    it("get() returns a rule by name", function()
      local rule = folding.get("thinking")
      assert.is_not_nil(rule)
      assert.are.equal("thinking", rule.name)
    end)

    it("get() returns nil for unknown name", function()
      assert.is_nil(folding.get("nonexistent"))
    end)

    it("get_all() returns ordered copy of all rules", function()
      local all = folding.get_all()
      assert.are.equal(4, #all)
      -- Verify it is a copy
      all[1] = nil
      assert.is_not_nil(folding.get_all()[1])
    end)

    it("has() returns true for built-in rules", function()
      assert.is_true(folding.has("frontmatter"))
      assert.is_true(folding.has("thinking"))
      assert.is_true(folding.has("tool_blocks"))
      assert.is_true(folding.has("messages"))
    end)

    it("has() returns false for unknown name", function()
      assert.is_false(folding.has("nonexistent"))
    end)

    it("unregister() removes a rule and returns true", function()
      assert.is_true(folding.unregister("thinking"))
      assert.is_false(folding.has("thinking"))
      assert.are.equal(3, folding.count())
    end)

    it("unregister() returns false for unknown name", function()
      assert.is_false(folding.unregister("nonexistent"))
    end)

    it("count() returns the number of built-in rules", function()
      assert.are.equal(4, folding.count())
    end)
  end)

  describe("update_ui changedtick stability", function()
    it("should not change changedtick when update_ui is called on an unchanged buffer", function()
      local ui = require("flemma.ui")

      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "Checking.",
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
        "",
        "@Assistant:",
        "Here are the files.",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Set up in a window with folding
      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      folding.setup_folding()

      -- First update_ui call to establish baseline
      ui.update_ui(bufnr)
      local tick_after_first = vim.api.nvim_buf_get_changedtick(bufnr)

      -- Second update_ui call on unchanged buffer
      ui.update_ui(bufnr)
      local tick_after_second = vim.api.nvim_buf_get_changedtick(bufnr)

      assert.are.equal(
        tick_after_first,
        tick_after_second,
        "update_ui should not change changedtick on an unchanged buffer"
      )
    end)

    it("CursorHold guard should prevent redundant fold_completed_blocks calls", function()
      local ui = require("flemma.ui")
      local state = require("flemma.state")

      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "Checking.",
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
      folding.setup_folding()

      -- Simulate the CursorHold pattern:
      -- 1. Read tick before update_ui
      local tick_before = vim.api.nvim_buf_get_changedtick(bufnr)
      -- 2. Call update_ui (as the autocmd does)
      ui.update_ui(bufnr)
      -- 3. Read tick after update_ui
      local tick_after = vim.api.nvim_buf_get_changedtick(bufnr)

      -- 4. Store ui_update_tick as the autocmd does (using the PRE-update tick)
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.ui_update_tick = tick_before

      -- 5. Simulate next CursorHold: check guard
      local tick_now = vim.api.nvim_buf_get_changedtick(bufnr)
      local guard_would_skip = (buffer_state.ui_update_tick == tick_now)

      -- If update_ui changed changedtick, the guard fails
      -- (ui_update_tick holds the pre-update tick, tick_now holds the post-update tick)
      assert.is_true(
        guard_would_skip,
        string.format(
          "CursorHold guard should skip redundant update_ui calls "
            .. "(ui_update_tick=%d, current_tick=%d, tick_before=%d, tick_after=%d)",
          buffer_state.ui_update_tick,
          tick_now,
          tick_before,
          tick_after
        )
      )
    end)

    it("fold_completed_blocks should skip when called twice on the same buffer state", function()
      local state = require("flemma.state")

      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "Checking.",
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
      folding.setup_folding()

      -- First call: should process folds normally
      folding.fold_completed_blocks(bufnr)
      local tool_use_folded = vim.fn.foldclosed(4)
      assert.are.equal(4, tool_use_folded, "Tool use should be folded after first call")

      -- Open the fold manually and clear auto_closed_folds tracking
      -- This isolates the changedtick guard from the per-fold dedup
      vim.cmd("4 foldopen")
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.auto_closed_folds = {}

      -- Second call on same changedtick: should return early (fold_completed_tick guard)
      -- WITHOUT the guard, the function would re-iterate rules, find the range
      -- again, and re-close the fold (since auto_closed_folds was cleared)
      folding.fold_completed_blocks(bufnr)

      -- If the guard works, the fold stays open (function returned early)
      -- If guard is missing, the fold gets re-closed (function re-executed fully)
      assert.are.equal(-1, vim.fn.foldclosed(4), "fold_completed_blocks should skip when changedtick has not changed")
    end)
  end)

  describe("fold auto-close retry on failure", function()
    -- These tests simulate the race condition where fold evaluation hasn't
    -- completed when safe_foldclose runs. We set foldmethod=manual right
    -- before calling fold_completed_blocks — this drops all fold
    -- information (foldlevel() returns 0), simulating the state between
    -- when Neovim receives "set foldmethod=expr" and when fold evaluation
    -- actually completes for off-screen lines.

    it("should not mark a fold as closed when foldclose silently fails", function()
      local state = require("flemma.state")
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "response",
        "<thinking>",
        "thought process here",
        "</thinking>",
        "actual response",
        "@You:",
        "follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      folding.setup_folding()
      vim.wo.foldlevel = 99

      -- Sabotage: switch to manual foldmethod and delete all folds.
      -- This simulates the race where fold evaluation hasn't completed
      -- yet — foldlevel() returns 0 for all lines.
      vim.wo.foldmethod = "manual"
      vim.cmd("normal! zE")
      assert.are.equal(0, vim.fn.foldlevel(3), "Sanity: manual foldmethod should have foldlevel 0")

      -- Call fold_completed_blocks — safe_foldclose should bail because
      -- foldlevel() returns 0 (no evaluated folds)
      folding.fold_completed_blocks(bufnr)

      -- The fold is NOT closed (no folds exist in manual mode)
      assert.are.equal(-1, vim.fn.foldclosed(3), "Fold should not be closed (no fold evaluation)")

      -- Critical: the fold should NOT be in auto_closed_folds
      local buffer_state = state.get_buffer_state(bufnr)
      local fold_id = "thinking:1" -- message_index for second-to-last message
      assert.is_falsy(
        buffer_state.auto_closed_folds and buffer_state.auto_closed_folds[fold_id],
        "Failed foldclose should NOT mark fold as closed in auto_closed_folds"
      )
    end)

    it("should retry pending folds on subsequent calls even on the same changedtick", function()
      local state = require("flemma.state")
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "response",
        "<thinking>",
        "thought process here",
        "</thinking>",
        "actual response",
        "@You:",
        "follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      folding.setup_folding()
      vim.wo.foldlevel = 99

      -- Sabotage: drop fold information to simulate the race condition
      vim.wo.foldmethod = "manual"
      vim.cmd("normal! zE")

      -- First call: foldlevel() returns 0, safe_foldclose bails
      folding.fold_completed_blocks(bufnr)
      assert.are.equal(-1, vim.fn.foldclosed(3), "Fold should not be closed (no fold evaluation)")

      -- Restore foldmethod=expr (simulating fold evaluation completing)
      -- Keep foldlevel=99 so folds stay OPEN — we need fold_completed_blocks
      -- to close them, not Neovim's foldlevel mechanism.
      folding.setup_folding()
      vim.wo.foldlevel = 99
      assert.are.equal(-1, vim.fn.foldclosed(3), "Sanity: fold should be open after setup with foldlevel=99")

      -- Second call on same changedtick: should RETRY because the fold is still pending
      folding.fold_completed_blocks(bufnr)
      assert.are.equal(3, vim.fn.foldclosed(3), "Pending fold should be retried and closed on subsequent call")

      -- Now it should be in auto_closed_folds
      local buffer_state = state.get_buffer_state(bufnr)
      local fold_id = "thinking:1"
      assert.is_truthy(
        buffer_state.auto_closed_folds and buffer_state.auto_closed_folds[fold_id],
        "Successfully closed fold should be marked in auto_closed_folds"
      )
    end)

    it("should still skip same-tick calls when all folds are successfully closed", function()
      local state = require("flemma.state")
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "response",
        "<thinking>",
        "thought process here",
        "</thinking>",
        "actual response",
        "@You:",
        "follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      folding.setup_folding()

      -- First call: folds close successfully
      folding.fold_completed_blocks(bufnr)
      assert.are.equal(3, vim.fn.foldclosed(3), "Thinking block should be folded")

      -- User opens the fold manually and clear tracking to isolate the tick guard
      vim.cmd("3 foldopen")
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.auto_closed_folds = {}

      -- Second call on same changedtick: should skip because no pending folds
      -- (all folds succeeded on the first call, pending set was cleared)
      folding.fold_completed_blocks(bufnr)
      assert.are.equal(-1, vim.fn.foldclosed(3), "Same-tick call should skip when no pending folds exist")
    end)

    it("should fold when returning to a buffer that had no window during streaming", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "response",
        "<thinking>",
        "thought process here",
        "</thinking>",
        "actual response",
        "@You:",
        "follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Simulate: fold_completed_blocks is called while buffer has NO window
      -- (user switched tabs during streaming). bufwinid returns -1.
      -- Don't display the buffer in any window — just call fold_completed_blocks.
      folding.fold_completed_blocks(bufnr)

      -- Now simulate returning to the tab: show the buffer in a window
      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      folding.setup_folding()
      vim.wo.foldlevel = 99

      -- Call fold_completed_blocks again on the SAME changedtick.
      -- This simulates BufWinEnter -> update_ui -> fold_completed_blocks.
      -- It should NOT skip even though changedtick hasn't changed.
      folding.fold_completed_blocks(bufnr)
      assert.are.equal(3, vim.fn.foldclosed(3), "Thinking fold should be closed after returning to buffer")
    end)
  end)

  describe("fold re-close after undo/redo", function()
    -- KNOWN ISSUE (unfixed): when a user edits lines overlapping a folded
    -- region and then undoes, Neovim reopens the fold — its open/closed
    -- state cannot survive structural edits to the boundary lines. The
    -- auto_closed_folds tracker then blocks the re-close because the fold
    -- ID is still marked as "already closed once" for this buffer session.
    --
    -- A naive "clear tracker on undo/redo" fix was explored and rejected:
    -- the tracker exists specifically to remember user `zo` intent, and
    -- clearing it causes ALL user-opened folds to snap shut on the next
    -- CursorHold — worse than the original bug. A correct fix needs to
    -- distinguish "Neovim reopened this specific fold because undo touched
    -- its boundary" from "user opened this with zo earlier." Neovim offers
    -- no FoldToggled autocmd, so the distinction requires either diffing
    -- per-fold state across the undo, or tracking user-open intent via
    -- keymap overrides on zo/zc/zO/zM/zR/etc. Both are larger changes.
    --
    -- These tests document the desired behavior and are marked `pending`
    -- until the proper fix lands.

    local function skip_until_fix()
      pending("requires per-fold user-intent tracking; see describe block comment")
      return true
    end

    it("should re-close a fold that was reopened by undo", function()
      if skip_until_fix() then
        return
      end
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You:",
        "Hello",
        "",
        "@Assistant:",
        "answer",
        "",
        '<thinking vertex:signature="sig2">',
        "</thinking>",
        "",
        "@You:",
        "follow",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      folding.setup_folding()
      vim.wo.foldlevel = 99
      vim.bo[bufnr].undolevels = 1000

      -- Baseline: thinking fold at line 7 auto-closes.
      folding.fold_completed_blocks(bufnr)
      assert.are.equal(7, vim.fn.foldclosed(7), "Thinking fold should be closed initially")

      -- Destructive edit inside the fold: dd the <thinking> open line.
      -- Neovim reopens the fold because its boundary was touched.
      vim.api.nvim_win_set_cursor(0, { 7, 0 })
      vim.cmd("normal! dd")
      vim.cmd("silent! undo")
      assert.are.equal(-1, vim.fn.foldclosed(7), "Neovim reopens fold after undo (precondition)")

      -- fold_completed_blocks must re-close: the tracker should have been
      -- cleared once undo regression was detected.
      folding.fold_completed_blocks(bufnr)
      assert.are.equal(7, vim.fn.foldclosed(7), "Thinking fold should be re-closed after undo")
    end)

    it("should re-close a fold that was reopened by redo", function()
      if skip_until_fix() then
        return
      end
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You:",
        "Hello",
        "",
        "@Assistant:",
        "answer",
        "",
        '<thinking vertex:signature="sig2">',
        "</thinking>",
        "",
        "@You:",
        "follow",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      folding.setup_folding()
      vim.wo.foldlevel = 99
      vim.bo[bufnr].undolevels = 1000

      folding.fold_completed_blocks(bufnr)
      assert.are.equal(7, vim.fn.foldclosed(7), "Thinking fold should be closed initially")

      -- Make an edit that Neovim can redo.
      vim.api.nvim_win_set_cursor(0, { 7, 0 })
      vim.cmd("normal! dd")
      -- After dd the fold is gone; re-close it via the fix path first.
      folding.fold_completed_blocks(bufnr)
      vim.cmd("silent! undo")
      folding.fold_completed_blocks(bufnr)
      assert.are.equal(7, vim.fn.foldclosed(7), "Sanity: fold re-closed after undo")

      -- Now redo — fold gets reopened again.
      vim.cmd("silent! redo")
      vim.cmd("silent! undo")
      assert.are.equal(-1, vim.fn.foldclosed(7), "Undo after redo reopens the fold (precondition)")

      folding.fold_completed_blocks(bufnr)
      assert.are.equal(7, vim.fn.foldclosed(7), "Thinking fold should be re-closed after redo path")
    end)

    it("should not clear the tracker on a normal forward edit", function()
      -- Guard: on normal typing, the tracker must persist so that a
      -- user-opened fold (via zo) is NOT re-closed on the next pass.
      local state = require("flemma.state")
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You:",
        "Hello",
        "",
        "@Assistant:",
        "answer",
        "",
        '<thinking vertex:signature="sig2">',
        "</thinking>",
        "",
        "@You:",
        "follow",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      folding.setup_folding()
      vim.wo.foldlevel = 99
      vim.bo[bufnr].undolevels = 1000

      folding.fold_completed_blocks(bufnr)
      assert.are.equal(7, vim.fn.foldclosed(7), "Fold should be closed initially")

      -- User opens the fold, then types far away. Tracker must NOT clear.
      vim.cmd("7 foldopen")
      vim.api.nvim_win_set_cursor(0, { 11, 7 })
      vim.cmd("normal! aabc")

      folding.fold_completed_blocks(bufnr)
      assert.are.equal(-1, vim.fn.foldclosed(7), "Fold should remain user-opened across forward edits")

      local buffer_state = state.get_buffer_state(bufnr)
      assert.is_truthy(
        buffer_state.auto_closed_folds and buffer_state.auto_closed_folds["thinking:2"],
        "Tracker must retain the fold ID across forward edits"
      )
    end)
  end)

  describe("toggle_message_fold", function()
    it("should close the message fold when cursor is inside an open message", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You:",
        "hello",
        "@Assistant:",
        "line one",
        "line two",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99

      -- Cursor on line 4 (inside @Assistant: message body)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      folding.toggle_message_fold()

      assert.are.equal(3, vim.fn.foldclosed(3), "Message fold should be closed at @Assistant: line")
    end)

    it("should open the message fold when cursor is on a closed fold", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You:",
        "hello",
        "@Assistant:",
        "response",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99

      -- Close the assistant message manually, then toggle to reopen
      vim.cmd("3 foldclose")
      assert.are.equal(3, vim.fn.foldclosed(3), "Sanity: message should be closed")

      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      folding.toggle_message_fold()

      assert.are.equal(-1, vim.fn.foldclosed(3), "Message fold should be open after toggle")
    end)

    it("should close message even when cursor is on a closed sub-fold", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You:",
        "question",
        "@Assistant:",
        "<thinking>",
        "reasoning",
        "</thinking>",
        "answer",
        "@You:",
        "follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99

      -- Close the thinking block (level 2), leave message open
      vim.cmd("4,6 foldclose")
      assert.are.equal(4, vim.fn.foldclosed(4), "Sanity: thinking fold should be closed")
      assert.are.equal(-1, vim.fn.foldclosed(3), "Sanity: message fold should be open")

      -- Cursor on the closed thinking fold line — Space should close the message, not open thinking
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      folding.toggle_message_fold()

      assert.are.equal(3, vim.fn.foldclosed(3), "Message fold should be closed, not thinking toggled")
    end)

    it("should close nested folds when closing a message", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You:",
        "question",
        "@Assistant:",
        "<thinking>",
        "reasoning",
        "</thinking>",
        "answer",
        "@You:",
        "follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99

      -- Thinking block is open, message is open
      assert.are.equal(-1, vim.fn.foldclosed(4), "Sanity: thinking should be open")

      -- Close the message via toggle
      vim.api.nvim_win_set_cursor(0, { 5, 0 })
      folding.toggle_message_fold()
      assert.are.equal(3, vim.fn.foldclosed(3), "Message should be closed")

      -- Reopen the message — thinking should have been closed along the way
      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      folding.toggle_message_fold()
      assert.are.equal(-1, vim.fn.foldclosed(3), "Message should be open")
      assert.are.equal(4, vim.fn.foldclosed(4), "Thinking should remain closed after reopen")
    end)

    it("should close tool use sub-folds when closing a message", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You:",
        "question",
        "@Assistant:",
        "**Tool Use:** `bash` (`call_001`)",
        "```json",
        '{"command": "ls"}',
        "```",
        "some text",
        "@You:",
        "**Tool Result:** `call_001`",
        "",
        "```",
        "file1.txt",
        "```",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99

      -- Tool use fold should be open
      assert.are.equal(-1, vim.fn.foldclosed(4), "Sanity: tool use should be open")

      -- Close the assistant message
      vim.api.nvim_win_set_cursor(0, { 5, 0 })
      folding.toggle_message_fold()
      assert.are.equal(3, vim.fn.foldclosed(3), "Assistant message should be closed")

      -- Reopen — tool use sub-fold should be closed
      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      folding.toggle_message_fold()
      assert.are.equal(-1, vim.fn.foldclosed(3), "Message should be open")
      assert.are.equal(4, vim.fn.foldclosed(4), "Tool use should remain closed after reopen")
    end)

    it("should toggle frontmatter fold when cursor is on frontmatter", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "```lua",
        "-- config",
        "```",
        "@System:",
        "prompt",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.conceallevel = 0
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99

      assert.are.equal(-1, vim.fn.foldclosed(1), "Sanity: frontmatter should be open")

      -- Close frontmatter via toggle
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      folding.toggle_message_fold()
      assert.are.equal(1, vim.fn.foldclosed(1), "Frontmatter should be closed")

      -- Reopen via toggle
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      folding.toggle_message_fold()
      assert.are.equal(-1, vim.fn.foldclosed(1), "Frontmatter should be open after toggle")
    end)

    it("should do nothing when cursor is outside any message", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99

      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      -- Should not error
      folding.toggle_message_fold()
    end)

    it("should notify (not error) when toggling frontmatter at conceallevel>=1", function()
      local notify = require("flemma.notify")
      local captured = {}
      notify._set_impl(function(notification)
        table.insert(captured, notification)
        return notification
      end)

      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "```lua",
        "-- config",
        "```",
        "@System:",
        "prompt",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.conceallevel = 2
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99

      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      -- Must not throw Vim(foldclose):E490
      assert.has_no.errors(function()
        folding.toggle_message_fold()
      end)

      -- Give the scheduled dispatch time to run
      vim.wait(10, function()
        return false
      end)

      assert.are.equal(1, #captured, "expected one notify dispatch")
      assert.are.equal(vim.log.levels.INFO, captured[1].level)
      assert.is_truthy(
        captured[1].message:find("conceallevel=2"),
        "notify message should cite the active conceallevel: " .. captured[1].message
      )
      assert.is_truthy(
        captured[1].message:find("Neovim limitation"),
        "notify message should attribute to Neovim: " .. captured[1].message
      )

      notify._reset_impl()
    end)
  end)
end)
