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

---@class flemma.hooks.Handle
---@field off fun(): nil Unsubscribe this listener

---@type table<string, {callback: fun(data: table)}[]>
local subscribers = {}

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
---@overload fun(name: "request:sending", callback: fun(data: flemma.hooks.RequestSendingData)): flemma.hooks.Handle
---@overload fun(name: "request:finished", callback: fun(data: flemma.hooks.RequestFinishedData)): flemma.hooks.Handle
---@overload fun(name: "tool:executing", callback: fun(data: flemma.hooks.ToolExecutingData)): flemma.hooks.Handle
---@overload fun(name: "tool:completed", callback: fun(data: flemma.hooks.ToolCompletedData)): flemma.hooks.Handle
---@overload fun(name: "boot:complete", callback: fun(data: flemma.hooks.BootCompleteData)): flemma.hooks.Handle
---@overload fun(name: "sink:created", callback: fun(data: flemma.hooks.SinkCreatedData)): flemma.hooks.Handle
---@overload fun(name: "sink:destroyed", callback: fun(data: flemma.hooks.SinkDestroyedData)): flemma.hooks.Handle
---@overload fun(name: "config:updated", callback: fun(data: flemma.hooks.ConfigUpdatedData)): flemma.hooks.Handle
---@overload fun(name: "usage:estimated", callback: fun(data: flemma.hooks.UsageEstimatedData)): flemma.hooks.Handle
---@overload fun(name: "conversation:idle", callback: fun(data: flemma.hooks.ConversationIdleData)): flemma.hooks.Handle
---@overload fun(name: "job:submitted", callback: fun(data: flemma.hooks.JobSubmittedData)): flemma.hooks.Handle
---@overload fun(name: "job:completed", callback: fun(data: flemma.hooks.JobCompletedData)): flemma.hooks.Handle
---@overload fun(name: "autopilot:resume-scheduled", callback: fun(data: flemma.hooks.AutopilotResumeScheduledData)): flemma.hooks.Handle
---@overload fun(name: "autopilot:resume-cancelled", callback: fun(data: flemma.hooks.AutopilotResumeCancelledData)): flemma.hooks.Handle
---@overload fun(name: "autopilot:resumed", callback: fun(data: flemma.hooks.AutopilotResumedData)): flemma.hooks.Handle
---@param name flemma.hooks.Name Hook name in "domain:action" format
---@param callback fun(data: table) Subscriber function receiving the hook payload
---@return flemma.hooks.Handle
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

---Dispatch a hook, firing internal subscribers then a User autocmd.
---
---The name is transformed from "domain:action" format to a
---"Flemma<Domain><Action>" autocmd pattern. Errors in individual
---handlers are caught and surfaced via log + flemma.notify but
---do not prevent subsequent handlers from firing.
---@overload fun(name: "request:sending", data: flemma.hooks.RequestSendingData)
---@overload fun(name: "request:finished", data: flemma.hooks.RequestFinishedData)
---@overload fun(name: "tool:executing", data: flemma.hooks.ToolExecutingData)
---@overload fun(name: "tool:completed", data: flemma.hooks.ToolCompletedData)
---@overload fun(name: "boot:complete", data?: flemma.hooks.BootCompleteData)
---@overload fun(name: "sink:created", data: flemma.hooks.SinkCreatedData)
---@overload fun(name: "sink:destroyed", data: flemma.hooks.SinkDestroyedData)
---@overload fun(name: "config:updated", data?: flemma.hooks.ConfigUpdatedData)
---@overload fun(name: "usage:estimated", data: flemma.hooks.UsageEstimatedData)
---@overload fun(name: "conversation:idle", data: flemma.hooks.ConversationIdleData)
---@overload fun(name: "job:submitted", data: flemma.hooks.JobSubmittedData)
---@overload fun(name: "job:completed", data: flemma.hooks.JobCompletedData)
---@overload fun(name: "autopilot:resume-scheduled", data: flemma.hooks.AutopilotResumeScheduledData)
---@overload fun(name: "autopilot:resume-cancelled", data: flemma.hooks.AutopilotResumeCancelledData)
---@overload fun(name: "autopilot:resumed", data: flemma.hooks.AutopilotResumedData)
---@param name flemma.hooks.Name Hook name in "domain:action" format
---@param data? table Payload passed to handlers
function M.dispatch(name, data)
  local payload = data or {}
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

---Exposed for testing only. Do not use in production code.
---@param name string
---@return string
function M._name_to_pattern(name)
  return name_to_pattern(name)
end

---Clear all internal subscribers. Exposed for testing only.
function M._clear_subscribers()
  subscribers = {}
end

return M
