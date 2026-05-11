describe("UI Fence Brackets", function()
  local flemma
  local ui
  local highlight

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.ui.indicators"] = nil
    package.loaded["flemma.ui.activity"] = nil
    package.loaded["flemma.ui"] = nil
    package.loaded["flemma.ui.folding"] = nil
    package.loaded["flemma.ui.folding.merge"] = nil
    package.loaded["flemma.ui.folding.rules.frontmatter"] = nil
    package.loaded["flemma.ui.folding.rules.thinking"] = nil
    package.loaded["flemma.ui.folding.rules.tool_blocks"] = nil
    package.loaded["flemma.ui.folding.rules.messages"] = nil
    package.loaded["flemma.ui.preview"] = nil
    package.loaded["flemma.highlight"] = nil
    package.loaded["flemma.parser"] = nil
    package.loaded["flemma.bridge"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.tools.context"] = nil
    package.loaded["flemma.tools.injector"] = nil

    flemma = require("flemma")
    ui = require("flemma.ui")
    highlight = require("flemma.highlight")

    flemma.setup({})

    vim.cmd("silent! %bdelete!")
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  describe("strip_fence_conceal", function()
    it("removes conceal_lines from the markdown highlights query", function()
      highlight.strip_fence_conceal()

      local files = vim.treesitter.query.get_files("markdown", "highlights")
      assert.is_truthy(#files > 0, "should have at least one highlights query file")

      local query = vim.treesitter.query.get("markdown", "highlights")
      assert.is_truthy(query, "query should exist after stripping")
      assert.is_falsy(query.has_conceal_line, "query should not have conceal_line flag after stripping")
    end)

    it("produces a query without conceal_line flag", function()
      highlight.strip_fence_conceal()

      local query = vim.treesitter.query.get("markdown", "highlights")
      assert.is_truthy(query, "query should exist after stripping")
      assert.is_falsy(query.has_conceal_line, "has_conceal_line should be false after stripping")
    end)

    it("clears _conceal_line on active highlighters", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "```", "hello", "```" })

      local hl = vim.treesitter.highlighter.active[bufnr]
      if hl then
        hl._conceal_line = true
      end

      highlight.strip_fence_conceal()

      local hl_after = vim.treesitter.highlighter.active[bufnr]
      if hl_after then
        assert.is_falsy(hl_after._conceal_line, "_conceal_line should be cleared")
      end
    end)
  end)

  describe("build_fence_virt_text", function()
    it("returns bar + label for fence with language", function()
      local chunks = ui.build_fence_virt_text("```lua", "FlemmaFenceBar", "FlemmaFenceLabel")
      assert.is_truthy(chunks)
      assert.are.equal(2, #chunks)
      assert.is_truthy(chunks[1][1]:find("╌"), "bar chunk should contain fence character")
      assert.are.equal("FlemmaFenceBar", chunks[1][2])
      assert.are.equal("lua", chunks[2][1])
      assert.are.equal("FlemmaFenceLabel", chunks[2][2])
    end)

    it("returns bar only for bare fence delimiter", function()
      local chunks = ui.build_fence_virt_text("```", "FlemmaFenceBar", "FlemmaFenceLabel")
      assert.is_truthy(chunks)
      assert.are.equal(1, #chunks)
      assert.are.equal("FlemmaFenceBar", chunks[1][2])
    end)

    it("returns nil for non-fence lines", function()
      assert.is_nil(ui.build_fence_virt_text("print('hello')", "FlemmaFenceBar", "FlemmaFenceLabel"))
      assert.is_nil(ui.build_fence_virt_text("``lua", "FlemmaFenceBar", "FlemmaFenceLabel"))
      assert.is_nil(ui.build_fence_virt_text("", "FlemmaFenceBar", "FlemmaFenceLabel"))
    end)

    it("uses provided highlight groups", function()
      local chunks = ui.build_fence_virt_text("```json", "CustomBar", "CustomLabel")
      assert.are.equal("CustomBar", chunks[1][2])
      assert.are.equal("CustomLabel", chunks[2][2])
    end)
  end)

  describe("restore_highlighter_conceal", function()
    it("is a no-op when fence_conceal_patched is false", function()
      assert.is_false(highlight.is_fence_conceal_patched())

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "markdown"

      -- Should not error even when no patch has been applied
      highlight.restore_highlighter_conceal(bufnr)
    end)

    it("is a no-op when the buffer has no treesitter highlighter", function()
      highlight.strip_fence_conceal()

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      -- Don't set filetype — no highlighter constructed
      highlight.restore_highlighter_conceal(bufnr)

      -- Verify global query is still stripped (not accidentally restored)
      local query = vim.treesitter.query.get("markdown", "highlights")
      assert.is_falsy(query.has_conceal_line, "global query should remain stripped")
    end)

    it("restores _conceal_line on a markdown buffer's highlighter", function()
      highlight.strip_fence_conceal()

      -- Create a markdown buffer — its highlighter gets _conceal_line = false
      -- because the global query was stripped before construction.
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "markdown"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "```", "hello", "```" })

      local hl_before = vim.treesitter.highlighter.active[bufnr]
      if not hl_before then
        -- Treesitter may not start automatically in headless tests; skip
        return
      end
      assert.is_falsy(hl_before._conceal_line, "highlighter should lack _conceal_line before restore")

      highlight.restore_highlighter_conceal(bufnr)

      local hl_after = vim.treesitter.highlighter.active[bufnr]
      assert.is_truthy(hl_after, "highlighter should exist after restore")
      assert.is_truthy(hl_after._conceal_line, "_conceal_line should be true after restore")
    end)

    it("is idempotent — second call is a no-op", function()
      highlight.strip_fence_conceal()

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "markdown"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "```", "hello", "```" })

      local hl = vim.treesitter.highlighter.active[bufnr]
      if not hl then
        return
      end

      highlight.restore_highlighter_conceal(bufnr)
      local hl_after_first = vim.treesitter.highlighter.active[bufnr]

      -- Second call should return early (hl._conceal_line is now true)
      highlight.restore_highlighter_conceal(bufnr)
      local hl_after_second = vim.treesitter.highlighter.active[bufnr]

      -- Same highlighter instance — no unnecessary restart
      assert.are.equal(hl_after_first, hl_after_second, "second call should not reconstruct the highlighter")
    end)

    it("leaves the global query in the stripped state", function()
      highlight.strip_fence_conceal()

      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "markdown"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "```", "hello", "```" })

      local hl = vim.treesitter.highlighter.active[bufnr]
      if not hl then
        return
      end

      highlight.restore_highlighter_conceal(bufnr)

      -- Global query must be stripped for future .chat highlighter construction
      local query = vim.treesitter.query.get("markdown", "highlights")
      assert.is_falsy(query.has_conceal_line, "global query should be stripped after restore")
    end)
  end)

  describe("fence CursorLine contrast swap", function()
    it("should expose fence_conceal_patched accessor", function()
      assert.is_false(highlight.is_fence_conceal_patched())
      highlight.strip_fence_conceal()
      assert.is_true(highlight.is_fence_conceal_patched())
    end)

    it("should expose fence cursorline map accessor", function()
      local map = highlight.get_fence_cursorline_map()
      assert.is_table(map)
    end)
  end)
end)
