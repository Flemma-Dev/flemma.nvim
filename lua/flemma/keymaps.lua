--- Keymap configuration for Flemma
--- Centralizes all buffer-local keymap setup
local M = {}

-- Setup function to initialize all keymaps
M.setup = function()
  local core = require("flemma.core")
  local navigation = require("flemma.navigation")
  local buffers = require("flemma.buffers")
  local textobject = require("flemma.textobject")
  local state = require("flemma.state")

  -- Set up the mappings for Flemma interaction if enabled
  local config = state.get_config()
  if config.keymaps.enabled then
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "chat",
      callback = function()
        -- Normal mode mappings
        if config.keymaps.normal.send then
          vim.keymap.set("n", config.keymaps.normal.send, function()
            core.send_to_provider()
          end, { buffer = true, desc = "Send to Flemma" })
        end

        if config.keymaps.normal.cancel then
          vim.keymap.set(
            "n",
            config.keymaps.normal.cancel,
            core.cancel_request,
            { buffer = true, desc = "Cancel Flemma Request" }
          )
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
            buffers.buffer_cmd(bufnr, "stopinsert")
            core.send_to_provider({
              on_complete = function()
                buffers.buffer_cmd(bufnr, "startinsert!")
              end,
            })
          end, { buffer = true, desc = "Send to Flemma and continue editing" })
        end
      end,
    })
  end
end

return M
