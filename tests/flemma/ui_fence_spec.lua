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

  local fence_ns = vim.api.nvim_create_namespace("flemma_fence_overlays")

  ---Set up a buffer with fence overlay preconditions: strip conceal, set
  ---conceallevel >= 2, and set filetype to chat so add_fence_overlays proceeds.
  ---@param bufnr integer
  local function setup_fence_preconditions(bufnr)
    highlight.strip_fence_conceal()
    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      vim.api.nvim_set_option_value("conceallevel", 2, { win = winid, scope = "local" })
    end
  end

  ---@param bufnr integer
  ---@return table[]
  local function get_fence_extmarks(bufnr)
    return vim.api.nvim_buf_get_extmarks(bufnr, fence_ns, 0, -1, { details = true })
  end

  ---@param mark table Extmark from nvim_buf_get_extmarks with details
  ---@return string[] texts Virtual text strings concatenated
  local function extmark_virt_texts(mark)
    local details = mark[4]
    if not details or not details.virt_text then
      return {}
    end
    local texts = {}
    for _, chunk in ipairs(details.virt_text) do
      table.insert(texts, chunk[1])
    end
    return texts
  end

  ---@param mark table
  ---@return string[] hls Highlight group names from virt_text chunks
  local function extmark_virt_hls(mark)
    local details = mark[4]
    if not details or not details.virt_text then
      return {}
    end
    local hls = {}
    for _, chunk in ipairs(details.virt_text) do
      table.insert(hls, chunk[2])
    end
    return hls
  end

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

  describe("add_fence_overlays", function()
    it("places extmarks on fence delimiter lines", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "Here is code:",
        "",
        "```lua",
        "print('hello')",
        "```",
      })

      setup_fence_preconditions(bufnr)
      ui.add_fence_overlays(bufnr)

      local marks = get_fence_extmarks(bufnr)
      assert.are.equal(2, #marks, "should place extmarks on both fence lines")

      -- Opening fence at line 4 (0-indexed: 3)
      assert.are.equal(3, marks[1][2], "opening fence extmark row")
      local open_texts = extmark_virt_texts(marks[1])
      assert.are.equal(2, #open_texts, "opening fence should have bar + label chunks")
      assert.is_truthy(open_texts[2]:find("lua"), "opening fence label should contain language name")

      -- Closing fence at line 6 (0-indexed: 5)
      assert.are.equal(5, marks[2][2], "closing fence extmark row")
      local close_texts = extmark_virt_texts(marks[2])
      assert.are.equal(1, #close_texts, "closing fence should have bar chunk only")
    end)

    it("uses fallback label when fence has no language", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "**Tool Result:** `tool_1`",
        "",
        "```",
        "```",
      })

      setup_fence_preconditions(bufnr)
      ui.add_fence_overlays(bufnr)

      local marks = get_fence_extmarks(bufnr)
      assert.are.equal(2, #marks)

      local open_texts = extmark_virt_texts(marks[1])
      assert.are.equal(2, #open_texts, "opening fence without language should still have 2 chunks")
      assert.are.equal("text", open_texts[2], "should use default fallback label")
    end)

    it("uses correct highlight groups", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "```json",
        "{}",
        "```",
      })

      setup_fence_preconditions(bufnr)
      ui.add_fence_overlays(bufnr)

      local marks = get_fence_extmarks(bufnr)
      assert.are.equal(2, #marks)

      local open_hls = extmark_virt_hls(marks[1])
      assert.are.equal("FlemmaFenceBar", open_hls[1])
      assert.are.equal("FlemmaFenceLabel", open_hls[2])

      local close_hls = extmark_virt_hls(marks[2])
      assert.are.equal("FlemmaFenceBar", close_hls[1])
    end)

    it("handles multiple fenced blocks", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "**Tool Use:** `bash` (`tool_1`)",
        "",
        "```json",
        '{"command":"ls"}',
        "```",
        "",
        "@You:",
        "**Tool Result:** `tool_1`",
        "",
        "```",
        "file1.txt",
        "```",
      })

      setup_fence_preconditions(bufnr)
      ui.add_fence_overlays(bufnr)

      local marks = get_fence_extmarks(bufnr)
      assert.are.equal(4, #marks, "should place extmarks on all 4 fence lines")

      -- First block: opening has "json", closing has bar only
      local first_open = extmark_virt_texts(marks[1])
      assert.are.equal("json", first_open[2])
      local first_close = extmark_virt_texts(marks[2])
      assert.are.equal(1, #first_close)

      -- Second block: opening has fallback "text"
      local second_open = extmark_virt_texts(marks[3])
      assert.are.equal("text", second_open[2])
    end)

    it("clears previous extmarks on each call", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "```lua",
        "x = 1",
        "```",
      })

      setup_fence_preconditions(bufnr)
      ui.add_fence_overlays(bufnr)
      assert.are.equal(2, #get_fence_extmarks(bufnr))

      -- Remove the fenced block
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "no code blocks here",
      })

      ui.add_fence_overlays(bufnr)
      assert.are.equal(0, #get_fence_extmarks(bufnr), "should clear stale extmarks")
    end)

    it("skips overlays when conceallevel < 2", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "```lua",
        "x = 1",
        "```",
      })

      highlight.strip_fence_conceal()
      -- conceallevel=0: overlays should be suppressed
      vim.api.nvim_set_option_value("conceallevel", 0, { win = 0, scope = "local" })

      ui.add_fence_overlays(bufnr)
      assert.are.equal(0, #get_fence_extmarks(bufnr), "no overlays at conceallevel=0")

      -- conceallevel=1: still suppressed
      vim.api.nvim_set_option_value("conceallevel", 1, { win = 0, scope = "local" })
      ui.add_fence_overlays(bufnr)
      assert.are.equal(0, #get_fence_extmarks(bufnr), "no overlays at conceallevel=1")

      -- conceallevel=2: overlays appear
      vim.api.nvim_set_option_value("conceallevel", 2, { win = 0, scope = "local" })
      ui.add_fence_overlays(bufnr)
      assert.are.equal(2, #get_fence_extmarks(bufnr), "overlays present at conceallevel=2")
    end)

    it("clears existing overlays when conceallevel drops below 2", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "```lua",
        "x = 1",
        "```",
      })

      setup_fence_preconditions(bufnr)
      ui.add_fence_overlays(bufnr)
      assert.are.equal(2, #get_fence_extmarks(bufnr))

      -- Drop conceallevel — overlays should be cleared
      vim.api.nvim_set_option_value("conceallevel", 0, { win = 0, scope = "local" })
      ui.add_fence_overlays(bufnr)
      assert.are.equal(0, #get_fence_extmarks(bufnr), "overlays cleared when conceallevel drops to 0")
    end)

    it("uses overlay positioning", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "```json",
        "{}",
        "```",
      })

      setup_fence_preconditions(bufnr)
      ui.add_fence_overlays(bufnr)

      local marks = get_fence_extmarks(bufnr)
      for _, mark in ipairs(marks) do
        assert.are.equal("overlay", mark[4].virt_text_pos, "fence extmarks should use overlay positioning")
      end
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
