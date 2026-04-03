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
  ---@param opts? { fence?: string }
  ---@return integer bufnr
  local function setup_buffer(opts)
    opts = opts or {}
    local fence = opts.fence or "```"

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
      fence,
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
      local bufnr = setup_buffer({ fence = "```flemma:tool status=pending" })
      local doc = parser.get_parsed_document(bufnr)

      ui.add_tool_previews(bufnr, doc)

      local marks = get_preview_extmarks(bufnr)
      assert.are.equal(1, #marks, "should have one preview extmark")
      assert.is_truthy(marks[1][4].virt_lines, "extmark should have virt_lines")

      local virt_text = marks[1][4].virt_lines[1][1][1]
      assert.is_truthy(virt_text:find("bash"), "preview should contain tool name")
    end)

    it("shows preview when tool has active execution indicator but no status fence", function()
      -- This is the key scenario: fence info was stripped at execution start
      -- but the tool is still executing — preview must remain visible.
      local bufnr = setup_buffer({ fence = "```" })
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
  end)
end)
