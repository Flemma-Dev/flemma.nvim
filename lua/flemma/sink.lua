--- Buffer-backed sink for streaming data accumulation
---
--- Replaces all in-memory string/table accumulators with a uniform API backed
--- by hidden scratch buffers. Callers interact through write/read methods and
--- never touch the underlying Neovim buffer directly.

---@class flemma.SinkModule
local M = {}

local log = require("flemma.logging")

local DEFAULT_FLUSH_INTERVAL = 50

---@class flemma.SinkCreateOpts
---@field name string Sink name (e.g. "stream/curl-42"), used in buffer name
---@field flush_interval? integer Milliseconds between auto-flushes (default 50)
---@field on_line? fun(line: string) Real-time callback fired for each complete line

---@class flemma.Sink
---@field private _bufnr integer Hidden scratch buffer number
---@field private _name string Sink name (e.g. "stream/curl-42")
---@field private _destroyed boolean Whether the sink has been destroyed
---@field private _partial string Incomplete trailing line (line framing)
---@field private _pending string[] Batched lines not yet flushed to buffer
---@field private _timer uv.uv_timer_t|nil Batch flush timer
---@field private _flush_interval integer Milliseconds between auto-flushes
---@field private _on_line? fun(line: string) Real-time line callback
---@field private _first_drain boolean Whether the first drain has occurred
local Sink = {}
Sink.__index = Sink

---Construct a new Sink instance and start its batch timer.
---@param bufnr integer
---@param name string
---@param flush_interval integer
---@param on_line? fun(line: string)
---@return flemma.Sink
---@private
function Sink.new(bufnr, name, flush_interval, on_line)
  local self = setmetatable({
    _bufnr = bufnr,
    _name = name,
    _destroyed = false,
    _partial = "",
    _pending = {},
    _timer = nil,
    _flush_interval = flush_interval,
    _on_line = on_line,
    _first_drain = true,
  }, Sink)

  -- Start the batch flush timer.
  -- Capture the pending table as an upvalue so the libuv callback avoids
  -- private field access through `self` — a LuaLS limitation where closures
  -- inside constructors can't see private fields of the captured object.
  local pending = self._pending
  local sink = self
  local timer = vim.uv.new_timer()
  if timer then
    self._timer = timer
    timer:start(flush_interval, flush_interval, function()
      if #pending > 0 then
        vim.schedule(function()
          Sink._drain(sink)
        end)
      end
    end)
  end

  return self
end

---Create a new sink backed by a hidden scratch buffer.
---
---The buffer is unlisted, has no swapfile, no undo, and is named
---`flemma://sink/<name>`. The batch timer is started but `_drain()` is a
---stub until write/flush are implemented in subsequent tasks.
---@param opts flemma.SinkCreateOpts
---@return flemma.Sink
function M.create(opts)
  if not opts or not opts.name or opts.name == "" then
    error("flemma.sink.create: opts.name is required")
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].undolevels = -1
  vim.bo[bufnr].bufhidden = "hide"
  vim.api.nvim_buf_set_name(bufnr, "flemma://sink/" .. opts.name)

  local flush_interval = opts.flush_interval or DEFAULT_FLUSH_INTERVAL

  return Sink.new(bufnr, opts.name, flush_interval, opts.on_line)
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

---Flush pending data to the buffer and finalize the partial line.
---
---Stub for now — full implementation comes in a subsequent task.
---@private
function Sink:_drain()
  -- Stub: will be implemented in Task 5
end

---Flush all pending data (including the partial line) to the Neovim buffer.
---
---This is a display concern — reads are always complete regardless of flush
---state. Stub for now.
function Sink:flush()
  -- Stub: will be implemented in Task 5
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
