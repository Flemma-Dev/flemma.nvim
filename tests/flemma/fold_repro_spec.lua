describe("Folding: empty and self-closing thinking blocks", function()
  local flemma
  local folding

  before_each(function()
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
    vim.cmd("silent! %bdelete!")
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  describe("self-closing thinking tag", function()
    it("should not create fold levels for self-closing tag (start_line == end_line)", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "response text",
        '<thinking vertex:signature="abc123"/>',
        "",
        "@You:",
        "follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Self-closing tag on line 3 should NOT create >2 (would leave unclosed fold)
      local level_3 = folding.get_fold_level(3)
      assert.are_not.equal(">2", level_3, "Self-closing thinking tag must not create >2 fold start")

      -- Message boundaries must still work
      assert.are.equal(">1", folding.get_fold_level(1), "@Assistant: should start message fold")
      assert.are.equal(">1", folding.get_fold_level(5), "@You: should start message fold")
    end)

    it("should not corrupt fold levels for lines after self-closing tag", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "response",
        '<thinking vertex:signature="abc123"/>',
        "",
        "@You:",
        "question",
        "@Assistant:",
        "answer",
        "<thinking>",
        "actual thinking content",
        "</thinking>",
        "",
        "@You:",
        "more",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Normal thinking block at lines 9-11 should still fold correctly
      assert.are.equal(">2", folding.get_fold_level(9), "Normal thinking open should be >2")
      assert.are.equal("<2", folding.get_fold_level(11), "Normal thinking close should be <2")

      -- All message boundaries must work
      assert.are.equal(">1", folding.get_fold_level(5), "@You: at line 5")
      assert.are.equal(">1", folding.get_fold_level(7), "@Assistant: at line 7")
      assert.are.equal(">1", folding.get_fold_level(13), "@You: at line 13")
    end)

    it("should not include self-closing tag in closeable ranges", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "response",
        '<thinking vertex:signature="abc123"/>',
        "@You:",
        "follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      local parser = require("flemma.parser")
      local doc = parser.get_parsed_document(bufnr)
      local thinking_rule = folding.get("thinking")
      local ranges = thinking_rule.get_closeable_ranges(doc)

      assert.are.equal(0, #ranges, "Self-closing thinking tag should not produce closeable ranges")
    end)
  end)

  describe("empty 2-line thinking block", function()
    it("should create proper fold for empty thinking block (open + close tags)", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "response",
        '<thinking vertex:signature="abc123">',
        "</thinking>",
        "",
        "@You:",
        "follow up",
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      assert.are.equal(">2", folding.get_fold_level(3), "Empty thinking open tag should start fold")
      assert.are.equal("<2", folding.get_fold_level(4), "Empty thinking close tag should end fold")
      assert.are.equal(">1", folding.get_fold_level(6), "@You: should start message fold")
    end)

    it("should auto-close empty 2-line thinking block", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@Assistant:",
        "response",
        '<thinking vertex:signature="abc123">',
        "</thinking>",
        "",
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

      local foldclosed = vim.fn.foldclosed(3)
      assert.are.equal(3, foldclosed, "Empty 2-line thinking block should be auto-closed")
    end)
  end)

  describe("example.chat reproduction: multiple empty thinking blocks with tool calls", function()
    it("should maintain correct fold levels", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You:", -- 1
        "Hello", -- 2
        "", -- 3
        "@Assistant:", -- 4
        "", -- 5
        "**Tool Use:** `bash` (`urn:flemma:tool:bash:id1`)", -- 6
        "", -- 7
        "```json", -- 8
        '{"command":"echo hi","label":"test","timeout":30}', -- 9
        "```", -- 10
        "", -- 11
        '<thinking vertex:signature="sig1">', -- 12
        "</thinking>", -- 13
        "", -- 14
        "@You:", -- 15
        "", -- 16
        "**Tool Result:** `urn:flemma:tool:bash:id1`", -- 17
        "", -- 18
        "```", -- 19
        "hi", -- 20
        "```", -- 21
        "", -- 22
        "@Assistant:", -- 23
        "The command worked!", -- 24
        "", -- 25
        '<thinking vertex:signature="sig2">', -- 26
        "</thinking>", -- 27
        "", -- 28
        "@You:", -- 29
        "Great", -- 30
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      -- Message boundaries
      assert.are.equal(">1", folding.get_fold_level(1), "@You: line 1")
      assert.are.equal(">1", folding.get_fold_level(4), "@Assistant: line 4")
      assert.are.equal(">1", folding.get_fold_level(15), "@You: line 15")
      assert.are.equal(">1", folding.get_fold_level(23), "@Assistant: line 23")
      assert.are.equal(">1", folding.get_fold_level(29), "@You: line 29")

      -- Empty thinking blocks
      assert.are.equal(">2", folding.get_fold_level(12), "thinking open at 12")
      assert.are.equal("<2", folding.get_fold_level(13), "thinking close at 13")
      assert.are.equal(">2", folding.get_fold_level(26), "thinking open at 26")
      assert.are.equal("<2", folding.get_fold_level(27), "thinking close at 27")

      -- Message end lines
      assert.are.equal("<1", folding.get_fold_level(3), "end of first @You")
      assert.are.equal("<1", folding.get_fold_level(14), "end of first @Assistant")
      assert.are.equal("<1", folding.get_fold_level(28), "end of second @Assistant")
      assert.are.equal("<1", folding.get_fold_level(30), "end of last @You")
    end)

    it("should auto-close all completed blocks", function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      vim.bo[bufnr].filetype = "chat"

      local lines = {
        "@You:", -- 1
        "Hello", -- 2
        "", -- 3
        "@Assistant:", -- 4
        "", -- 5
        "**Tool Use:** `bash` (`urn:flemma:tool:bash:id1`)", -- 6
        "", -- 7
        "```json", -- 8
        '{"command":"echo hi","label":"test","timeout":30}', -- 9
        "```", -- 10
        "", -- 11
        '<thinking vertex:signature="sig1">', -- 12
        "</thinking>", -- 13
        "", -- 14
        "@You:", -- 15
        "", -- 16
        "**Tool Result:** `urn:flemma:tool:bash:id1`", -- 17
        "", -- 18
        "```", -- 19
        "hi", -- 20
        "```", -- 21
        "", -- 22
        "@Assistant:", -- 23
        "The command worked!", -- 24
        "", -- 25
        '<thinking vertex:signature="sig2">', -- 26
        "</thinking>", -- 27
        "", -- 28
        "@You:", -- 29
        "Great", -- 30
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.wo.foldmethod = "expr"
      vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
      vim.wo.foldlevel = 99

      folding.fold_completed_blocks(bufnr)

      -- Completed tool_use should be folded
      assert.are.equal(6, vim.fn.foldclosed(6), "Completed tool_use should be auto-closed")

      -- Terminal tool_result should be folded
      assert.are.equal(17, vim.fn.foldclosed(17), "Terminal tool_result should be auto-closed")

      -- Empty thinking block in second-to-last assistant msg should be folded
      assert.are.equal(26, vim.fn.foldclosed(26), "Empty thinking in second-to-last msg should be auto-closed")
    end)
  end)
end)
