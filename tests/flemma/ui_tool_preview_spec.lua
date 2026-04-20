describe("UI Tool Previews", function()
  local flemma
  local ui
  local parser
  local state

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.ui"] = nil
    package.loaded["flemma.parser"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.tools"] = nil
    package.loaded["flemma.tools.context"] = nil
    package.loaded["flemma.tools.injector"] = nil

    flemma = require("flemma")
    ui = require("flemma.ui")
    parser = require("flemma.parser")
    state = require("flemma.state")

    flemma.setup({})

    vim.cmd("silent! %bdelete!")
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  local tool_preview_ns = vim.api.nvim_create_namespace("flemma_tool_preview")

  --- Helper: get all virt_lines extmarks in the tool_preview namespace
  ---@param bufnr integer
  ---@return table[]
  local function get_preview_extmarks(bufnr)
    return vim.api.nvim_buf_get_extmarks(bufnr, tool_preview_ns, 0, -1, { details = true })
  end

  --- Helper: set up a buffer with a tool use + tool result placeholder
  ---@param opts? { status?: string }
  ---@return integer bufnr
  local function setup_buffer(opts)
    opts = opts or {}
    local header = "**Tool Result:** `tool_123`"
    if opts.status then
      header = header .. " (" .. opts.status .. ")"
    end

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = "chat"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@You:",
      "Hello",
      "",
      "@Assistant:",
      "**Tool Use:** `bash` (`tool_123`)",
      "",
      "```json",
      '{"command":"echo hi","label":"print greeting"}',
      "```",
      "",
      "@You:",
      "",
      header,
      "",
      "```",
      "```",
    })

    return bufnr
  end

  --- Helper: simulate an active execution indicator for a tool
  ---@param bufnr integer
  ---@param tool_id string
  local function simulate_execution_indicator(bufnr, tool_id)
    local buffer_state = state.get_buffer_state(bufnr)
    if not buffer_state.tool_indicators then
      buffer_state.tool_indicators = {}
    end
    -- Minimal indicator entry — enough for the truthiness check in add_tool_previews
    buffer_state.tool_indicators[tool_id] = { extmark_id = 0, timer = nil }
  end

  describe("add_tool_previews", function()
    it("shows preview for pending status blocks", function()
      local bufnr = setup_buffer({ status = "pending" })
      local doc = parser.get_parsed_document(bufnr)

      ui.add_tool_previews(bufnr, doc)

      local marks = get_preview_extmarks(bufnr)
      assert.are.equal(1, #marks, "should have one preview extmark")
      assert.is_truthy(marks[1][4].virt_lines, "extmark should have virt_lines")

      local virt_text = marks[1][4].virt_lines[1][1][1]
      assert.is_truthy(virt_text:find("bash"), "preview should contain tool name")
    end)

    it("shows preview when tool has active execution indicator but no status suffix", function()
      -- This is the key scenario: the header status suffix was cleared at
      -- execution start but the tool is still executing — preview must
      -- remain visible.
      local bufnr = setup_buffer()
      simulate_execution_indicator(bufnr, "tool_123")

      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local marks = get_preview_extmarks(bufnr)
      assert.are.equal(1, #marks, "should have one preview extmark for executing tool")

      local virt_text = marks[1][4].virt_lines[1][1][1]
      assert.is_truthy(virt_text:find("bash"), "preview should contain tool name")
    end)

    it("does not show preview for completed tool results with content", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "Hello",
        "",
        "@Assistant:",
        "**Tool Use:** `bash` (`tool_123`)",
        "",
        "```json",
        '{"command":"echo hi","label":"print greeting"}',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `tool_123`",
        "",
        "```",
        "hi",
        "```",
      })

      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local marks = get_preview_extmarks(bufnr)
      assert.are.equal(0, #marks, "should not show preview for completed result with content")
    end)

    it("does not show preview for empty result without status or indicator", function()
      -- A plain empty fenced block with no status and no active indicator —
      -- this represents a completed tool with empty output, not a pending one.
      local bufnr = setup_buffer({ fence = "```" })

      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local marks = get_preview_extmarks(bufnr)
      assert.are.equal(0, #marks, "should not show preview for empty result without status or indicator")
    end)

    it("anchors on opening fence at conceallevel=0", function()
      -- Default case: tree-sitter does not conceal anything. Anchoring on the
      -- opening fence places the virt_line visually inside the fenced block.
      local bufnr = setup_buffer({ fence = "```flemma:tool status=pending" })
      vim.api.nvim_set_option_value("conceallevel", 0, { win = vim.api.nvim_get_current_win() })

      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local marks = get_preview_extmarks(bufnr)
      assert.are.equal(1, #marks)

      local anchor_row = marks[1][2]
      local lines = vim.api.nvim_buf_get_lines(bufnr, anchor_row, anchor_row + 1, false)
      assert.are.equal("```flemma:tool status=pending", lines[1])
    end)

    it("anchors on blank line before fence at conceallevel>=1", function()
      -- Tree-sitter's markdown query sets `conceal_lines = ""` on the
      -- fenced_code_block_delimiter, so at conceallevel>=1 the opening and
      -- closing fence lines are hidden entirely. An extmark anchored there
      -- would go invisible with them. Anchor on the preceding blank line
      -- instead so the virt_line survives.
      local bufnr = setup_buffer({ fence = "```flemma:tool status=pending" })
      vim.api.nvim_set_option_value("conceallevel", 2, { win = vim.api.nvim_get_current_win() })

      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local marks = get_preview_extmarks(bufnr)
      assert.are.equal(1, #marks)

      local anchor_row = marks[1][2]
      local lines = vim.api.nvim_buf_get_lines(bufnr, anchor_row, anchor_row + 1, false)
      assert.are.equal("", lines[1], "anchor row should be the blank line before the opening fence")

      -- And the NEXT line is the opening fence — confirms we are one above it.
      local next_line = vim.api.nvim_buf_get_lines(bufnr, anchor_row + 1, anchor_row + 2, false)[1]
      assert.are.equal("```flemma:tool status=pending", next_line)
    end)

    it("falls back to the Tool Result header when the blank is collapsed", function()
      -- The parser accepts zero blank lines between the `**Tool Result:**`
      -- header and the opening fence (codeblock.skip_blank_lines tolerates 0).
      -- In that case `opening_fence - 1` lands on the header line itself,
      -- which has no `conceal_lines` metadata — only per-character conceal on
      -- `**` and backticks — so the line survives and the virt_line renders
      -- just below the header.
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "Hello",
        "",
        "@Assistant:",
        "**Tool Use:** `bash` (`tool_123`)",
        "",
        "```json",
        '{"command":"echo hi","label":"print greeting"}',
        "```",
        "",
        "@You:",
        "**Tool Result:** `tool_123`",
        "```flemma:tool status=pending",
        "```",
      })
      vim.api.nvim_set_option_value("conceallevel", 2, { win = vim.api.nvim_get_current_win() })

      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local marks = get_preview_extmarks(bufnr)
      assert.are.equal(1, #marks)

      local anchor_row = marks[1][2]
      local anchor_line = vim.api.nvim_buf_get_lines(bufnr, anchor_row, anchor_row + 1, false)[1]
      assert.are.equal("**Tool Result:** `tool_123`", anchor_line)
    end)
  end)
end)
