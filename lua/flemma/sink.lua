--- Buffer-backed sink for streaming data accumulation
---
--- Replaces all in-memory string/table accumulators with a uniform API backed
--- by hidden scratch buffers. Callers interact through write/read methods and
--- never touch the underlying Neovim buffer directly.

---@class flemma.SinkModule
local M = {}

local log = require("flemma.logging")

local DEFAULT_FLUSH_INTERVAL = 50
local next_buffer_id = 0

---@class flemma.SinkCreateOpts
---@field name string Sink name (e.g. "stream/curl-42"), used in buffer name
---@field flush_interval? integer Milliseconds between auto-flushes (default 50)
---@field on_line? fun(line: string) Real-time callback fired for each complete line

---@class flemma.Sink
---@field private _bufnr integer Hidden scratch buffer number (-1 before materialization)
---@field private _name string Sink name (e.g. "stream/curl-42")
---@field private _destroyed boolean Whether the sink has been destroyed
---@field private _partial string Incomplete trailing line (line framing)
---@field private _pending string[] Batched lines not yet flushed to buffer
---@field private _timer uv.uv_timer_t|nil Batch flush timer
---@field private _flush_interval integer Milliseconds between auto-flushes
---@field private _on_line? fun(line: string) Real-time line callback
---@field private _first_drain boolean Whether the first drain has occurred
---@field private _buffer_has_partial boolean Whether the buffer's last line is a display copy of _partial
---@field private _materialized boolean Whether the backing buffer has been created
local Sink = {}
Sink.__index = Sink

---Construct a new Sink instance (lazy — no buffer or timer until first write).
---@param name string
---@param flush_interval integer
---@param on_line? fun(line: string)
---@return flemma.Sink
---@private
function Sink.new(name, flush_interval, on_line)
  return setmetatable({
    _bufnr = -1,
    _name = name,
    _destroyed = false,
    _partial = "",
    _pending = {},
    _timer = nil,
    _flush_interval = flush_interval,
    _on_line = on_line,
    _first_drain = true,
    _buffer_has_partial = false,
    _materialized = false,
  }, Sink)
end

---Create the backing buffer and start the batch timer.
---Called automatically on first write(); idempotent.
---@private
function Sink:_materialize()
  if self._materialized or self._destroyed then
    return
  end
  self._materialized = true

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].undolevels = -1
  vim.bo[bufnr].bufhidden = "hide"
  next_buffer_id = next_buffer_id + 1
  vim.api.nvim_buf_set_name(bufnr, "flemma://sink/" .. self._name .. "#" .. next_buffer_id)
  self._bufnr = bufnr

  -- Start the batch flush timer.
  -- INVARIANT: _drain() clears _pending in-place (nil-per-element) to
  -- preserve the table reference. Never replace _pending with a new table.
  local sink = self
  local timer = vim.uv.new_timer()
  if timer then
    self._timer = timer
    timer:start(self._flush_interval, self._flush_interval, function()
      vim.schedule(function()
        Sink._drain(sink)
      end)
    end)
  end

  vim.api.nvim_exec_autocmds("User", {
    pattern = "FlemmaSinkCreated",
    data = { name = self._name, bufnr = bufnr },
  })
end

---Create a new sink.
---
---The sink starts lazy — no buffer or timer is allocated until the first
---`write()` or `write_lines()` call. This avoids creating resources for
---sinks that may never receive data (e.g., thinking sinks when the model
---produces no thinking output).
---@param opts flemma.SinkCreateOpts
---@return flemma.Sink
function M.create(opts)
  if not opts or not opts.name or opts.name == "" then
    error("flemma.sink.create: opts.name is required")
  end

  return Sink.new(opts.name, opts.flush_interval or DEFAULT_FLUSH_INTERVAL, opts.on_line)
end

---Write raw data to the sink with automatic line framing
---Lines are split on \n; partial trailing data is buffered until the next write.
---Fires on_line callback for each complete line.
---@param chunk string
function Sink:write(chunk)
  if type(chunk) ~= "string" then
    error("sink:write(): expected string, got " .. type(chunk))
  end
  if self._destroyed then
    return
  end
  if chunk == "" then
    return
  end

  self:_materialize()

  local input = self._partial .. chunk
  local lines = vim.split(input, "\n", { plain = true })

  -- Last element is the new partial (empty if chunk ended with \n)
  self._partial = table.remove(lines)

  -- All preceding elements are complete lines
  for _, line in ipairs(lines) do
    if self._on_line then
      local ok, err = pcall(self._on_line, line)
      if not ok then
        log.error("sink on_line callback error: " .. tostring(err))
      end
    end
    table.insert(self._pending, line)
  end
end

---Write pre-framed lines to the sink
---If a partial line is buffered from a previous write(), it is flushed as a
---complete line before the new lines are appended.
---@param lines string[]
function Sink:write_lines(lines)
  if type(lines) ~= "table" then
    error("sink:write_lines(): expected table, got " .. type(lines))
  end
  if self._destroyed then
    return
  end
  if #lines == 0 then
    return
  end

  self:_materialize()

  -- Flush any pending partial as a complete line
  if self._partial ~= "" then
    local flushed = self._partial
    self._partial = ""
    if self._on_line then
      local ok, err = pcall(self._on_line, flushed)
      if not ok then
        log.error("sink on_line callback error: " .. tostring(err))
      end
    end
    table.insert(self._pending, flushed)
  end

  for _, line in ipairs(lines) do
    if self._on_line then
      local ok, err = pcall(self._on_line, line)
      if not ok then
        log.error("sink on_line callback error: " .. tostring(err))
      end
    end
    table.insert(self._pending, line)
  end
end

---Assemble complete content from all three sources (buffer + pending + partial)
---@return string[]
---@private
function Sink:_assemble_lines()
  -- 1. Lines already flushed to the Neovim buffer
  local buffer_lines = {}
  if vim.api.nvim_buf_is_valid(self._bufnr) then
    buffer_lines = vim.api.nvim_buf_get_lines(self._bufnr, 0, -1, false)
    -- Fresh buffer has {""}; treat as empty
    if #buffer_lines == 1 and buffer_lines[1] == "" and self._first_drain then
      buffer_lines = {}
    elseif self._buffer_has_partial and #buffer_lines > 0 then
      -- The buffer's last line is a display copy of _partial; exclude it
      -- to avoid double-counting (it's added back from _partial below)
      table.remove(buffer_lines)
    end
  end

  -- 2. Pending lines (batched, not yet flushed to buffer)
  local all_lines = {}
  vim.list_extend(all_lines, buffer_lines)
  vim.list_extend(all_lines, self._pending)

  -- 3. Partial line (incomplete trailing data)
  if self._partial ~= "" then
    table.insert(all_lines, self._partial)
  end

  return all_lines
end

---Read full accumulated content as a string
---Assembles from buffer + pending + partial without flushing.
---@return string
function Sink:read()
  if self._destroyed then
    error("sink already destroyed")
  end
  local lines = self:_assemble_lines()
  return table.concat(lines, "\n")
end

---Read full accumulated content as a lines table
---Assembles from buffer + pending + partial without flushing.
---@return string[]
function Sink:read_lines()
  if self._destroyed then
    error("sink already destroyed")
  end
  return self:_assemble_lines()
end

---Drain pending lines and current partial to the Neovim buffer
---
---Complete lines from `_pending` are appended. The current `_partial` is written
---as the buffer's last line for character-by-character display. The `on_line`
---callback is unaffected — it only fires in `write()` when a newline completes
---a line, never from `_drain()`.
---@private
function Sink:_drain()
  if self._destroyed or not self._materialized then
    return
  end
  if not vim.api.nvim_buf_is_valid(self._bufnr) then
    -- Buffer was deleted externally; transition to destroyed
    self._destroyed = true
    if self._timer and not self._timer:is_closing() then
      self._timer:stop()
      self._timer:close()
    end
    self._timer = nil
    return
  end

  local has_new_pending = #self._pending > 0
  local has_partial = self._partial ~= ""

  -- Nothing to do: no new complete lines and no partial state to update
  if not has_new_pending and not has_partial and not self._buffer_has_partial then
    return
  end

  -- Build lines to write: pending complete lines + current partial (if any)
  local lines_to_write = {}
  for i = 1, #self._pending do
    lines_to_write[#lines_to_write + 1] = self._pending[i]
    self._pending[i] = nil
  end
  if has_partial then
    lines_to_write[#lines_to_write + 1] = self._partial
  end

  if self._first_drain then
    -- Replace the default empty first line instead of appending
    self._first_drain = false
    if #lines_to_write > 0 then
      vim.api.nvim_buf_set_lines(self._bufnr, 0, -1, false, lines_to_write)
    end
  elseif self._buffer_has_partial then
    -- Replace the old partial (last line) and append new content after it
    vim.api.nvim_buf_set_lines(self._bufnr, -2, -1, false, lines_to_write)
  elseif #lines_to_write > 0 then
    vim.api.nvim_buf_set_lines(self._bufnr, -1, -1, false, lines_to_write)
  end

  self._buffer_has_partial = has_partial
end

---Flush all pending data (including partial) to the Neovim buffer
---This is for display purposes; reads already assemble from all sources.
function Sink:flush()
  if self._destroyed or not self._materialized then
    return
  end

  -- Flush partial as a line
  if self._partial ~= "" then
    table.insert(self._pending, self._partial)
    self._partial = ""
  end

  self:_drain()
end

---Destroy the sink, releasing the buffer and stopping the timer.
---
---If the buffer is currently visible in a window, sets `bufhidden=wipe` so
---it survives until the window closes. Otherwise deletes immediately.
---Double-destroy is a silent no-op.
function Sink:destroy()
  if self._destroyed then
    return
  end

  self:flush()

  -- Stop and release the timer
  if self._timer then
    self._timer:stop()
    if not self._timer:is_closing() then
      self._timer:close()
    end
    self._timer = nil
  end

  self._destroyed = true

  -- Nothing to clean up if the buffer was never created
  if not self._materialized then
    return
  end

  vim.api.nvim_exec_autocmds("User", {
    pattern = "FlemmaSinkDestroyed",
    data = { name = self._name, bufnr = self._bufnr },
  })

  -- Check if the buffer is still valid before operating on it
  if not vim.api.nvim_buf_is_valid(self._bufnr) then
    return
  end

  -- Check visibility: if viewed, defer wipe to window close
  local windows = vim.fn.win_findbuf(self._bufnr)
  if #windows > 0 then
    vim.bo[self._bufnr].bufhidden = "wipe"
    log.debug("sink '" .. self._name .. "': buffer visible, deferring wipe")
  else
    vim.api.nvim_buf_delete(self._bufnr, { force = true })
    log.debug("sink '" .. self._name .. "': buffer deleted")
  end
end

---Check whether the sink has been destroyed.
---@return boolean
function Sink:is_destroyed()
  return self._destroyed
end

return M
