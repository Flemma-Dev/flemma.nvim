--- Buffer state management and UI support for Flemma
local M = {}

local state = require("flemma.state")

-- Store buffer-local state
local buffer_state = {}

function M.init_buffer(bufnr)
  buffer_state[bufnr] = {
    current_request = nil,
    request_cancelled = false,
    spinner_timer = nil,
    current_usage = {
      input_tokens = 0,
      output_tokens = 0,
    },
  }
end

function M.cleanup_buffer(bufnr)
  if buffer_state[bufnr] then
    if buffer_state[bufnr].current_request then
      vim.fn.jobstop(buffer_state[bufnr].current_request)
    end
    if buffer_state[bufnr].spinner_timer then
      vim.fn.timer_stop(buffer_state[bufnr].spinner_timer)
    end
    buffer_state[bufnr] = nil
  end
end

function M.get_state(bufnr)
  if not buffer_state[bufnr] then
    M.init_buffer(bufnr)
  end
  return buffer_state[bufnr]
end

function M.set_state(bufnr, key, value)
  if not buffer_state[bufnr] then
    M.init_buffer(bufnr)
  end
  buffer_state[bufnr][key] = value
end

function M.buffer_cmd(bufnr, cmd)
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return
  end
  vim.fn.win_execute(winid, "noautocmd " .. cmd)
end

function M.auto_write_buffer(bufnr)
  if state.get_config().editing.auto_write and vim.bo[bufnr].modified then
    M.buffer_cmd(bufnr, "silent! write")
  end
end

return M
