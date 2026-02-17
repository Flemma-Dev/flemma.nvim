--- State management for Flemma plugin
--- Centralizes all shared plugin state (global and per-buffer)
---@class flemma.State
local M = {}

local session_module = require("flemma.session")

---@class flemma.state.InflightUsage
---@field input_tokens number
---@field output_tokens number
---@field thoughts_tokens number
---@field output_has_thoughts boolean
---@field cache_read_input_tokens number
---@field cache_creation_input_tokens number

---@class flemma.state.BufferState
---@field current_request integer|nil Job ID of the active cURL request
---@field request_cancelled boolean Whether the current request has been cancelled
---@field spinner_timer integer|nil Timer ID for the spinner animation
---@field api_error_occurred boolean Whether an API error occurred during the last request
---@field inflight_usage flemma.state.InflightUsage Token counters accumulated during streaming
---@field locked boolean Whether the buffer is locked (non-modifiable) for request/tool execution
---@field waiting_for_tools? boolean Whether a send is queued waiting for async tool resolution
---@field ast_cache? { changedtick: integer, document: flemma.ast.DocumentNode } Cached parsed AST
---@field spinner_extmark_id integer|nil Extmark ID for the spinner/thinking preview
---@field spinner_line_idx0 integer|nil 0-indexed line of the spinner extmark

---@diagnostic disable-next-line: missing-fields
local config = {} ---@type flemma.Config
---@type flemma.provider.Base|nil
local provider = nil
local session = session_module.Session.new()

---@type table<integer, flemma.state.BufferState>
local buffer_states = {}

---Set the global plugin configuration
---@param conf flemma.Config
function M.set_config(conf)
  config = conf
end

---Get the global plugin configuration
---@return flemma.Config
function M.get_config()
  return config
end

---Set the active provider instance
---@param p flemma.provider.Base|nil
function M.set_provider(p)
  provider = p
end

---Get the active provider instance
---@return flemma.provider.Base|nil
function M.get_provider()
  return provider
end

---Get the global session (tracks all requests across buffers)
---@return flemma.session.Session
function M.get_session()
  return session
end

-- Buffer state management

---Initialize buffer state with default values
---@param bufnr integer Buffer number
local function init_buffer(bufnr)
  buffer_states[bufnr] = {
    current_request = nil,
    request_cancelled = false,
    spinner_timer = nil,
    api_error_occurred = false,
    locked = false,
    waiting_for_tools = false,
    inflight_usage = {
      input_tokens = 0,
      output_tokens = 0,
      thoughts_tokens = 0,
      output_has_thoughts = false,
      cache_read_input_tokens = 0,
      cache_creation_input_tokens = 0,
    },
  }
end

---Get buffer-local state, initializing if needed
---@param bufnr integer Buffer number
---@return flemma.state.BufferState buffer_state
function M.get_buffer_state(bufnr)
  if not buffer_states[bufnr] then
    init_buffer(bufnr)
  end
  return buffer_states[bufnr]
end

---Set a specific key in buffer state
---@param bufnr integer Buffer number
---@param key string State key
---@param value any State value
function M.set_buffer_state(bufnr, key, value)
  if not buffer_states[bufnr] then
    init_buffer(bufnr)
  end
  buffer_states[bufnr][key] = value
end

---Cleanup buffer state and any active jobs/timers
---Called on buffer lifecycle events (BufWipeout/BufUnload/BufDelete)
---@param bufnr integer Buffer number
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
  -- Clean up tool executor state
  local ok, executor = pcall(require, "flemma.tools.executor")
  if ok then
    executor.cleanup_buffer(bufnr)
  end
  -- Clean up autopilot state
  require("flemma.autopilot").cleanup_buffer(bufnr)
  -- Clean up any notifications associated with this buffer
  require("flemma.notify").cleanup_buffer(bufnr)
end

---Lock a buffer (mark non-modifiable for request/tool execution)
---@param bufnr integer
function M.lock_buffer(bufnr)
  local bs = M.get_buffer_state(bufnr)
  bs.locked = true
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.bo[bufnr].modifiable = false
  end
end

---Unlock a buffer (restore modifiable after request/tool execution completes)
---@param bufnr integer
function M.unlock_buffer(bufnr)
  local bs = M.get_buffer_state(bufnr)
  bs.locked = false
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.bo[bufnr].modifiable = true
  end
end

return M
