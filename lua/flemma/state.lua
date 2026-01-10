--- State management for Flemma plugin
--- Centralizes all shared plugin state (global and per-buffer)

local M = {}
local session_module = require("flemma.session")

-- Local state variables
local config = {}
local provider = nil
local session = session_module.Session.new()

-- Buffer-local state storage
local buffer_states = {}

-- Configuration management
function M.set_config(conf)
  config = conf or {}
end

function M.get_config()
  return config
end

-- Provider management
function M.set_provider(p)
  provider = p
end

function M.get_provider()
  return provider
end

-- Session management
function M.get_session()
  return session
end

function M.reset_session()
  session = session_module.Session.new()
end

-- Buffer state management

--- Initialize buffer state with default values
---@param bufnr number Buffer number
local function init_buffer(bufnr)
  buffer_states[bufnr] = {
    current_request = nil,
    request_cancelled = false,
    spinner_timer = nil,
    api_error_occurred = false,
    inflight_usage = {
      input_tokens = 0,
      output_tokens = 0,
      thoughts_tokens = 0,
    },
  }
end

--- Get buffer-local state, initializing if needed
---@param bufnr number Buffer number
---@return table buffer_state
function M.get_buffer_state(bufnr)
  if not buffer_states[bufnr] then
    init_buffer(bufnr)
  end
  return buffer_states[bufnr]
end

--- Set a specific key in buffer state
---@param bufnr number Buffer number
---@param key string State key
---@param value any State value
function M.set_buffer_state(bufnr, key, value)
  if not buffer_states[bufnr] then
    init_buffer(bufnr)
  end
  buffer_states[bufnr][key] = value
end

--- Cleanup buffer state and any active jobs/timers
--- Called on buffer lifecycle events (BufWipeout/BufUnload/BufDelete)
---@param bufnr number Buffer number
function M.cleanup_buffer_state(bufnr)
  local st = buffer_states[bufnr]
  if st then
    if st.current_request then
      -- Mark as cancelled and use client to terminate the job cleanly
      st.request_cancelled = true
      local client = require("flemma.client")
      client.cancel_request(st.current_request)
    end
    if st.spinner_timer then
      vim.fn.timer_stop(st.spinner_timer)
    end
    buffer_states[bufnr] = nil
  end
end

return M
