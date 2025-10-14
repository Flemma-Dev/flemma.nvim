--- Buffer state management and UI support for Flemma
local M = {}

local state = require("flemma.state")
local client = require("flemma.client")

-- Store buffer-local state
local buffer_state = {}

function M.init_buffer(bufnr)
  buffer_state[bufnr] = {
    current_request = nil,
    request_cancelled = false,
    spinner_timer = nil,
    inflight_usage = {
      input_tokens = 0,
      output_tokens = 0,
      thoughts_tokens = 0,
    },
  }
end

-- Cleanup any outstanding jobs/timers and remove stored state for a buffer.
-- Intended to be called on buffer lifecycle events (BufWipeout/BufUnload/BufDelete) for chat buffers.
function M.cleanup_buffer(bufnr)
  local st = buffer_state[bufnr]
  if st then
    if st.current_request then
      -- Mark as cancelled and use client to terminate the job cleanly
      st.request_cancelled = true
      client.cancel_request(st.current_request)
    end
    if st.spinner_timer then
      vim.fn.timer_stop(st.spinner_timer)
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
