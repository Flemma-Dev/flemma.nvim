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

  it("renders the approved tool's label on the fence widget without a deferred UI pass", function()
    local bufnr = setup_pending_tool()

    -- Steady state: multi-line preview + approval prompt, no footer yet.
    ui.update_ui(bufnr)

    local before_approval = vim.api.nvim_buf_get_extmarks(bufnr, tool_approval_ns, 0, -1, { details = true })
    assert.are.equal(1, #before_approval, "pending tool should have an approval widget")
    local before_text = table.concat(
      vim.tbl_map(function(c)
        return c[1]
      end, before_approval[1][4].virt_text),
      ""
    )
    assert.is_truthy(before_text:find("⏸"), "pending widget should show pause icon")

    -- Approving is what made the buffer dance.
    local ok = executor.approve_at_cursor(bufnr)
    assert.is_true(ok)

    -- The approved widget must appear in the SAME synchronous pass.
    local after_approval = vim.api.nvim_buf_get_extmarks(bufnr, tool_approval_ns, 0, -1, { details = true })
    assert.are.equal(1, #after_approval, "approved tool should have an approved widget")
    local after_text = table.concat(
      vim.tbl_map(function(c)
        return c[1]
      end, after_approval[1][4].virt_text),
      ""
    )
    assert.is_truthy(after_text:find("✓"), "approved widget should show check icon")
    assert.is_truthy(
      after_text:find("checking disk space"),
      "approved widget must show label synchronously after approval"
    )
  end)

  it("transitions from pending prompt to approved widget synchronously", function()
    local bufnr = setup_pending_tool()

    ui.update_ui(bufnr)

    local before = vim.api.nvim_buf_get_extmarks(bufnr, tool_approval_ns, 0, -1, { details = true })
    assert.are.equal(1, #before, "pending tool should have an approval prompt")
    local before_text = table.concat(
      vim.tbl_map(function(c)
        return c[1]
      end, before[1][4].virt_text),
      ""
    )
    assert.is_truthy(before_text:find("⏸"), "pending tool should show pause icon")

    local ok = executor.approve_at_cursor(bufnr)
    assert.is_true(ok)

    local after = vim.api.nvim_buf_get_extmarks(bufnr, tool_approval_ns, 0, -1, { details = true })
    assert.are.equal(1, #after, "approved tool should have an approved widget")
    local after_text = table.concat(
      vim.tbl_map(function(c)
        return c[1]
      end, after[1][4].virt_text),
      ""
    )
    assert.is_truthy(after_text:find("✓"), "approved tool should show check icon")
    assert.is_falsy(after_text:find("⏸"), "approved tool should not show pause icon")
  end)
end)
