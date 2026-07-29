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

    it("scales bar width to match fence backtick count", function()
      local chunks = ui.build_fence_virt_text("``````", "FlemmaFenceBar", "FlemmaFenceLabel")
      assert.is_truthy(chunks)
      assert.are.equal(1, #chunks)
      assert.are.equal(string.rep("╌", 6), chunks[1][1])
    end)

    it("extracts language after wide fence delimiter", function()
      local chunks = ui.build_fence_virt_text("````lua", "FlemmaFenceBar", "FlemmaFenceLabel")
      assert.is_truthy(chunks)
      assert.are.equal(2, #chunks)
      assert.are.equal(string.rep("╌", 4), chunks[1][1])
      assert.are.equal("lua", chunks[2][1])
    end)
  end)

  describe("tree-aware fence filtering", function()
    ---@param bufnr integer
    ---@return TSNode|nil
    local function get_markdown_root(bufnr)
      local ok, ts_parser = pcall(vim.treesitter.get_parser, bufnr, "markdown")
      if not ok or not ts_parser then
        return nil
      end
      ts_parser:parse()
      local trees = ts_parser:trees()
      return trees[1] and trees[1]:root() or nil
    end

    it("distinguishes outer delimiters from inner backticks in nested fences", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "``````",
        "```",
        "nested code",
        "```",
        "``````",
      })

      local root = get_markdown_root(bufnr)
      if not root then
        return
      end

      local node_open = root:named_descendant_for_range(0, 0, 0, 0)
      assert.are.equal("fenced_code_block_delimiter", node_open:type(), "outer opening is a delimiter")

      local node_close = root:named_descendant_for_range(4, 0, 4, 0)
      assert.are.equal("fenced_code_block_delimiter", node_close:type(), "outer closing is a delimiter")

      local node_inner_open = root:named_descendant_for_range(1, 0, 1, 0)
      assert.are_not.equal(
        "fenced_code_block_delimiter",
        node_inner_open:type(),
        "inner ``` is content, not a delimiter"
      )

      local node_inner_close = root:named_descendant_for_range(3, 0, 3, 0)
      assert.are_not.equal(
        "fenced_code_block_delimiter",
        node_inner_close:type(),
        "inner ``` is content, not a delimiter"
      )
    end)

    it("only treats the opening as a delimiter when fences are non-balanced", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "````",
        "some code",
        "```",
        "more text",
      })

      local root = get_markdown_root(bufnr)
      if not root then
        return
      end

      local node_open = root:named_descendant_for_range(0, 0, 0, 0)
      assert.are.equal("fenced_code_block_delimiter", node_open:type(), "opening ```` is a delimiter")

      local node_short = root:named_descendant_for_range(2, 0, 2, 0)
      assert.are_not.equal("fenced_code_block_delimiter", node_short:type(), "``` does not close a ```` fence")

      local open_chunks = ui.build_fence_virt_text("````", "FlemmaFenceBar", "FlemmaFenceLabel")
      assert.are.equal(string.rep("╌", 4), open_chunks[1][1], "opening overlay is 4 wide")

      local short_chunks = ui.build_fence_virt_text("```", "FlemmaFenceBar", "FlemmaFenceLabel")
      assert.is_truthy(short_chunks, "pattern match still fires on ```")
    end)
  end)

  describe("resolve_fence_highlights", function()
    it("returns nil for non-chat buffers", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "markdown"
      highlight.strip_fence_conceal()
      vim.api.nvim_set_option_value("conceallevel", 2, { win = 0, scope = "local" })

      local bar_hl, label_hl = ui.resolve_fence_highlights(bufnr, vim.api.nvim_get_current_win(), 0)
      assert.is_nil(bar_hl)
      assert.is_nil(label_hl)
    end)

    it("returns nil when conceal patch is inactive", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_set_option_value("conceallevel", 2, { win = 0, scope = "local" })

      local bar_hl, label_hl = ui.resolve_fence_highlights(bufnr, vim.api.nvim_get_current_win(), 0)
      assert.is_nil(bar_hl)
      assert.is_nil(label_hl)
    end)

    it("returns nil when conceallevel < 2", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      highlight.strip_fence_conceal()

      vim.api.nvim_set_option_value("conceallevel", 0, { win = 0, scope = "local" })
      local bar_hl = ui.resolve_fence_highlights(bufnr, vim.api.nvim_get_current_win(), 0)
      assert.is_nil(bar_hl, "nil at conceallevel=0")

      vim.api.nvim_set_option_value("conceallevel", 1, { win = 0, scope = "local" })
      bar_hl = ui.resolve_fence_highlights(bufnr, vim.api.nvim_get_current_win(), 0)
      assert.is_nil(bar_hl, "nil at conceallevel=1")
    end)

    it("returns default highlight groups when all gates pass", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      highlight.strip_fence_conceal()
      vim.api.nvim_set_option_value("conceallevel", 2, { win = 0, scope = "local" })

      local bar_hl, label_hl = ui.resolve_fence_highlights(bufnr, vim.api.nvim_get_current_win(), 0)
      assert.are.equal("FlemmaFenceBar", bar_hl)
      assert.are.equal("FlemmaFenceLabel", label_hl)
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
