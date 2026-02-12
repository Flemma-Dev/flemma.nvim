--- Keymap configuration for Flemma
--- Centralizes all buffer-local keymap setup
---@class flemma.Keymaps
local M = {}

---Setup function to initialize all keymaps
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
            core.send_or_execute()
          end, { buffer = true, desc = "Send to Flemma" })
        end

        if config.keymaps.normal.tool_execute then
          vim.keymap.set("n", config.keymaps.normal.tool_execute, function()
            local bufnr = vim.api.nvim_get_current_buf()
            local executor = require("flemma.tools.executor")
            local ok, err = executor.execute_at_cursor(bufnr)
            if not ok then
              vim.notify("Flemma: " .. (err or "Execution failed"), vim.log.levels.ERROR)
            end
          end, { buffer = true, desc = "Execute Flemma tool at cursor" })
        end

        if config.keymaps.normal.cancel then
          vim.keymap.set("n", config.keymaps.normal.cancel, function()
            local bufnr = vim.api.nvim_get_current_buf()
            local executor = require("flemma.tools.executor")
            if not executor.cancel_for_buffer(bufnr) then
              vim.notify("Flemma: Nothing to cancel", vim.log.levels.INFO)
            end
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
            -- Defer to next event loop iteration so stopinsert takes effect
            -- and we exit any textlock context (e.g., Copilot's keymap wrapper)
            vim.schedule(function()
              core.send_or_execute({
                on_request_complete = function()
                  ui.buffer_cmd(bufnr, "startinsert!")
                end,
              })
            end)
          end, { buffer = true, desc = "Send to Flemma and continue editing" })
        end
      end,
    })
  end
end

return M
