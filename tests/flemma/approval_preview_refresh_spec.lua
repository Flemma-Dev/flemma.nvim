--- Regression: approving (or rejecting) a tool must refresh the tool preview
--- synchronously, so the interactive approval-prompt line and the settled
--- "— <label>" footer swap in a single redraw frame.
---
--- The bug: executor.approve() mutated the (pending)→(approved) header but never
--- called ui.update_ui(). The approval prompt (tool_approval_ns) was dropped on
--- the incidental CursorMoved, while the footer (tool_preview_ns, rendered only
--- by add_tool_previews inside update_ui) didn't appear until the next
--- CursorHold-driven update_ui (~updatetime ms later). The buffer "danced": one
--- virtual line vanished, then ~100ms later another appeared.
---
--- These tests use an unnamed scratch buffer so the `pattern = "*.chat"`
--- CursorMoved/CursorHold autocmds never fire — the ONLY thing that can refresh
--- the preview is approve()/reject() itself.

describe("approval preview synchronous refresh", function()
  local flemma
  local ui
  local executor

  local tool_preview_ns = vim.api.nvim_create_namespace("flemma_tool_preview")
  local tool_approval_ns = vim.api.nvim_create_namespace("flemma_tool_approval")

  before_each(function()
    for _, mod in ipairs({
      "flemma",
      "flemma.ui",
      "flemma.ui.indicators",
      "flemma.ui.activity",
      "flemma.parser",
      "flemma.config",
      "flemma.state",
      "flemma.tools",
      "flemma.tools.registry",
      "flemma.tools.context",
      "flemma.tools.injector",
      "flemma.tools.executor",
      "flemma.navigation",
      "flemma.cursor",
      "flemma.autopilot",
    }) do
      package.loaded[mod] = nil
    end

    flemma = require("flemma")
    ui = require("flemma.ui")
    flemma.setup({})
    executor = require("flemma.tools.executor")

    vim.cmd("silent! %bdelete!")
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  --- Build a buffer with one pending bash tool whose multi-line command + label
  --- yields a multi-line preview (so a "— <label>" footer is rendered once the
  --- result is no longer pending).
  ---@return integer bufnr
  local function setup_pending_tool()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = "chat"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@Assistant:",
      "**Tool Use:** `bash` (`tool_a`)",
      "",
      "```json",
      '{"command":"echo line1\\necho line2","label":"checking disk space"}',
      "```",
      "",
      "@You:",
      "",
      "**Tool Result:** `tool_a` (pending)",
      "",
      "```",
      "```",
    })

    for i, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
      if line:find("Tool Result.*pending") then
        vim.api.nvim_win_set_cursor(0, { i, 0 })
        break
      end
    end

    return bufnr
  end

  --- Flatten an extmark's virt_lines into a single string.
  ---@param mark table
  ---@return string
  local function join_virt_lines(mark)
    local parts = {}
    for _, vline in ipairs(mark[4].virt_lines or {}) do
      for _, chunk in ipairs(vline) do
        parts[#parts + 1] = chunk[1]
      end
    end
    return table.concat(parts, "")
  end

  it("renders the approved tool's footer label without a deferred UI pass", function()
    local bufnr = setup_pending_tool()

    -- Steady state: multi-line preview + approval prompt, no footer yet.
    ui.update_ui(bufnr)

    local before = vim.api.nvim_buf_get_extmarks(bufnr, tool_preview_ns, 0, -1, { details = true })
    assert.are.equal(1, #before, "pending tool should have a preview")
    assert.is_falsy(
      join_virt_lines(before[1]):find("checking disk space"),
      "pending preview must not show the footer label yet"
    )

    -- Approving is what made the buffer dance.
    local ok = executor.approve_at_cursor(bufnr)
    assert.is_true(ok)

    -- The footer must appear in the SAME synchronous pass — the buggy code only
    -- added it on the next CursorHold-driven update_ui.
    local after = vim.api.nvim_buf_get_extmarks(bufnr, tool_preview_ns, 0, -1, { details = true })
    assert.are.equal(1, #after, "approved tool should still have a preview")
    assert.is_truthy(
      join_virt_lines(after[1]):find("checking disk space"),
      "approved tool footer must render synchronously after approval"
    )
  end)

  it("drops the approval prompt synchronously after approval", function()
    local bufnr = setup_pending_tool()

    ui.update_ui(bufnr)

    local before = vim.api.nvim_buf_get_extmarks(bufnr, tool_approval_ns, 0, -1, { details = true })
    assert.are.equal(1, #before, "pending tool should have an approval prompt")

    local ok = executor.approve_at_cursor(bufnr)
    assert.is_true(ok)

    local after = vim.api.nvim_buf_get_extmarks(bufnr, tool_approval_ns, 0, -1, { details = true })
    assert.are.equal(0, #after, "approval prompt must be removed synchronously after approval")
  end)
end)
