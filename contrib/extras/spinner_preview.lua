--- Spinner preview — shows all Flemma spinner animations in a floating window.
--- Run with:  nvim +"luafile contrib/extras/spinner_preview.lua"

-- Make flemma modules requireable
vim.opt.rtp:prepend(".")

local spinners = require("flemma.ui.spinners")

local LABELS = { "waiting", "thinking", "streaming", "buffering", "tool" }
local HIGHLIGHTS = {
  waiting = "DiagnosticInfo",
  thinking = "DiagnosticHint",
  streaming = "DiagnosticOk",
  buffering = "DiagnosticWarn",
  tool = "DiagnosticError",
}

local INTERVAL_MS = 100
local MIDDLE_DOT = " · "

-- Build buffer content: each spinner gets two lines (content + blank separator)
local lines = {}
for i, label in ipairs(LABELS) do
  local frames = spinners.FRAMES[label]
  lines[#lines + 1] = frames[1] .. " " .. label .. MIDDLE_DOT .. "0s"
  if i < #LABELS then
    lines[#lines + 1] = ""
  end
end

local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
vim.bo[bufnr].modifiable = false
vim.bo[bufnr].bufhidden = "wipe"

-- Sizing
local width = 40
local height = #lines
local ui = vim.api.nvim_list_uis()[1] or { width = 80, height = 24 }
local row = math.floor((ui.height - height) / 2)
local col = math.floor((ui.width - width) / 2)

local winid = vim.api.nvim_open_win(bufnr, true, {
  relative = "editor",
  row = row,
  col = col,
  width = width,
  height = height,
  style = "minimal",
  border = "rounded",
  title = " Spinner Preview ",
  title_pos = "center",
})

local ns = vim.api.nvim_create_namespace("spinner_preview")
local tick = 0
local start = vim.uv.hrtime()

local timer = vim.uv.new_timer()
timer:start(
  0,
  INTERVAL_MS,
  vim.schedule_wrap(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      timer:stop()
      timer:close()
      return
    end

    tick = tick + 1
    local elapsed = string.format("%.1fs", (vim.uv.hrtime() - start) / 1e9)

    vim.bo[bufnr].modifiable = true
    local new_lines = {}
    for i, label in ipairs(LABELS) do
      local frames = spinners.FRAMES[label]
      local speed = spinners.SPEED[label] or 1
      local frame = frames[(math.floor(tick / speed) % #frames) + 1]
      new_lines[#new_lines + 1] = frame .. " " .. label .. MIDDLE_DOT .. elapsed
      if i < #LABELS then
        new_lines[#new_lines + 1] = ""
      end
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
    vim.bo[bufnr].modifiable = false

    -- Apply highlights
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    for i, label in ipairs(LABELS) do
      local line_idx = (i - 1) * 2
      vim.api.nvim_buf_set_extmark(bufnr, ns, line_idx, 0, {
        end_col = #new_lines[line_idx + 1],
        hl_group = HIGHLIGHTS[label],
      })
    end
  end)
)

-- Close on q, <Esc>, or window close
local closed = false
local function close()
  if closed then
    return
  end
  closed = true
  timer:stop()
  timer:close()
  if vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_close(winid, true)
  end
end

vim.keymap.set("n", "q", close, { buffer = bufnr })
vim.keymap.set("n", "<Esc>", close, { buffer = bufnr })
vim.api.nvim_create_autocmd("WinClosed", {
  buffer = bufnr,
  once = true,
  callback = close,
})
