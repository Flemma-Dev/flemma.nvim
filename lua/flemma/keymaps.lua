--- Keymap configuration for Flemma
--- Centralizes all buffer-local keymap setup
---@class flemma.Keymaps
local M = {}

local core = require("flemma.core")
local cursor = require("flemma.cursor")
local executor = require("flemma.tools.executor")
local navigation = require("flemma.navigation")
local state = require("flemma.state")
local textobject = require("flemma.textobject")
local ui = require("flemma.ui")

local ROLE_NAMES = { ["@System"] = true, ["@You"] = true, ["@Assistant"] = true }
local CANCEL_WINDOW_MS = 800

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
            core.send_or_execute({ user_initiated = true })
          end, { buffer = true, desc = "Send to Flemma" })
        end

        if config.keymaps.normal.tool_execute then
          vim.keymap.set("n", config.keymaps.normal.tool_execute, function()
            local bufnr = vim.api.nvim_get_current_buf()

            local ok, err = executor.execute_at_cursor(bufnr)
            if not ok then
              vim.notify("Flemma: " .. (err or "Execution failed"), vim.log.levels.ERROR)
            end
          end, { buffer = true, desc = "Execute Flemma tool at cursor" })
        end

        if config.keymaps.normal.cancel then
          vim.keymap.set("n", config.keymaps.normal.cancel, function()
            local bufnr = vim.api.nvim_get_current_buf()

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
        end, { buffer = true, desc = "Auto-newline after role markers" })

        -- Insert mode mapping - send and return to insert mode
        if config.keymaps.insert.send then
          vim.keymap.set("i", config.keymaps.insert.send, function()
            local bufnr = vim.api.nvim_get_current_buf()
            ui.buffer_cmd(bufnr, "stopinsert")
            -- Defer to next event loop iteration so stopinsert takes effect
            -- and we exit any textlock context (e.g., Copilot's keymap wrapper)
            vim.schedule(function()
              core.send_or_execute({
                user_initiated = true,
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
