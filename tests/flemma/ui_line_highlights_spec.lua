describe("UI Line Highlights", function()
  local flemma
  local ui
  local parser

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.ui"] = nil
    package.loaded["flemma.parser"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.state"] = nil

    flemma = require("flemma")
    ui = require("flemma.ui")
    parser = require("flemma.parser")

    flemma.setup({
      line_highlights = { enabled = true },
      signs = { enabled = false },
    })

    vim.cmd("silent! %bdelete!")
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  local line_hl_ns = vim.api.nvim_create_namespace("flemma_line_highlights")

  -- Helper: get all extmarks in the line_hl namespace
  local function get_line_hl_extmarks(bufnr)
    return vim.api.nvim_buf_get_extmarks(bufnr, line_hl_ns, 0, -1, { details = true })
  end

  describe("apply_line_highlights", function()
    it("creates one range extmark per message", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "hello",
        "world",
        "",
        "@Assistant:",
        "reply line 1",
        "reply line 2",
      })

      local doc = parser.get_parsed_document(bufnr)
      ui.apply_line_highlights(bufnr, doc)

      local marks = get_line_hl_extmarks(bufnr)
      assert.are.equal(2, #marks, "should have one extmark per message")

      -- First message: @You (rows 0-3)
      assert.are.equal(0, marks[1][2], "first extmark starts at row 0")
      assert.is_truthy(marks[1][4].end_row, "first extmark has end_row")
      assert.is_truthy(string.find(marks[1][4].line_hl_group, "User"), "first extmark has User highlight")

      -- Second message: @Assistant (rows 4-6)
      assert.are.equal(4, marks[2][2], "second extmark starts at row 4")
      assert.is_truthy(marks[2][4].end_row, "second extmark has end_row")
      assert.is_truthy(string.find(marks[2][4].line_hl_group, "Assistant"), "second extmark has Assistant highlight")
    end)

    it("creates a range extmark for frontmatter", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "---",
        "model: gpt-4",
        "---",
        "",
        "@You:",
        "hello",
      })

      local doc = parser.get_parsed_document(bufnr)
      ui.apply_line_highlights(bufnr, doc)

      local marks = get_line_hl_extmarks(bufnr)
      -- 1 frontmatter + 1 message
      assert.are.equal(2, #marks, "should have frontmatter + message extmarks")
      assert.are.equal("FlemmaLineFrontmatter", marks[1][4].line_hl_group, "first extmark is frontmatter")
    end)

    it("range extmark covers interior rows via overlap query", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "line 1",
        "line 2",
        "line 3",
      })

      local doc = parser.get_parsed_document(bufnr)
      ui.apply_line_highlights(bufnr, doc)

      -- Query interior row (row 2) with overlap=true
      local marks_at_row2 = vim.api.nvim_buf_get_extmarks(
        bufnr, line_hl_ns, { 2, 0 }, { 2, 0 }, { details = true, overlap = true }
      )
      assert.are.equal(1, #marks_at_row2, "overlap query should find range extmark at interior row")
      assert.is_truthy(string.find(marks_at_row2[1][4].line_hl_group, "User"))

      -- Without overlap, interior row returns nothing
      local marks_no_overlap = vim.api.nvim_buf_get_extmarks(
        bufnr, line_hl_ns, { 2, 0 }, { 2, 0 }, { details = true }
      )
      assert.are.equal(0, #marks_no_overlap, "non-overlap query should not find range extmark at interior row")
    end)

    it("uses end_right_gravity=true for message extmarks", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "hello",
      })

      local doc = parser.get_parsed_document(bufnr)
      ui.apply_line_highlights(bufnr, doc)

      local marks = get_line_hl_extmarks(bufnr)
      assert.are.equal(1, #marks)
      assert.is_true(marks[1][4].end_right_gravity, "message extmark should have end_right_gravity=true")
    end)
  end)
end)
