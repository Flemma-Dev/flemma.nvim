--- Keymap configuration for Flemma
--- Centralizes all buffer-local keymap setup
local M = {}

-- Setup function to initialize all keymaps
M.setup = function()
  local core = require("flemma.core")
  local navigation = require("flemma.navigation")
  local ui = require("flemma.ui")
  local textobject = require("flemma.textobject")
  local state = require("flemma.state")

  -- Create or clear the augroup for keymap-related autocmds
  local augroup = vim.api.nvim_create_augroup("FlemmaKeymaps", { clear = true })

  -- Set up the mappings for Flemma interaction if enabled
  local config = state.get_config()
  if config.keymaps.enabled then
    vim.api.nvim_create_autocmd("FileType", {
      group = augroup,
      pattern = "chat",
      callback = function()
        -- Normal mode mappings
        if config.keymaps.normal.send then
          vim.keymap.set("n", config.keymaps.normal.send, function()
            core.send_to_provider()
          end, { buffer = true, desc = "Send to Flemma" })
        end

        if config.keymaps.normal.tool_execute then
          vim.keymap.set("n", config.keymaps.normal.tool_execute, function()
            local bufnr = vim.api.nvim_get_current_buf()
            local cursor = vim.api.nvim_win_get_cursor(0)
            local tool_context = require("flemma.tools.context")
            local executor = require("flemma.tools.executor")

            local context, err = tool_context.resolve(bufnr, { row = cursor[1], col = cursor[2] })
            if not context then
              vim.notify("Flemma: " .. (err or "No tool call found"), vim.log.levels.ERROR)
              return
            end

            local ok, exec_err = executor.execute(bufnr, context)
            if not ok then
              vim.notify("Flemma: " .. (exec_err or "Execution failed"), vim.log.levels.ERROR)
            end
          end, { buffer = true, desc = "Execute Flemma tool at cursor" })
        end

        if config.keymaps.normal.cancel then
          vim.keymap.set("n", config.keymaps.normal.cancel, function()
            local bufnr = vim.api.nvim_get_current_buf()
            local buffer_state = state.get_buffer_state(bufnr)
            local executor = require("flemma.tools.executor")

            -- Priority 1: Cancel API request if active
            if buffer_state.current_request then
              core.cancel_request()
              return
            end

            -- Priority 2: Cancel first pending tool (by start time)
            local pending = executor.get_pending(bufnr)
            if #pending > 0 then
              table.sort(pending, function(a, b)
                return a.started_at < b.started_at
              end)
              executor.cancel(pending[1].tool_id)
              return
            end

            vim.notify("Flemma: Nothing to cancel", vim.log.levels.INFO)
          end, { buffer = true, desc = "Cancel Flemma Request or Tool" })
        end

        -- Message navigation keymaps
        if config.keymaps.normal.next_message then
          vim.keymap.set(
            "n",
            config.keymaps.normal.next_message,
            navigation.find_next_message,
            { buffer = true, desc = "Jump to next message" }
          )
        end

        if config.keymaps.normal.prev_message then
          vim.keymap.set(
            "n",
            config.keymaps.normal.prev_message,
            navigation.find_prev_message,
            { buffer = true, desc = "Jump to previous message" }
          )
        end

        -- Set up text objects with configured key
        textobject.setup({ text_object = config.text_object })

        -- Insert mode mapping - send and return to insert mode
        if config.keymaps.insert.send then
          vim.keymap.set("i", config.keymaps.insert.send, function()
            local bufnr = vim.api.nvim_get_current_buf()
            ui.buffer_cmd(bufnr, "stopinsert")
            core.send_to_provider({
              on_request_complete = function()
                ui.buffer_cmd(bufnr, "startinsert!")
              end,
            })
          end, { buffer = true, desc = "Send to Flemma and continue editing" })
        end
      end,
    })
  end
end

return M
