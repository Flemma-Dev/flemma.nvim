--- Inline rejection popup — floating input overlaid on tool result fence
---@class flemma.ui.Rejection
local M = {}

local buffer_utils = require("flemma.utilities.buffer")
local config_facade = require("flemma.config")
local executor = require("flemma.tools.executor")
local messages = require("flemma.messages")
local navigation = require("flemma.navigation")
local notify = require("flemma.notify")
local parser = require("flemma.parser")
local ast = require("flemma.ast")
local tool_context = require("flemma.tools.context")

local rejection_ns = vim.api.nvim_create_namespace("flemma_rejection")

---@class flemma.ui.rejection.State
---@field float_buf integer Float buffer handle
---@field float_win integer Float window handle
---@field parent_buf integer Parent buffer handle
---@field parent_win integer Parent window handle
---@field tool_id string Tool ID captured at open time
---@field parent_cursorline boolean Saved cursorline state for parent window
---@field augroup integer Autocmd group handle
---@field status_extmark_id integer|nil Overlay extmark replacing (pending) with (rejected)

---Active popup state, nil when no popup is open.
---@type flemma.ui.rejection.State|nil
local active = nil

---Close the active popup and clean up all resources.
---@param state flemma.ui.rejection.State
local function close(state)
  if vim.fn.getcmdwintype() ~= "" then
    vim.api.nvim_create_autocmd("CmdwinLeave", {
      once = true,
      callback = function()
        vim.schedule(function()
          close(state)
        end)
      end,
    })
    return
  end
  pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
  if state.status_extmark_id and vim.api.nvim_buf_is_valid(state.parent_buf) then
    pcall(vim.api.nvim_buf_del_extmark, state.parent_buf, rejection_ns, state.status_extmark_id)
  end
  if vim.api.nvim_win_is_valid(state.float_win) then
    vim.api.nvim_win_close(state.float_win, true)
  end
  vim.cmd("stopinsert")
  if vim.api.nvim_win_is_valid(state.parent_win) then
    vim.wo[state.parent_win].cursorline = state.parent_cursorline
  end
  if active == state then
    active = nil
  end
end

---Confirm the rejection with the current popup content.
---@param state flemma.ui.rejection.State
local function confirm(state)
  local lines = vim.api.nvim_buf_get_lines(state.float_buf, 0, -1, false)
  local message = table.concat(lines, "\n")
  local tool_id = state.tool_id
  local parent_buf = state.parent_buf
  local parent_win = state.parent_win
  close(state)
  if not vim.api.nvim_buf_is_valid(parent_buf) then
    return
  end
  if vim.api.nvim_win_is_valid(parent_win) then
    vim.api.nvim_set_current_win(parent_win)
  end
  local ok, err = executor.reject(parent_buf, tool_id, message)
  if ok then
    navigation.advance_to_next_pending(parent_buf, tool_id)
  else
    notify.error(err or "Reject failed")
  end
end

---Find the opening and closing fence lines within a tool_result segment.
---@param bufnr integer
---@param result_seg flemma.ast.ToolResultSegment
---@return integer|nil open_lnum 1-based line number of the opening fence
---@return integer|nil close_lnum 1-based line number of the closing fence
local function find_fence_lines(bufnr, result_seg)
  local start = result_seg.position.start_line
  local end_line = result_seg.position.end_line --[[@as integer]]
  local open_lnum = nil
  local close_lnum = nil
  for lnum = start + 1, end_line do
    local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
    if line and line:match("^`+") then
      if not open_lnum then
        open_lnum = lnum
      else
        close_lnum = lnum
        break
      end
    end
  end
  return open_lnum, close_lnum
end

---Compute float geometry: bufpos anchor, col offset, width, initial/max height.
---Uses screenpos() to measure actual visual distance between fences,
---accounting for virt_lines (tool previews, approval prompt).
---@param parent_win integer
---@param open_lnum integer 1-based line number of the opening fence
---@param close_lnum integer|nil 1-based line number of the closing fence
---@return integer fence_line_0 Zero-indexed fence line for bufpos
---@return integer col_offset Gutter width (skip sign/number columns)
---@return integer width Available text area width
---@return integer initial_height Visual lines between fences (at least 1)
---@return integer max_height Maximum popup height before scrolling
local function compute_geometry(parent_win, open_lnum, close_lnum)
  local fence_line_0 = open_lnum - 1
  local gutter = buffer_utils.get_gutter_width(parent_win)
  local win_width = vim.api.nvim_win_get_width(parent_win)
  local wininfo = vim.fn.getwininfo(parent_win)[1]
  local win_top = wininfo.winrow
  local win_bottom = wininfo.winrow + wininfo.height - 1
  local open_pos = vim.fn.screenpos(parent_win, open_lnum, 1)
  local close_pos = close_lnum and vim.fn.screenpos(parent_win, close_lnum, 1) or nil
  local effective_open = open_pos.row > 0 and open_pos.row or win_top
  local effective_close = (close_pos and close_pos.row > 0) and close_pos.row or win_bottom
  local max_height = math.max(1, win_bottom - effective_open - 1)
  local initial_height = math.max(1, effective_close - effective_open - 1)
  initial_height = math.min(initial_height, max_height)
  return fence_line_0, gutter, win_width - gutter, initial_height, max_height
end

---Set up buffer-local keymaps on the float buffer.
---@param state flemma.ui.rejection.State
local function setup_keymaps(state)
  local buf = state.float_buf
  local opts = { buffer = buf, nowait = true }

  vim.keymap.set("i", "<CR>", function()
    confirm(state)
  end, opts)
  vim.keymap.set("i", "<C-c>", function()
    close(state)
  end, opts)

  vim.keymap.set("n", "<CR>", function()
    confirm(state)
  end, opts)
  vim.keymap.set("n", "q", function()
    close(state)
  end, opts)
  vim.keymap.set("n", "<Esc>", function()
    close(state)
  end, opts)
  vim.keymap.set("n", "<C-c>", function()
    close(state)
  end, opts)
end

---Set up autocmds for resize and cleanup.
---@param state flemma.ui.rejection.State
---@param initial_height integer
---@param max_height integer
local function setup_autocmds(state, initial_height, max_height)
  local group = vim.api.nvim_create_augroup("FlemmaRejectionPopup", { clear = true })
  state.augroup = group

  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    group = group,
    buffer = state.float_buf,
    callback = function()
      if not vim.api.nvim_win_is_valid(state.float_win) then
        return
      end
      local line_count = vim.api.nvim_buf_line_count(state.float_buf)
      local height = math.max(line_count, initial_height)
      height = math.min(height, max_height)
      vim.api.nvim_win_set_height(state.float_win, height)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload" }, {
    group = group,
    buffer = state.parent_buf,
    callback = function()
      close(state)
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(state.float_win),
    callback = function()
      close(state)
    end,
  })
end

---Fall back to vim.ui.input for rejection when the popup is disabled.
---@param bufnr integer
local function fallback_input(bufnr)
  vim.ui.input({ prompt = "Flemma: Rejection reason (optional): " }, function(input)
    if input == nil then
      return
    end
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    local message = nil
    if input ~= "" then
      message = messages.render("tool-rejected--feedback", { reason = input })
    end
    local ok, err = executor.reject_at_cursor(bufnr, message)
    if not ok then
      notify.error(err or "Reject failed")
    end
  end)
end

---Open the rejection popup for the tool at cursor.
---Falls back to vim.ui.input when ui.rejection.enabled is false.
---@param bufnr integer Parent buffer handle
function M.open(bufnr)
  local rejection_config = config_facade.get().ui.rejection
  if not rejection_config.enabled then
    fallback_input(bufnr)
    return
  end

  if active then
    close(active)
  end

  local parent_win = vim.api.nvim_get_current_win()

  local cursor_pos = vim.api.nvim_win_get_cursor(parent_win)
  local ctx, err = tool_context.resolve(bufnr, { row = cursor_pos[1], col = cursor_pos[2] })
  if not ctx then
    notify.error(err or "No tool call found")
    return
  end

  local doc = parser.get_parsed_document(bufnr)
  local result_seg = ast.find_tool_sibling(doc, ctx.node)
  if not result_seg or result_seg.kind ~= "tool_result" then
    notify.error("No tool result placeholder for " .. ctx.tool_id)
    return
  end
  ---@cast result_seg flemma.ast.ToolResultSegment

  local open_lnum, close_lnum = find_fence_lines(bufnr, result_seg)
  if not open_lnum then
    notify.error("No fence found in tool result for " .. ctx.tool_id)
    return
  end

  local fence_line_0, col_offset, width, initial_height, max_height =
    compute_geometry(parent_win, open_lnum, close_lnum)

  local float_buf = buffer_utils.create_scratch_buffer({ bufhidden = "wipe", undolevels = false })
  vim.b[float_buf].completion = rejection_config.completion

  local prefill = "User feedback: "
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, { prefill })

  local float_win = vim.api.nvim_open_win(float_buf, true, {
    relative = "win",
    win = parent_win,
    bufpos = { fence_line_0, 0 },
    row = 0,
    col = col_offset,
    width = width,
    height = initial_height,
    border = { "", "╌", "", "", "", "╌", "", "" },
    style = "minimal",
    noautocmd = true,
    zindex = 50,
  })

  vim.wo[float_win].wrap = true
  vim.wo[float_win].linebreak = true
  vim.wo[float_win].cursorline = false
  vim.wo[float_win].number = false
  vim.wo[float_win].relativenumber = false
  vim.wo[float_win].signcolumn = "no"
  vim.wo[float_win].winblend = rejection_config.winblend
  vim.api.nvim_set_option_value(
    "winhighlight",
    "Normal:FlemmaRejection,NormalFloat:FlemmaRejection,FloatBorder:FlemmaRejectionBorder",
    { win = float_win }
  )

  local parent_cursorline = vim.wo[parent_win].cursorline
  vim.wo[parent_win].cursorline = false

  local status_extmark_id = nil
  local header_line_0 = result_seg.position.start_line - 1
  local header_text = vim.api.nvim_buf_get_lines(bufnr, header_line_0, header_line_0 + 1, false)[1] or ""
  local pending_start = header_text:find("%(pending%)")
  if pending_start then
    status_extmark_id = vim.api.nvim_buf_set_extmark(bufnr, rejection_ns, header_line_0, pending_start - 1, {
      end_col = pending_start - 1 + #"(pending)",
      virt_text = { { "(rejected)", "FlemmaToolResultRejected" } },
      virt_text_pos = "overlay",
      hl_mode = "combine",
    })
  end

  local state = {
    float_buf = float_buf,
    float_win = float_win,
    parent_buf = bufnr,
    parent_win = parent_win,
    tool_id = ctx.tool_id,
    parent_cursorline = parent_cursorline,
    status_extmark_id = status_extmark_id,
    augroup = 0,
  }
  active = state

  setup_keymaps(state)
  setup_autocmds(state, initial_height, max_height)

  vim.cmd("startinsert!")
end

---Whether a rejection popup is currently active.
---@return boolean
function M.is_open()
  return active ~= nil
end

return M
