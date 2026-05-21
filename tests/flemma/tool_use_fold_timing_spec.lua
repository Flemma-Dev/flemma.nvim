describe("Tool Use auto-close timing", function()
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
    package.loaded["flemma.state"] = nil
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

  local function setup_fold_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.bo[bufnr].filetype = "chat"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.cmd("new")
    vim.api.nvim_set_current_buf(bufnr)
    vim.wo.foldmethod = "expr"
    vim.wo.foldexpr = "v:lua.require('flemma.ui.folding').get_fold_level(v:lnum)"
    vim.wo.foldlevel = 99
    return bufnr
  end

  describe("simultaneous tool_use + tool_result folding", function()
    it("should fold tool_use at the same time as tool_result", function()
      local bufnr = setup_fold_buffer({
        "@You:",
        "Run a command",
        "",
        "@Assistant:",
        "",
        "**Tool Use:** `bash` (`toolu_01`)",
        "",
        "```json",
        '{"command":"echo hello"}',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_01`",
        "",
        "```",
        "hello",
        "```",
        "",
        "@Assistant:",
        "Done!",
        "",
        "@You:",
        "",
      })

      folding.fold_completed_blocks(bufnr)

      assert.are.equal(6, vim.fn.foldclosed(6), "tool_use block should be auto-closed")
      assert.are.equal(14, vim.fn.foldclosed(14), "tool_result block should be auto-closed")
    end)

    it("should fold tool_use when result is injected into a previously-open buffer", function()
      local bufnr = setup_fold_buffer({
        "@You:",
        "Run a command",
        "",
        "@Assistant:",
        "",
        "**Tool Use:** `bash` (`toolu_02`)",
        "",
        "```json",
        '{"command":"echo hello"}',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_02` (pending)",
        "",
        "```",
        "```",
        "",
      })

      vim.cmd("redraw")
      folding.fold_completed_blocks(bufnr)
      assert.are.equal(-1, vim.fn.foldclosed(6), "tool_use should be open while result is pending")

      vim.api.nvim_buf_set_lines(bufnr, 13, 17, false, {
        "**Tool Result:** `toolu_02`",
        "",
        "```",
        "hello",
        "```",
      })

      folding.invalidate_folds(bufnr)
      folding.fold_completed_blocks(bufnr)

      assert.are.equal(6, vim.fn.foldclosed(6), "tool_use should be auto-closed after result injection")
      assert.are.equal(14, vim.fn.foldclosed(14), "tool_result should be auto-closed after injection")
    end)

    it("should fold both blocks after update_ui sequence with extmarks", function()
      local bufnr = setup_fold_buffer({
        "@You:",
        "test",
        "",
        "@Assistant:",
        "",
        "**Tool Use:** `read` (`toolu_03`)",
        "",
        "```json",
        '{"path":"foo.txt"}',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `toolu_03` (pending)",
        "",
        "```",
        "```",
        "",
      })

      vim.cmd("redraw")

      vim.api.nvim_buf_set_lines(bufnr, 13, 17, false, {
        "**Tool Result:** `toolu_03`",
        "",
        "```",
        "file contents here",
        "```",
      })

      local ui = require("flemma.ui")
      local parser = require("flemma.parser")
      local doc = parser.get_parsed_document(bufnr)
      ui.add_rulers(bufnr, doc)
      ui.highlight_thinking_tags(bufnr, doc)
      ui.apply_line_highlights(bufnr, doc)
      ui.add_tool_previews(bufnr, doc)

      folding.invalidate_folds(bufnr)
      folding.fold_completed_blocks(bufnr)

      assert.are.equal(6, vim.fn.foldclosed(6), "tool_use should auto-close even after extmark operations")
      assert.are.equal(14, vim.fn.foldclosed(14), "tool_result should auto-close even after extmark operations")
    end)
  end)
end)
