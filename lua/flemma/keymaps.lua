--- Keymap configuration for Flemma
--- Centralizes all buffer-local keymap setup
---@class flemma.Keymaps
local M = {}

local bridge = require("flemma.bridge")
local config_facade = require("flemma.config")
local core = require("flemma.core")
local hooks = require("flemma.hooks")
local cursor = require("flemma.cursor")
local executor = require("flemma.tools.executor")
local log = require("flemma.logging")
local messages = require("flemma.messages")
local navigation = require("flemma.navigation")
local notify = require("flemma.notify")
local state = require("flemma.state")
local textobject = require("flemma.textobject")
local buffer_utils = require("flemma.utilities.buffer")
local folding = require("flemma.ui.folding")
local rejection = require("flemma.ui.rejection")
local ui = require("flemma.ui")

local ROLE_NAMES = { ["@System"] = true, ["@You"] = true, ["@Assistant"] = true }
local CANCEL_WINDOW_MS = 800
local RAGE_CANCEL_MS = 500

---@type integer? Monotonic timestamp (ms) of the last Ctrl+C miss (nothing was cancelled)
local last_cancel_miss_at = nil

---Handle colon insertion in insert mode.
---If the text before the cursor is a valid role marker at the start of
---the line and the cursor is at end of line, appends ":" and a newline.
---@return boolean handled True if the role marker was completed
function M.handle_colon_insert()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]

  -- In insert mode cursor can be at col == #line (after last char),
  -- in normal mode it clamps to col == #line - 1 (on last char).
  -- Accept both: the line itself must be a valid role name.
  if ROLE_NAMES[line] and col >= #line - 1 then
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local line_count = vim.api.nvim_buf_line_count(0)
    local next_line_blank = row < line_count
      and vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]:match("^%s*$") ~= nil

    if next_line_blank then
      -- Blank line already present — just complete the marker, don't insert another
      vim.api.nvim_buf_set_lines(0, row - 1, row, false, { line .. ":" })
    else
      -- Complete the role marker and add a blank line below
      vim.api.nvim_buf_set_lines(0, row - 1, row, false, { line .. ":", "" })
    end
    cursor.request_move(
      vim.api.nvim_get_current_buf(),
      { line = row + 1, force = true, reason = "role-marker-completion" }
    )
    return true
  end

  return false
end

---Setup function to initialize all keymaps
M.setup = function()
  -- Set up the mappings for Flemma interaction if enabled
  local config = config_facade.get()
  if config.keymaps.enabled then
    hooks.on("buffer:created", function()
      -- Normal mode mappings
      if config.keymaps.normal.send then
        vim.keymap.set("n", config.keymaps.normal.send, function()
          core.send_or_execute({ user_initiated = true, bufnr = vim.api.nvim_get_current_buf() })
        end, { buffer = true, desc = messages["ui.keymap.send"]{} })
      end

      if config.keymaps.normal.tool_execute then
        vim.keymap.set("n", config.keymaps.normal.tool_execute, function()
          local bufnr = vim.api.nvim_get_current_buf()

          local ok, err = executor.execute_at_cursor(bufnr)
          if not ok then
            notify.error(err or messages["ui.tool.execute_failed"]{})
          end
        end, { buffer = true, desc = messages["ui.keymap.tool_execute"]{} })
      end

      if config.keymaps.normal.tool_background then
        vim.keymap.set("n", config.keymaps.normal.tool_background, function()
          local bufnr = vim.api.nvim_get_current_buf()

          local ok, err = executor.background_at_cursor(bufnr)
          if not ok then
            notify.error(err or messages["ui.tool.background_failed"]{})
          else
            notify.info(messages["ui.tool.backgrounded"]{})
          end
        end, { buffer = true, desc = messages["ui.keymap.tool_background"]{} })
      end

      if config.keymaps.normal.tool_approve then
        vim.keymap.set("n", config.keymaps.normal.tool_approve, function()
          local bufnr = vim.api.nvim_get_current_buf()

          local ok, err = executor.approve_at_cursor(bufnr)
          if not ok then
            notify.error(err or messages["ui.tool.approve_failed"]{})
          end
        end, { buffer = true, desc = messages["ui.keymap.tool_approve"]{} })
      end

      if config.keymaps.normal.tool_reject then
        vim.keymap.set("n", config.keymaps.normal.tool_reject, function()
          local bufnr = vim.api.nvim_get_current_buf()
          rejection.open(bufnr)
        end, { buffer = true, desc = messages["ui.keymap.tool_reject"]{} })
      end

      if config.keymaps.normal.tool_approve_all then
        vim.keymap.set("n", config.keymaps.normal.tool_approve_all, function()
          local bufnr = vim.api.nvim_get_current_buf()

          local ok, err = executor.approve_all_pending(bufnr)
          if not ok then
            notify.error(err or messages["ui.tool.no_pending_approve"]{})
          end
        end, { buffer = true, desc = messages["ui.keymap.tool_approve_all"]{} })
      end

      if config.keymaps.normal.cancel then
        vim.keymap.set("n", config.keymaps.normal.cancel, function()
          local bufnr = vim.api.nvim_get_current_buf()

          if executor.cancel_for_buffer(bufnr) then
            last_cancel_miss_at = nil
            return
          end

          local buffer_state = state.get_buffer_state(bufnr)
          if buffer_state.resume_delay_timer then
            bridge.cancel_request({ bufnr = bufnr })
            last_cancel_miss_at = nil
            return
          end

          local now = vim.uv.now()
          if last_cancel_miss_at and (now - last_cancel_miss_at) < RAGE_CANCEL_MS then
            last_cancel_miss_at = nil
            log.info("RAGE cancel: user double-tapped Ctrl+C, cancelling all tools in buffer " .. bufnr)
            executor.cancel_all(bufnr)
            if buffer_state.current_request then
              bridge.cancel_request({ bufnr = bufnr })
            end
            return
          end

          last_cancel_miss_at = now
          log.debug("keymaps: Ctrl+C miss in buffer " .. bufnr .. ", awaiting double-tap for RAGE cancel")
          notify.info(messages["ui.tool.nothing_to_cancel_retry"]{})
        end, { buffer = true, desc = messages["ui.keymap.cancel"]{} })
      end

      -- Message navigation keymaps
      if config.keymaps.normal.message_next then
        vim.keymap.set(
          "n",
          config.keymaps.normal.message_next,
          navigation.find_next_message,
          { buffer = true, desc = messages["ui.keymap.message_next"]{} }
        )
      end

      if config.keymaps.normal.message_prev then
        vim.keymap.set(
          "n",
          config.keymaps.normal.message_prev,
          navigation.find_prev_message,
          { buffer = true, desc = messages["ui.keymap.message_prev"]{} }
        )
      end

      -- Fold toggle keymap (skip when the key conflicts with mapleader)
      local fold_toggle_key = config.keymaps.normal.fold_toggle
      if fold_toggle_key then
        local leader = vim.g.mapleader or "\\"
        if vim.keycode(fold_toggle_key) ~= leader then
          vim.keymap.set(
            "n",
            fold_toggle_key,
            folding.toggle_message_fold,
            { buffer = true, desc = messages["ui.keymap.fold_toggle"]{} }
          )
        end
      end

      -- Turn fold keymaps
      if config.keymaps.normal.fold_turn then
        vim.keymap.set(
          "n",
          config.keymaps.normal.fold_turn,
          folding.fold_turn_at_cursor,
          { buffer = true, desc = messages["ui.keymap.fold_turn"]{} }
        )
      end

      if config.keymaps.normal.fold_turns then
        vim.keymap.set(
          "n",
          config.keymaps.normal.fold_turns,
          folding.fold_all_turns,
          { buffer = true, desc = messages["ui.keymap.fold_turns"]{} }
        )
      end

      -- Conceal keymaps (toggle / on / off) — only when editing.conceal is configured
      local cfg_for_conceal = config_facade.get()
      local has_conceal = cfg_for_conceal
        and cfg_for_conceal.editing
        and cfg_for_conceal.editing.conceal ~= nil
        and cfg_for_conceal.editing.conceal ~= false
      if has_conceal then
        local conceal_maps = {
          {
            key = config.keymaps.normal.conceal_toggle,
            fn = ui.toggle_conceal,
            desc = messages["ui.keymap.conceal_toggle"]{},
          },
          { key = config.keymaps.normal.conceal_on, fn = ui.enable_conceal, desc = messages["ui.keymap.conceal_on"]{} },
          {
            key = config.keymaps.normal.conceal_off,
            fn = ui.disable_conceal,
            desc = messages["ui.keymap.conceal_off"]{},
          },
        }
        for _, m in ipairs(conceal_maps) do
          if m.key then
            vim.keymap.set("n", m.key, m.fn, { buffer = true, desc = m.desc })
          end
        end
      end

      -- Set up text objects with configured key
      textobject.setup({ text_object = config.keymaps.text_object })

      -- Insert-mode : auto-newline for role markers
      vim.keymap.set("i", ":", function()
        if not M.handle_colon_insert() then
          vim.api.nvim_feedkeys(":", "n", false)
          return
        end

        -- Eat one Space or Enter typed within 800ms (muscle memory protection).
        -- Space triggers InsertCharPre; Enter does not, so we catch it via
        -- a temporary keymap. Both share one idempotent cleanup.
        local completion_time = vim.uv.now()
        local cleaned_up = false
        local autocmd_id

        local function cleanup()
          if cleaned_up then
            return
          end
          cleaned_up = true
          if autocmd_id then
            pcall(vim.api.nvim_del_autocmd, autocmd_id)
          end
          pcall(vim.keymap.del, "i", "<CR>", { buffer = true })
        end

        -- Catch Space (printable char → InsertCharPre fires)
        autocmd_id = vim.api.nvim_create_autocmd("InsertCharPre", {
          buffer = 0,
          callback = function()
            if vim.v.char == " " and (vim.uv.now() - completion_time) < CANCEL_WINDOW_MS then
              vim.v.char = ""
            end
            cleanup()
          end,
        })

        -- Catch Enter (special key → needs a temporary keymap)
        vim.keymap.set("i", "<CR>", function()
          cleanup()
        end, { buffer = true })

        -- Safety timer: clean up if nothing typed within the window
        vim.defer_fn(cleanup, CANCEL_WINDOW_MS)
      end, { buffer = true, desc = messages["ui.keymap.colon_insert"]{} })

      -- Insert mode mapping - send and return to insert mode
      if config.keymaps.insert.send then
        vim.keymap.set("i", config.keymaps.insert.send, function()
          local bufnr = vim.api.nvim_get_current_buf()
          buffer_utils.buffer_cmd(bufnr, "stopinsert")
          -- Defer to next event loop iteration so stopinsert takes effect
          -- and we exit any textlock context (e.g., Copilot's keymap wrapper)
          vim.schedule(function()
            core.send_or_execute({
              bufnr = bufnr,
              user_initiated = true,
              on_request_complete = function()
                buffer_utils.buffer_cmd(bufnr, "startinsert!")
              end,
            })
          end)
        end, { buffer = true, desc = messages["ui.keymap.insert_send"]{} })
      end
    end)
  end
end

return M
