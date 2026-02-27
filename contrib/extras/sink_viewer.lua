-- Sink viewer — shows Flemma sink buffers in a bottom split as they stream.
--
-- Copy this file into your Neovim config and require it, or paste the parts
-- you need. The autocmd listens for FlemmaSinkCreated events and opens a
-- bottom split for any sink whose name matches a pattern you choose.
--
-- Usage:
--   require("sink_viewer").setup({ pattern = "^anthropic/thinking" })
--   require("sink_viewer").setup({ pattern = { "^anthropic/thinking", "^http/" } })
--
-- Every time Flemma creates a sink whose name matches any of the given
-- patterns, a 10-line split appears at the bottom showing the backing
-- buffer in real time. Previous viewer windows are closed first so they
-- don't pile up. Focus stays in your current window.
--
-- Requires Neovim 0.10+ (uses nvim_open_win with split option).

local M = {}

---@class SinkViewerOpts
---@field pattern string|string[] Lua pattern(s) matched against the sink name
---@field height? integer      Split height in lines (default 10)
---@field separator? string    Fillchar for the horizontal separator (default "━")
---@field separator_fg? string Hex foreground color for the separator (default "#ff9e64")
---@field separator_bg? string Hex background color for the separator (default none)

---@param opts SinkViewerOpts
function M.setup(opts)
  opts = opts or {}
  local patterns = type(opts.pattern) == "table" and opts.pattern or { opts.pattern or "^anthropic/thinking" }
  local height = opts.height or 10
  local separator = opts.separator or "━"
  local separator_fg = opts.separator_fg or "#ff9e64"

  local separator_hl = "FlemmaSinkViewerSeparator"
  local hl_def = { fg = separator_fg, bold = true }
  if opts.separator_bg then
    hl_def.bg = opts.separator_bg
  end
  vim.api.nvim_set_hl(0, separator_hl, hl_def)

  local function matches(name)
    for _, p in ipairs(patterns) do
      if name:match(p) then
        return true
      end
    end
    return false
  end

  local group = vim.api.nvim_create_augroup("FlemmaSinkViewer", { clear = true })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "FlemmaSinkCreated",
    callback = function(event)
      local data = event.data
      if not data or not data.name or not matches(data.name) then
        return
      end

      local bufnr = data.bufnr
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      -- Close any existing viewer windows for sinks matching the same pattern
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) then
          local buf = vim.api.nvim_win_get_buf(win)
          local name = vim.api.nvim_buf_get_name(buf)
          local sink_name = name:match("^flemma://sink/(.+)#%d+$")
          if sink_name and matches(sink_name) then
            vim.api.nvim_win_close(win, true)
          end
        end
      end

      -- Split below the current window without stealing focus
      local parent_win = vim.api.nvim_get_current_win()
      local win = vim.api.nvim_open_win(bufnr, false, {
        split = "below",
        win = parent_win,
        height = height,
      })

      -- Style the separator — the window above owns the horizontal border
      local saved_fillchars = vim.wo[parent_win].fillchars
      local saved_winhighlight = vim.wo[parent_win].winhighlight
      vim.wo[parent_win].fillchars = "horiz:" .. separator .. ",horizup:" .. separator .. ",horizdown:" .. separator
      vim.wo[parent_win].winhighlight = "WinSeparator:" .. separator_hl

      -- Per-instance group for cleanup autocmds — cleared on each new viewer
      local instance_group = vim.api.nvim_create_augroup("FlemmaSinkViewerInstance", { clear = true })

      local function restore_parent()
        if vim.api.nvim_win_is_valid(parent_win) then
          vim.wo[parent_win].fillchars = saved_fillchars
          vim.wo[parent_win].winhighlight = saved_winhighlight
        end
        vim.api.nvim_clear_autocmds({ group = instance_group })
      end

      -- Restore parent highlights when the viewer window closes
      vim.api.nvim_create_autocmd("WinClosed", {
        group = instance_group,
        pattern = tostring(win),
        once = true,
        callback = restore_parent,
      })

      -- Auto-close when the sink is destroyed by the caller
      vim.api.nvim_create_autocmd("User", {
        group = instance_group,
        pattern = "FlemmaSinkDestroyed",
        callback = function(ev)
          if ev.data and ev.data.bufnr == bufnr then
            if vim.api.nvim_win_is_valid(win) then
              vim.api.nvim_win_close(win, true)
            end
            restore_parent()
          end
        end,
      })

      -- Auto-scroll to bottom on buffer changes; detach when window is gone
      vim.api.nvim_buf_attach(bufnr, false, {
        on_lines = function()
          if not vim.api.nvim_win_is_valid(win) then
            return true
          end
          vim.schedule(function()
            if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
              local count = vim.api.nvim_buf_line_count(bufnr)
              vim.api.nvim_win_set_cursor(win, { count, 0 })
            end
          end)
        end,
      })
    end,
  })
end

return M
