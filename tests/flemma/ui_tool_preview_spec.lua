describe("UI Tool Previews", function()
  local flemma
  local ui
  local parser
  local state

  before_each(function()
    package.loaded["flemma"] = nil
    package.loaded["flemma.ui.indicators"] = nil
    package.loaded["flemma.ui.activity"] = nil
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
  local tool_approval_ns = vim.api.nvim_create_namespace("flemma_tool_approval")

  --- Helper: get all virt_lines extmarks in the tool_preview namespace
  ---@param bufnr integer
  ---@return table[]
  local function get_preview_extmarks(bufnr)
    return vim.api.nvim_buf_get_extmarks(bufnr, tool_preview_ns, 0, -1, { details = true })
  end

  --- Helper: get all virt_lines extmarks in the tool_approval namespace
  ---@param bufnr integer
  ---@return table[]
  local function get_approval_extmarks(bufnr)
    return vim.api.nvim_buf_get_extmarks(bufnr, tool_approval_ns, 0, -1, { details = true })
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
      local bufnr = setup_buffer()

      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local marks = get_preview_extmarks(bufnr)
      assert.are.equal(0, #marks, "should not show preview for empty result without status or indicator")
    end)

    it("anchors on opening fence at conceallevel=0", function()
      -- Default case: tree-sitter does not conceal anything. Anchoring on the
      -- opening fence places the virt_line visually inside the fenced block.
      local bufnr = setup_buffer({ status = "pending" })
      vim.api.nvim_set_option_value("conceallevel", 0, { win = vim.api.nvim_get_current_win() })

      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local marks = get_preview_extmarks(bufnr)
      assert.are.equal(1, #marks)

      local anchor_row = marks[1][2]
      local lines = vim.api.nvim_buf_get_lines(bufnr, anchor_row, anchor_row + 1, false)
      assert.are.equal("```", lines[1])
    end)

    it("anchors on opening fence line at conceallevel>=1", function()
      local bufnr = setup_buffer({ status = "pending" })
      vim.api.nvim_set_option_value("conceallevel", 2, { win = vim.api.nvim_get_current_win() })

      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local marks = get_preview_extmarks(bufnr)
      assert.are.equal(1, #marks)

      local anchor_row = marks[1][2]
      local lines = vim.api.nvim_buf_get_lines(bufnr, anchor_row, anchor_row + 1, false)
      assert.are.equal("```", lines[1], "anchor row should be the opening fence line")
    end)

    it("renders multi-line virt_lines for multi-line tool input", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "Hello",
        "",
        "@Assistant:",
        "**Tool Use:** `bash` (`tool_ml`)",
        "",
        "```json",
        '{"command":"echo line1\\necho line2\\necho line3"}',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `tool_ml` (pending)",
        "",
        "```",
        "```",
      })

      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local marks = get_preview_extmarks(bufnr)
      assert.are.equal(1, #marks, "should have one preview extmark")
      local virt_lines = marks[1][4].virt_lines
      -- 3 content lines + 1 approval prompt = 4 virt_lines
      assert.is_true(#virt_lines >= 3, "multi-line tool should produce multiple virt_lines")
    end)

    it("renders approval prompt when cursor is within pending tool_result range", function()
      local bufnr = setup_buffer({ status = "pending" })
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for i, line in ipairs(lines) do
        if line:find("Tool Result") then
          vim.api.nvim_win_set_cursor(0, { i, 0 })
          break
        end
      end

      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local marks = get_approval_extmarks(bufnr)
      assert.are.equal(1, #marks, "should have one approval extmark")
      local virt_lines = marks[1][4].virt_lines
      local text = table.concat(
        vim.tbl_map(function(c)
          return c[1]
        end, virt_lines[1]),
        ""
      )
      assert.is_truthy(text:find("⏸"), "approval virt_line should contain the pause indicator")
      assert.is_truthy(text:find("<M%-a>"), "single pending tool should show Approve keybind")
      assert.is_falsy(text:find("<M%-A>"), "single pending tool should not show All keybind")
    end)

    it("shows hint instead of keybinds when cursor is outside tool_result range", function()
      local bufnr = setup_buffer({ status = "pending" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local marks = get_approval_extmarks(bufnr)
      assert.are.equal(1, #marks, "should still render approval extmark")
      local virt_lines = marks[1][4].virt_lines
      local text = table.concat(
        vim.tbl_map(function(c)
          return c[1]
        end, virt_lines[1]),
        ""
      )
      assert.is_truthy(text:find("⏸"), "should contain ┕ connector")
      assert.is_truthy(text:find("Awaiting approval…"), "should show hint text")
      assert.is_falsy(text:find("<M%-a>"), "should not show keybinds")
    end)

    it("does not render approval prompt when ui.approval.enabled is false", function()
      local cfg = require("flemma.config")
      cfg.writer(nil, cfg.LAYERS.RUNTIME).ui.approval.enabled = false

      local bufnr = setup_buffer({ status = "pending" })
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for i, line in ipairs(lines) do
        if line:find("Tool Result") then
          vim.api.nvim_win_set_cursor(0, { i, 0 })
          break
        end
      end

      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local marks = get_approval_extmarks(bufnr)
      assert.are.equal(0, #marks, "should not render approval when disabled")

      cfg.writer(nil, cfg.LAYERS.RUNTIME).ui.approval.enabled = true
    end)

    it("does not render approval prompt for approved tools", function()
      local bufnr = setup_buffer({ status = "approved" })
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for i, line in ipairs(lines) do
        if line:find("Tool Result") then
          vim.api.nvim_win_set_cursor(0, { i, 0 })
          break
        end
      end

      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local marks = get_approval_extmarks(bufnr)
      assert.are.equal(0, #marks, "approved tool should not have approval prompt")
    end)

    it("shows queue counter when cursor is on one of multiple pending tools", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "Hello",
        "",
        "@Assistant:",
        "**Tool Use:** `bash` (`tool_a`)",
        "",
        "```json",
        '{"command":"echo a"}',
        "```",
        "",
        "**Tool Use:** `bash` (`tool_b`)",
        "",
        "```json",
        '{"command":"echo b"}',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `tool_a` (pending)",
        "",
        "```",
        "```",
        "",
        "**Tool Result:** `tool_b` (pending)",
        "",
        "```",
        "```",
      })

      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for i, line in ipairs(buf_lines) do
        if line:find("tool_a.*pending") then
          vim.api.nvim_win_set_cursor(0, { i, 0 })
          break
        end
      end

      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local marks = get_approval_extmarks(bufnr)
      assert.are.equal(2, #marks, "should have two approval extmarks")

      local first_vl = marks[1][4].virt_lines
      local first_text = table.concat(
        vim.tbl_map(function(c)
          return c[1]
        end, first_vl[1]),
        ""
      )
      assert.is_truthy(first_text:find("1/2"), "first tool should show 1/2")
      assert.is_truthy(first_text:find("<M%-a>"), "focused tool should show keybinds")
      assert.is_truthy(first_text:find("<M%-A>"), "focused tool should show All keybind with 2 pending")

      local second_vl = marks[2][4].virt_lines
      local second_text = table.concat(
        vim.tbl_map(function(c)
          return c[1]
        end, second_vl[1]),
        ""
      )
      assert.is_truthy(second_text:find("2/2"), "second tool should show 2/2")
      assert.is_truthy(second_text:find("Awaiting approval…"), "unfocused tool should show hint")
    end)

    it("counts all non-executed tools in queue counter, not just pending", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "Hello",
        "",
        "@Assistant:",
        "**Tool Use:** `bash` (`tool_a`)",
        "",
        "```json",
        '{"command":"echo a"}',
        "```",
        "",
        "**Tool Use:** `bash` (`tool_b`)",
        "",
        "```json",
        '{"command":"echo b"}',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `tool_a` (approved)",
        "",
        "```",
        "```",
        "",
        "**Tool Result:** `tool_b` (pending)",
        "",
        "```",
        "```",
      })

      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for i, line in ipairs(buf_lines) do
        if line:find("tool_b.*pending") then
          vim.api.nvim_win_set_cursor(0, { i, 0 })
          break
        end
      end

      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local marks = get_approval_extmarks(bufnr)
      assert.are.equal(1, #marks, "only pending tool gets an approval prompt")

      local text = table.concat(
        vim.tbl_map(function(c)
          return c[1]
        end, marks[1][4].virt_lines[1]),
        ""
      )
      assert.is_truthy(text:find("2/2"), "should show 2/2 (position among all non-executed tools)")
      assert.is_falsy(text:find("<M%-A>"), "single remaining pending tool should not show All keybind")
    end)

    it("paints role line bg across the virt_line text and padding", function()
      -- line_hl_group on the covering @You range extmark does not propagate to
      -- virt_lines, so without explicit bg chunks the preview row would show
      -- Normal bg and create a visible stripe against tinted role backgrounds.
      -- The fix combines FlemmaToolPreview fg with FlemmaLineUser bg on the
      -- text chunk, then pads to the text area width with FlemmaLineUser so the
      -- role bg extends like a real line_hl_group would.
      local bufnr = setup_buffer({ status = "pending" })
      local doc = parser.get_parsed_document(bufnr)

      ui.add_tool_previews(bufnr, doc)

      local marks = get_preview_extmarks(bufnr)
      assert.are.equal(1, #marks)

      local chunks = marks[1][4].virt_lines[1]
      assert.is_truthy(#chunks >= 1, "expected at least the text chunk")

      -- Text chunk: combined [FlemmaToolPreview, FlemmaLineUser] so fg comes
      -- from the preview group and bg from the role's line highlight.
      local text_hl = chunks[1][2]
      assert.same({ "FlemmaToolPreview", "FlemmaLineUser" }, text_hl)

      -- Padding chunk (when the preview is shorter than the text area): spaces
      -- highlighted with FlemmaLineUser alone to extend the role bg to the
      -- right edge.
      if #chunks > 1 then
        assert.are.equal("FlemmaLineUser", chunks[2][2])
        assert.is_truthy(chunks[2][1]:match("^ +$"), "padding chunk should be spaces only")
      end
    end)

    it("renders the label ahead of the ⏸ approval affordance", function()
      -- Canonical layout — the label leads so it stays in a fixed position
      -- across the pending → approved transition:
      --   "— <label>  ⏸ N/M · <hints>"   (focused → keybinds; else → awaiting)
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(bufnr)
      vim.bo[bufnr].filetype = "chat"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "Hello",
        "",
        "@Assistant:",
        "**Tool Use:** `bash` (`tool_a`)",
        "",
        "```json",
        '{"command":"echo a","label":"checking disk space"}',
        "```",
        "",
        "**Tool Use:** `bash` (`tool_b`)",
        "",
        "```json",
        '{"command":"echo b","label":"second task"}',
        "```",
        "",
        "@You:",
        "",
        "**Tool Result:** `tool_a` (pending)",
        "",
        "```",
        "```",
        "",
        "**Tool Result:** `tool_b` (pending)",
        "",
        "```",
        "```",
      })

      -- Cursor on tool_a → focused → keybind hints.
      for i, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
        if line:find("tool_a.*pending") then
          vim.api.nvim_win_set_cursor(0, { i, 0 })
          break
        end
      end

      local doc = parser.get_parsed_document(bufnr)
      ui.add_tool_previews(bufnr, doc)

      local marks = get_approval_extmarks(bufnr)
      assert.are.equal(2, #marks)

      local function join(mark)
        return table.concat(
          vim.tbl_map(function(c)
            return c[1]
          end, mark[4].virt_lines[1]),
          ""
        )
      end

      -- Focused tool: "꜖ checking disk space  ⏸ 1/2 · <M-a> ..."
      local a = join(marks[1])
      assert.is_truthy(a:find("^꜖ checking disk space"), "label must lead: " .. a)
      assert.is_true((a:find("checking disk space")) < (a:find("⏸")), "label must precede the ⏸ indicator: " .. a)
      assert.is_truthy(a:find("⏸ 1/2 · "), "indicator + counter follow the label: " .. a)
      assert.is_truthy(a:find("<M%-a>"), "focused tool shows keybinds after the indicator: " .. a)

      -- Unfocused tool: "꜖ second task  ⏸ 2/2 · Awaiting approval…"
      local b = join(marks[2])
      assert.is_truthy(b:find("^꜖ second task"), "label must lead: " .. b)
      assert.is_true((b:find("second task")) < (b:find("⏸")), "label must precede the ⏸ indicator: " .. b)
      assert.is_truthy(b:find("⏸ 2/2 · Awaiting approval…"), "awaiting hint follows the indicator: " .. b)
    end)
  end)
end)
