describe("Ctrl+C cancel behaviour", function()
  local executor
  local state

  before_each(function()
    package.loaded["flemma.tools.executor"] = nil
    package.loaded["flemma.tools.context"] = nil
    package.loaded["flemma.state"] = nil
    executor = require("flemma.tools.executor")
    state = require("flemma.state")
  end)

  after_each(function()
    vim.cmd("silent! %bdelete!")
  end)

  ---Create a buffer with a tool_use + tool_result pair and a pending_execution entry.
  ---@param opts? { background?: boolean, completed?: boolean }
  ---@return integer bufnr
  ---@return boolean[] cancel_called mutable array; cancel_called[1] tracks invocation
  local function setup_tool_buffer(opts)
    opts = opts or {}
    local cancel_called = { false }

    local bufnr = vim.api.nvim_create_buf(false, true)
    local result_suffix = ""
    if opts.background then
      result_suffix = " (job=job_bg1)"
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "@Assistant:",
      "**Tool Use:** `bash` (`tool_01`)",
      "",
      "```json",
      '{"command": "sleep 999"}',
      "```",
      "",
      "@You:",
      "**Tool Result:** `tool_01`" .. result_suffix,
      "",
      "```",
      "Running...",
      "```",
    })
    vim.bo[bufnr].filetype = "chat"

    local buffer_state = state.get_buffer_state(bufnr)
    buffer_state.pending_executions = {
      ["tool_01"] = {
        tool_id = "tool_01",
        tool_name = "bash",
        bufnr = bufnr,
        start_line = 2,
        end_line = 6,
        started_at = 0,
        completed = opts.completed or false,
        placeholder_modified = false,
        job_id = opts.background and "job_bg1" or nil,
        cancel_fn = function()
          cancel_called[1] = true
        end,
      },
    }

    return bufnr, cancel_called
  end

  -- ==========================================================================
  -- cancel_for_buffer: cursor-aware cancellation
  -- ==========================================================================

  describe("cancel_for_buffer", function()
    it("cancels foreground tool when cursor is on the tool block", function()
      local bufnr, cancel_called = setup_tool_buffer()

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      -- Place cursor on the Tool Use header (line 2, 1-indexed)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      local cancelled = executor.cancel_for_buffer(bufnr)
      assert.is_true(cancelled, "cancel_for_buffer should return true")
      assert.is_true(cancel_called[1], "cancel_fn should have been invoked")
    end)

    it("cancels background tool when cursor is on the tool block", function()
      local bufnr, cancel_called = setup_tool_buffer({ background = true })

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      -- Place cursor on the Tool Result header (line 9, inside the @You block)
      vim.api.nvim_win_set_cursor(0, { 9, 0 })

      local cancelled = executor.cancel_for_buffer(bufnr)
      assert.is_true(cancelled, "cancel_for_buffer should return true for background tool")
      assert.is_true(cancel_called[1], "cancel_fn should have been invoked for background tool")
    end)

    it("returns false when cursor is not on any tool", function()
      -- Buffer with no tool blocks — just conversation text
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "Here is some text with no tools.",
        "",
        "@You:",
        "",
      })
      vim.bo[bufnr].filetype = "chat"

      -- Seed a background tool that exists but is NOT under the cursor
      local cancel_called = false
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_bg"] = {
          tool_id = "tool_bg",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 1,
          end_line = 1,
          started_at = 0,
          completed = false,
          placeholder_modified = false,
          job_id = "job_bg1",
          cancel_fn = function()
            cancel_called = true
          end,
        },
      }

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local cancelled = executor.cancel_for_buffer(bufnr)
      assert.is_false(cancelled, "cancel_for_buffer should return false when cursor is not on a tool")
      assert.is_false(cancel_called, "cancel_fn should NOT have been invoked")
    end)

    it("returns false when tool under cursor is already completed", function()
      local bufnr, cancel_called = setup_tool_buffer({ completed = true })

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      local cancelled = executor.cancel_for_buffer(bufnr)
      assert.is_false(cancelled, "cancel_for_buffer should return false for completed tool")
      assert.is_false(cancel_called[1], "cancel_fn should NOT be called for completed tool")
    end)

    it("does NOT fall back to oldest pending tool when cursor is elsewhere", function()
      -- Buffer with no tool blocks in the text — tools exist only in pending_executions
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "Just a text response, no tools here.",
        "",
        "@You:",
        "",
      })
      vim.bo[bufnr].filetype = "chat"

      local tool1_cancelled = false
      local tool2_cancelled = false
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_01"] = {
          tool_id = "tool_01",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 1,
          end_line = 1,
          started_at = 0,
          completed = false,
          placeholder_modified = false,
          cancel_fn = function()
            tool1_cancelled = true
          end,
        },
        ["tool_02"] = {
          tool_id = "tool_02",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 1,
          end_line = 1,
          started_at = 1,
          completed = false,
          placeholder_modified = false,
          cancel_fn = function()
            tool2_cancelled = true
          end,
        },
      }

      vim.cmd("new")
      vim.api.nvim_set_current_buf(bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local cancelled = executor.cancel_for_buffer(bufnr)
      assert.is_false(cancelled, "should NOT fall back to oldest pending tool")
      assert.is_false(tool1_cancelled, "tool_01 cancel_fn should NOT be called")
      assert.is_false(tool2_cancelled, "tool_02 cancel_fn should NOT be called")
    end)
  end)

  -- ==========================================================================
  -- cancel_all: includes background tools
  -- ==========================================================================

  describe("cancel_all", function()
    it("cancels both foreground and background tools", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@Assistant:",
        "**Tool Use:** `bash` (`tool_fg`)",
        "",
        "```json",
        '{"command": "ls"}',
        "```",
        "",
        "**Tool Use:** `bash` (`tool_bg`)",
        "",
        "```json",
        '{"command": "sleep 999"}',
        "```",
        "",
        "@You:",
        "**Tool Result:** `tool_fg`",
        "",
        "```",
        "```",
        "",
        "**Tool Result:** `tool_bg` (job=job_bg1)",
        "",
        "```",
        "Running in background.",
        "```",
      })
      vim.bo[bufnr].filetype = "chat"

      local fg_cancelled = false
      local bg_cancelled = false
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_fg"] = {
          tool_id = "tool_fg",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 2,
          end_line = 6,
          started_at = 0,
          completed = false,
          placeholder_modified = false,
          cancel_fn = function()
            fg_cancelled = true
          end,
        },
        ["tool_bg"] = {
          tool_id = "tool_bg",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 8,
          end_line = 12,
          started_at = 1,
          completed = false,
          placeholder_modified = false,
          job_id = "job_bg1",
          cancel_fn = function()
            bg_cancelled = true
          end,
        },
      }

      executor.cancel_all(bufnr)

      assert.is_true(fg_cancelled, "foreground tool cancel_fn should be called")
      assert.is_true(bg_cancelled, "background tool cancel_fn should be called")
    end)
  end)
end)

-- ============================================================================
-- RAGE cancel (double-tap Ctrl+C)
-- ============================================================================

describe("RAGE cancel (double-tap Ctrl+C)", function()
  -- Headless Neovim can't reliably trigger buffer-local <C-c> keymaps via
  -- feedkeys, so we extract the keymap callback after setup and call it directly.

  local state
  local keymaps
  ---@type fun() The Ctrl+C keymap callback, extracted after keymaps.setup()
  local fire_cancel

  before_each(function()
    package.loaded["flemma.tools.executor"] = nil
    package.loaded["flemma.tools.context"] = nil
    package.loaded["flemma.state"] = nil
    package.loaded["flemma.keymaps"] = nil
    package.loaded["flemma.config"] = nil
    package.loaded["flemma.config.store"] = nil
    package.loaded["flemma.config.proxy"] = nil
    package.loaded["flemma.config.schema"] = nil
    package.loaded["flemma.bridge"] = nil
    package.loaded["flemma.core"] = nil
    package.loaded["flemma.autopilot"] = nil
    package.loaded["flemma.ui"] = nil
    package.loaded["flemma.ui.folding"] = nil
    package.loaded["flemma.cursor"] = nil
    package.loaded["flemma.navigation"] = nil
    package.loaded["flemma.notify"] = nil
    package.loaded["flemma.textobject"] = nil

    local config_facade = require("flemma.config")
    local config_schema = require("flemma.config.schema")
    config_facade.init(config_schema)
    config_facade.apply(config_facade.LAYERS.SETUP, {
      keymaps = { enabled = true, normal = { cancel = "<C-c>" } },
    })

    state = require("flemma.state")
    require("flemma.core").setup()
    keymaps = require("flemma.keymaps")
  end)

  after_each(function()
    fire_cancel = nil
    vim.cmd("silent! %bdelete!")
  end)

  ---Setup a chat buffer, display it, register keymaps, and extract the <C-c> callback.
  ---@param lines string[]
  ---@return integer bufnr
  local function setup_and_extract_cancel(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].filetype = "chat"

    vim.cmd("new")
    vim.api.nvim_set_current_buf(bufnr)

    keymaps.setup()
    vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr })

    local maps = vim.api.nvim_buf_get_keymap(bufnr, "n")
    for _, m in ipairs(maps) do
      if m.lhs == "<C-C>" then
        fire_cancel = m.callback
        break
      end
    end
    assert.is_not_nil(fire_cancel, "Ctrl+C keymap should be registered")

    return bufnr
  end

  it("first miss does not cancel all tools", function()
    local bufnr = setup_and_extract_cancel({
      "@Assistant:",
      "Some text.",
      "",
      "@You:",
      "",
    })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local bg_cancelled = false
    local buffer_state = state.get_buffer_state(bufnr)
    buffer_state.pending_executions = {
      ["tool_bg"] = {
        tool_id = "tool_bg",
        tool_name = "bash",
        bufnr = bufnr,
        start_line = 1,
        end_line = 1,
        started_at = 0,
        completed = false,
        placeholder_modified = false,
        job_id = "job_bg1",
        cancel_fn = function()
          bg_cancelled = true
        end,
      },
    }

    fire_cancel()

    assert.is_false(bg_cancelled, "background tool should NOT be cancelled on single miss")
  end)

  it("double-tap within threshold cancels all tools", function()
    local bufnr = setup_and_extract_cancel({
      "@Assistant:",
      "Some text.",
      "",
      "@You:",
      "",
    })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local bg_cancelled = false
    local buffer_state = state.get_buffer_state(bufnr)
    buffer_state.pending_executions = {
      ["tool_bg"] = {
        tool_id = "tool_bg",
        tool_name = "bash",
        bufnr = bufnr,
        start_line = 1,
        end_line = 1,
        started_at = 0,
        completed = false,
        placeholder_modified = false,
        job_id = "job_bg1",
        cancel_fn = function()
          bg_cancelled = true
        end,
      },
    }

    fire_cancel()
    fire_cancel()

    assert.is_true(bg_cancelled, "background tool SHOULD be cancelled on double-tap")
  end)

  it("successful cancel resets the double-tap timer", function()
    local bufnr = setup_and_extract_cancel({
      "@Assistant:",
      "**Tool Use:** `bash` (`tool_fg`)",
      "",
      "```json",
      '{"command": "ls"}',
      "```",
      "",
      "@You:",
      "**Tool Result:** `tool_fg`",
      "",
      "```",
      "```",
    })

    local fg_cancelled = false
    local bg_cancelled = false
    local buffer_state = state.get_buffer_state(bufnr)
    buffer_state.pending_executions = {
      ["tool_fg"] = {
        tool_id = "tool_fg",
        tool_name = "bash",
        bufnr = bufnr,
        start_line = 2,
        end_line = 6,
        started_at = 0,
        completed = false,
        placeholder_modified = false,
        cancel_fn = function()
          fg_cancelled = true
        end,
      },
      ["tool_bg"] = {
        tool_id = "tool_bg",
        tool_name = "bash",
        bufnr = bufnr,
        start_line = 2,
        end_line = 6,
        started_at = 1,
        completed = false,
        placeholder_modified = false,
        job_id = "job_bg1",
        cancel_fn = function()
          bg_cancelled = true
        end,
      },
    }

    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    fire_cancel()
    assert.is_true(fg_cancelled, "foreground tool should be cancelled")

    fire_cancel()
    assert.is_false(bg_cancelled, "background tool should NOT be cancelled — timer was reset by successful cancel")
  end)

  it("Ctrl+C cancels pending resume delay timer via keymap", function()
    local bufnr = setup_and_extract_cancel({
      "@Assistant:",
      "Done.",
      "",
      "@You:",
      "",
    })

    local buffer_state = state.get_buffer_state(bufnr)
    local timer = assert(vim.uv.new_timer())
    buffer_state.resume_delay_timer = timer
    timer:start(5000, 0, function() end)

    fire_cancel()

    assert.is_nil(buffer_state.resume_delay_timer, "Resume delay timer should be cancelled by Ctrl+C")
    assert.is_true(timer:is_closing(), "Timer should be closed")
  end)
end)
