--- Per-buffer FIFO queue for buffer-modifying operations.
--- Ensures writes execute in order and retries on textlock (E565) by
--- re-scheduling via vim.schedule when Neovim forbids buffer changes
--- (e.g., during getchar() in visual/operator-pending mode).
---@class flemma.buffer.WriteQueue
local M = {}

local log = require("flemma.logging")

local MAX_RETRIES = 10

---@class flemma.buffer.WriteQueueEntry
---@field fn fun()
---@field retries integer

---Per-buffer queue state with a head pointer and a deferred list for re-entrant items.
---@class flemma.buffer.WriteQueueState
---@field entries flemma.buffer.WriteQueueEntry[]
---@field head integer 1-based index of the next entry to process
---@field deferred flemma.buffer.WriteQueueEntry[] items enqueued re-entrantly during drain

---@type table<integer, flemma.buffer.WriteQueueState>
local queues = {}

---Whether a drain is already scheduled (per-buffer) to avoid duplicate scheduling.
---@type table<integer, boolean>
local drain_scheduled = {}

---Whether drain() is currently executing for a buffer (re-entrancy guard).
---@type table<integer, boolean>
local draining = {}

---Check whether an error string indicates a textlock (E565) error.
---@param err string
---@return boolean
local function is_textlock_error(err)
  return err:find("E565") ~= nil
end

---Compact the queue by removing processed entries when the head pointer
---has advanced past half the array, to avoid unbounded growth.
---@param queue_state flemma.buffer.WriteQueueState
local function maybe_compact(queue_state)
  if queue_state.head > math.max(#queue_state.entries / 2, 16) then
    local new_entries = {}
    for i = queue_state.head, #queue_state.entries do
      new_entries[#new_entries + 1] = queue_state.entries[i]
    end
    queue_state.entries = new_entries
    queue_state.head = 1
  end
end

---Move deferred (re-entrant) items to the end of the entries array.
---Called at the start of each drain cycle so that items enqueued from
---outside between drain cycles are positioned before re-entrant items.
---@param queue_state flemma.buffer.WriteQueueState
local function flush_deferred(queue_state)
  if #queue_state.deferred > 0 then
    for _, deferred_entry in ipairs(queue_state.deferred) do
      queue_state.entries[#queue_state.entries + 1] = deferred_entry
    end
    queue_state.deferred = {}
  end
end

---Drain the queue for a buffer: execute entries in FIFO order.
---At the start of each drain cycle, deferred (re-entrant) items from the
---previous cycle are appended to the entries array. This ensures items
---enqueued from outside between drain cycles execute before re-entrant ones.
---If an E565 textlock error is caught, restore modifiable state, stop, and re-schedule.
---@param bufnr integer
function M.drain(bufnr)
  drain_scheduled[bufnr] = false

  if draining[bufnr] then
    return -- Re-entrant call; handled by deferred list in enqueue
  end

  local queue_state = queues[bufnr]
  if not queue_state then
    return
  end

  -- Flush deferred items from a previous drain cycle to the end of entries
  flush_deferred(queue_state)

  if queue_state.head > #queue_state.entries then
    queues[bufnr] = nil
    return
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    queues[bufnr] = nil
    return
  end

  draining[bufnr] = true

  -- Snapshot the end boundary so items added re-entrantly during this
  -- drain cycle are deferred (they go into queue_state.deferred, not entries)
  local snapshot_end = #queue_state.entries

  while queue_state.head <= snapshot_end do
    local entry = queue_state.entries[queue_state.head]

    -- Save modifiable state so we can restore it on E565 failure.
    -- vim.bo[] reads/writes are NOT affected by textlock.
    local saved_modifiable = vim.bo[bufnr].modifiable

    local ok, err = pcall(entry.fn)

    if ok then
      queue_state.head = queue_state.head + 1
    elseif type(err) == "string" and is_textlock_error(err) then
      -- Restore modifiable to pre-fn state (fn may have set it to true before crashing)
      vim.bo[bufnr].modifiable = saved_modifiable

      entry.retries = entry.retries + 1
      if entry.retries > MAX_RETRIES then
        log.error("writequeue: dropping operation after " .. MAX_RETRIES .. " textlock retries")
        queue_state.head = queue_state.head + 1
        -- Continue to try next entry
      else
        -- Feed Escape to break the getchar() wait that is holding the textlock.
        -- nvim_input is NOT restricted by textlock. The Esc cancels the pending
        -- text-object/operator (e.g., targets.vim's 'i' in 'vi"'), releasing
        -- the textlock so the retry on the next event loop tick succeeds.
        vim.api.nvim_input("\27")
        -- Stop draining and re-schedule
        draining[bufnr] = nil
        M.schedule_drain(bufnr)
        return
      end
    else
      -- Non-textlock error — restore modifiable, log, discard, continue
      vim.bo[bufnr].modifiable = saved_modifiable
      log.error("writequeue: operation failed: " .. tostring(err))
      queue_state.head = queue_state.head + 1
    end
  end

  draining[bufnr] = nil
  maybe_compact(queue_state)

  -- Check if there are still items pending (deferred items from this cycle
  -- or leftover entries). If so, don't clean up — a subsequent enqueue or
  -- scheduled drain will pick them up.
  if #queue_state.deferred == 0 and queue_state.head > #queue_state.entries then
    queues[bufnr] = nil
  end
end

---Schedule a drain on the next event loop iteration (deduped per-buffer).
---@param bufnr integer
function M.schedule_drain(bufnr)
  if drain_scheduled[bufnr] then
    return
  end
  drain_scheduled[bufnr] = true
  vim.schedule(function()
    M.drain(bufnr)
  end)
end

---Enqueue a buffer-modifying operation. Executes immediately if the queue is
---empty and no drain is in progress; otherwise appends and the in-progress or
---scheduled drain will pick it up.
---Re-entrant calls (enqueue during drain) go to a deferred list that is
---flushed at the start of the next drain cycle, ensuring items enqueued from
---outside the drain take priority.
---@param bufnr integer
---@param fn fun()
function M.enqueue(bufnr, fn)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local entry = { fn = fn, retries = 0 }

  -- Re-entrant enqueue during drain: defer to next drain cycle
  if draining[bufnr] then
    local queue_state = queues[bufnr]
    if queue_state then
      queue_state.deferred[#queue_state.deferred + 1] = entry
    end
    return
  end

  local queue_state = queues[bufnr]
  local was_idle = not queue_state or (queue_state.head > #queue_state.entries and #queue_state.deferred == 0)

  if not queue_state then
    queue_state = { entries = {}, head = 1, deferred = {} }
    queues[bufnr] = queue_state
  end

  queue_state.entries[#queue_state.entries + 1] = entry

  -- Start draining when the queue was idle. When items are already pending
  -- (e.g., from an E565 retry), a scheduled drain is already queued — don't
  -- start a second drain. But when only deferred (re-entrant) items remain
  -- and no drain is scheduled, we must start one to avoid stalling.
  if was_idle or not drain_scheduled[bufnr] then
    M.drain(bufnr)
  end
end

---Enqueue a buffer-modifying operation, scheduling it to the next event loop
---iteration first. This replaces the common `vim.schedule(function() ... end)`
---pattern at call sites that receive callbacks from luv (libuv) contexts.
---@param bufnr integer
---@param fn fun()
function M.schedule(bufnr, fn)
  vim.schedule(function()
    M.enqueue(bufnr, fn)
  end)
end

---Clear all pending operations for a buffer.
---Any in-progress drain will stop after its current entry because the
---head pointer will be past the (now empty) entries array.
---@param bufnr integer
function M.clear(bufnr)
  queues[bufnr] = nil
  drain_scheduled[bufnr] = nil
  draining[bufnr] = nil
end

return M
