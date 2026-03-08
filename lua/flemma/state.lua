--- State management for Flemma plugin
--- Centralizes all shared plugin state (global and per-buffer)
---@class flemma.State
local M = {}

local session_module = require("flemma.session")
local client = require("flemma.client")
local writequeue = require("flemma.buffer.writequeue")

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
---@field spinner_preview_text string|nil Thinking preview text for the spinner timer to render
---@field autopilot_override? boolean Per-buffer autopilot override (set from frontmatter, nil = use global config)
---@field auto_closed_folds? table<string, boolean>
---@field pending_folds? table<string, boolean> Fold IDs that were attempted but failed to close (eligible for retry)
---@field fold_completed_tick? integer Last changedtick processed by fold_completed_blocks (prevents redundant folding)
---@field ui_update_tick? integer Last changedtick processed by update_ui (gates CursorHold redundancy)
---@field autopilot? flemma.autopilot.BufferState Per-buffer autopilot state machine
---@field tool_indicators? table<string, flemma.ui.ToolIndicator> Per-tool execution indicator state
---@field pending_executions? table<string, flemma.tools.PendingExecution> In-flight tool executions keyed by tool_id
---@field cursorline_prev_row? integer Last cursor row (0-indexed) where the CursorLine overlay was placed
---@field cursorline_extmark_id? integer Stable extmark ID for the CursorLine overlay
---@field diagnostics_previous_request? string Raw JSON of the previous request sent from this buffer
---@field diagnostics_current_request? string Raw JSON of the most recent request sent from this buffer
---@field _diagnostics_raw_json? string Temporary storage for raw JSON during request lifecycle

---@diagnostic disable-next-line: missing-fields
local config = {} ---@type flemma.Config
---@type flemma.provider.Base|nil
local provider = nil

---@type table<integer, flemma.state.BufferState>
local buffer_states = {}

---@type table<string, fun(bufnr: integer)>
local cleanup_hooks = {}

---Register a buffer cleanup hook. Called during cleanup_buffer_state().
---Used by modules that state cannot require directly (circular dependency).
---@param name string Hook identifier (for idempotent registration)
---@param fn fun(bufnr: integer) Cleanup function
function M.register_cleanup(name, fn)
  cleanup_hooks[name] = fn
end

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
  return session_module.get()
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

---Iterate all active buffer states (bufnr, state pairs).
---Does NOT initialize missing entries — only visits buffers that already have state.
---@return fun(t: table<integer, flemma.state.BufferState>, k?: integer): integer, flemma.state.BufferState
---@return table<integer, flemma.state.BufferState>
function M.each_buffer_state()
  return pairs(buffer_states)
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
      st.request_cancelled = true
      client.cancel_request(st.current_request)
    end
    if st.spinner_timer then
      vim.fn.timer_stop(st.spinner_timer)
    end
  end
  -- Run registered cleanup hooks (executor, notifications) before clearing state.
  -- Hooks may access buffer state (e.g., executor), so this runs before nil.
  for _, fn in pairs(cleanup_hooks) do
    pcall(fn, bufnr)
  end
  buffer_states[bufnr] = nil
  writequeue.clear(bufnr)
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
