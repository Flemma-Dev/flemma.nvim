--- Hooks subsystem — dispatches User autocmds at lifecycle boundaries
--- so external plugins can react to Flemma events.
---
--- Internal name format: "domain:action" (e.g., "request:sending")
--- Autocmd pattern format: "Flemma<Domain><Action>" (e.g., "FlemmaRequestSending")
---
--- Colons separate domain from action. Hyphens separate words within
--- either segment. The transform TitleCases each word and strips both
--- delimiters, then prepends "Flemma".
---@class flemma.Hooks
local M = {}

local log = require("flemma.logging")
local notify = require("flemma.notify")

---@alias flemma.hooks.Name
---| "request:sending"
---| "request:finished"
---| "tool:executing"
---| "tool:completed"
---| "boot:complete"
---| "sink:created"
---| "sink:destroyed"
---| "config:updated"
---| "usage:estimated"
---| "conversation:idle"
---| "job:submitted"
---| "job:completed"
---| "autopilot:resume-scheduled"
---| "autopilot:resume-cancelled"
---| "autopilot:resumed"
---| "tool:approval-required"
---| "buffer:created"
---| "buffer:destroyed"

---@class flemma.hooks.RequestSendingData
---@field bufnr integer

---@class flemma.hooks.RequestFinishedData
---@field bufnr integer
---@field status "completed" | "cancelled" | "errored"
---@field request? flemma.session.Request The recorded session entry (present when status is "completed" and provider pricing was available)

---@class flemma.hooks.ToolExecutingData
---@field bufnr integer
---@field tool_name string
---@field tool_id string

---@class flemma.hooks.ToolCompletedData
---@field bufnr integer
---@field tool_name string
---@field tool_id string
---@field status "success" | "error"

---@class flemma.hooks.BootCompleteData -- no fields; hook carries no payload

---@class flemma.hooks.SinkCreatedData
---@field bufnr integer
---@field name string

---@class flemma.hooks.SinkDestroyedData
---@field bufnr integer
---@field name string

---@class flemma.hooks.ConfigUpdatedData -- no fields; hook carries no payload

---@class flemma.hooks.UsageEstimatedData
---@field bufnr integer

---@class flemma.hooks.ConversationIdleData
---@field bufnr integer

---@class flemma.hooks.JobSubmittedData
---@field bufnr integer
---@field job_id string
---@field tool_id string
---@field tool_name string
---@field active_count integer Number of background jobs in progress (executing + queued) after this submission

---@class flemma.hooks.JobCompletedData
---@field bufnr integer
---@field job_id string
---@field tool_id string
---@field tool_name string
---@field success boolean
---@field active_count integer Number of background jobs still in progress after this completion

---@class flemma.hooks.AutopilotResumeScheduledData
---@field bufnr integer
---@field delay_ms integer Timer duration in milliseconds

---@class flemma.hooks.AutopilotResumeCancelledData
---@field bufnr integer

---@class flemma.hooks.AutopilotResumedData
---@field bufnr integer

---@class flemma.hooks.ToolApprovalRequiredTool
---@field tool_id string
---@field tool_name string
---@field input table<string, any>

---@class flemma.hooks.ToolApprovalRequiredData
---@field bufnr integer
---@field tools flemma.hooks.ToolApprovalRequiredTool[]

---@class flemma.hooks.BufferCreatedData
---@field bufnr integer

---@class flemma.hooks.BufferDestroyedData
---@field bufnr integer

---@class flemma.hooks.Subscription
---@field off fun(self: flemma.hooks.Subscription): nil Unsubscribe this listener

---@type table<string, {callback: fun(data: table)}[]>
local subscribers = {}

---Survives module re-requires so test harness can set-and-forget.
---@type boolean
local force_sync = rawget(_G, "_flemma_hooks_force_sync") or false

local PREFIX = "Flemma"

---TitleCase a single word: "sending" -> "Sending"
---@param word string
---@return string
local function title_case(word)
  if word == "" then
    return ""
  end
  return word:sub(1, 1):upper() .. word:sub(2)
end

---Transform "domain:action" to "Flemma<Domain><Action>"
---Colons separate segments, hyphens separate words within segments.
---@param name string
---@return string
local function name_to_pattern(name)
  local parts = {}
  for segment in name:gmatch("[^:]+") do
    for word in segment:gmatch("[^-]+") do
      parts[#parts + 1] = title_case(word)
    end
  end
  return PREFIX .. table.concat(parts)
end

---Subscribe to a hook with a Lua callback.
---
---Internal subscribers fire synchronously before the User autocmd,
---in registration order. Errors in one subscriber do not prevent
---subsequent subscribers or the autocmd from firing.
---@overload fun(name: "request:sending", callback: fun(data: flemma.hooks.RequestSendingData)): flemma.hooks.Subscription
---@overload fun(name: "request:finished", callback: fun(data: flemma.hooks.RequestFinishedData)): flemma.hooks.Subscription
---@overload fun(name: "tool:executing", callback: fun(data: flemma.hooks.ToolExecutingData)): flemma.hooks.Subscription
---@overload fun(name: "tool:completed", callback: fun(data: flemma.hooks.ToolCompletedData)): flemma.hooks.Subscription
---@overload fun(name: "tool:approval-required", callback: fun(data: flemma.hooks.ToolApprovalRequiredData)): flemma.hooks.Subscription
---@overload fun(name: "boot:complete", callback: fun(data: flemma.hooks.BootCompleteData)): flemma.hooks.Subscription
---@overload fun(name: "sink:created", callback: fun(data: flemma.hooks.SinkCreatedData)): flemma.hooks.Subscription
---@overload fun(name: "sink:destroyed", callback: fun(data: flemma.hooks.SinkDestroyedData)): flemma.hooks.Subscription
---@overload fun(name: "config:updated", callback: fun(data: flemma.hooks.ConfigUpdatedData)): flemma.hooks.Subscription
---@overload fun(name: "usage:estimated", callback: fun(data: flemma.hooks.UsageEstimatedData)): flemma.hooks.Subscription
---@overload fun(name: "conversation:idle", callback: fun(data: flemma.hooks.ConversationIdleData)): flemma.hooks.Subscription
---@overload fun(name: "job:submitted", callback: fun(data: flemma.hooks.JobSubmittedData)): flemma.hooks.Subscription
---@overload fun(name: "job:completed", callback: fun(data: flemma.hooks.JobCompletedData)): flemma.hooks.Subscription
---@overload fun(name: "autopilot:resume-scheduled", callback: fun(data: flemma.hooks.AutopilotResumeScheduledData)): flemma.hooks.Subscription
---@overload fun(name: "autopilot:resume-cancelled", callback: fun(data: flemma.hooks.AutopilotResumeCancelledData)): flemma.hooks.Subscription
---@overload fun(name: "autopilot:resumed", callback: fun(data: flemma.hooks.AutopilotResumedData)): flemma.hooks.Subscription
---@overload fun(name: "buffer:created", callback: fun(data: flemma.hooks.BufferCreatedData)): flemma.hooks.Subscription
---@overload fun(name: "buffer:destroyed", callback: fun(data: flemma.hooks.BufferDestroyedData)): flemma.hooks.Subscription
---@param name flemma.hooks.Name Hook name in "domain:action" format
---@param callback fun(data: table) Subscriber function receiving the hook payload
---@return flemma.hooks.Subscription
function M.on(name, callback)
  local list = subscribers[name]
  if not list then
    list = {}
    subscribers[name] = list
  end
  local entry = { callback = callback }
  list[#list + 1] = entry
  return {
    off = function()
      local current = subscribers[name]
      if not current then
        return
      end
      for i, e in ipairs(current) do
        if e == entry then
          table.remove(current, i)
          return
        end
      end
    end,
  }
end

---@class flemma.hooks.DispatchOpts
---@field sync? boolean Fire subscribers synchronously instead of deferring via vim.schedule (default: false)

---Fire internal subscribers and the User autocmd for a hook.
---@param name string
---@param payload table
local function fire(name, payload)
  local list = subscribers[name]
  if list then
    for _, entry in ipairs(list) do
      local ok, err = pcall(entry.callback, payload)
      if not ok then
        local message = string.format("hook '%s' subscriber error: %s", name, tostring(err))
        log.warn(message)
        notify.warn(message)
      end
    end
  end
  local pattern = name_to_pattern(name)
  local ok, err = pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = pattern,
    data = payload,
  })
  if not ok then
    local message = string.format("hook '%s' handler error: %s", name, tostring(err))
    log.warn(message)
    notify.warn(message)
  end
end

---Dispatch a hook, firing internal subscribers then a User autocmd.
---
---By default, dispatch is asynchronous — subscribers run on the next
---event loop iteration via vim.schedule. Pass `{ sync = true }` when
---the dispatch site needs subscribers to complete before continuing
---(e.g., buffer:destroyed cleanup that precedes state teardown).
---
---The name is transformed from "domain:action" format to a
---"Flemma<Domain><Action>" autocmd pattern. Errors in individual
---handlers are caught and surfaced via log + flemma.notify but
---do not prevent subsequent handlers from firing.
---@overload fun(name: "request:sending", data: flemma.hooks.RequestSendingData, opts?: flemma.hooks.DispatchOpts)
---@overload fun(name: "request:finished", data: flemma.hooks.RequestFinishedData, opts?: flemma.hooks.DispatchOpts)
---@overload fun(name: "tool:executing", data: flemma.hooks.ToolExecutingData, opts?: flemma.hooks.DispatchOpts)
---@overload fun(name: "tool:completed", data: flemma.hooks.ToolCompletedData, opts?: flemma.hooks.DispatchOpts)
---@overload fun(name: "tool:approval-required", data: flemma.hooks.ToolApprovalRequiredData, opts?: flemma.hooks.DispatchOpts)
---@overload fun(name: "boot:complete", data?: flemma.hooks.BootCompleteData, opts?: flemma.hooks.DispatchOpts)
---@overload fun(name: "sink:created", data: flemma.hooks.SinkCreatedData, opts?: flemma.hooks.DispatchOpts)
---@overload fun(name: "sink:destroyed", data: flemma.hooks.SinkDestroyedData, opts?: flemma.hooks.DispatchOpts)
---@overload fun(name: "config:updated", data?: flemma.hooks.ConfigUpdatedData, opts?: flemma.hooks.DispatchOpts)
---@overload fun(name: "usage:estimated", data: flemma.hooks.UsageEstimatedData, opts?: flemma.hooks.DispatchOpts)
---@overload fun(name: "conversation:idle", data: flemma.hooks.ConversationIdleData, opts?: flemma.hooks.DispatchOpts)
---@overload fun(name: "job:submitted", data: flemma.hooks.JobSubmittedData, opts?: flemma.hooks.DispatchOpts)
---@overload fun(name: "job:completed", data: flemma.hooks.JobCompletedData, opts?: flemma.hooks.DispatchOpts)
---@overload fun(name: "autopilot:resume-scheduled", data: flemma.hooks.AutopilotResumeScheduledData, opts?: flemma.hooks.DispatchOpts)
---@overload fun(name: "autopilot:resume-cancelled", data: flemma.hooks.AutopilotResumeCancelledData, opts?: flemma.hooks.DispatchOpts)
---@overload fun(name: "autopilot:resumed", data: flemma.hooks.AutopilotResumedData, opts?: flemma.hooks.DispatchOpts)
---@overload fun(name: "buffer:created", data: flemma.hooks.BufferCreatedData, opts?: flemma.hooks.DispatchOpts)
---@overload fun(name: "buffer:destroyed", data: flemma.hooks.BufferDestroyedData, opts?: flemma.hooks.DispatchOpts)
---@param name flemma.hooks.Name Hook name in "domain:action" format
---@param data? table Payload passed to handlers
---@param opts? flemma.hooks.DispatchOpts
function M.dispatch(name, data, opts)
  local payload = data or {}
  if force_sync or (opts and opts.sync) then
    fire(name, payload)
  else
    vim.schedule(function()
      fire(name, payload)
    end)
  end
end

---Exposed for testing only. Do not use in production code.
---@param name string
---@return string
function M._name_to_pattern(name)
  return name_to_pattern(name)
end

---Force all dispatches to be synchronous. Exposed for testing only.
---Persists across module re-requires via a global sentinel.
---@param enabled boolean
function M._force_sync(enabled)
  force_sync = enabled
  rawset(_G, "_flemma_hooks_force_sync", enabled)
end

---Clear all internal subscribers. Exposed for testing only.
function M._clear_subscribers()
  subscribers = {}
end

return M
