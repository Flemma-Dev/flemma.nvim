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

---@alias flemma.hooks.Name
---| "request:sending"
---| "request:finished"
---| "tool:executing"
---| "tool:finished"
---| "boot:complete"
---| "sink:created"
---| "sink:destroyed"
---| "config:updated"

---@class flemma.hooks.RequestSendingData
---@field bufnr integer

---@class flemma.hooks.RequestFinishedData
---@field bufnr integer
---@field status "completed" | "cancelled" | "errored"

---@class flemma.hooks.ToolExecutingData
---@field bufnr integer
---@field tool_name string
---@field tool_id string

---@class flemma.hooks.ToolFinishedData
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

---Dispatch a hook, firing a User autocmd.
---
---The name is transformed from "domain:action" format to a
---"Flemma<Domain><Action>" autocmd pattern. Errors in consumer
---handlers are caught and surfaced via log + vim.notify.
---@overload fun(name: "request:sending", data: flemma.hooks.RequestSendingData)
---@overload fun(name: "request:finished", data: flemma.hooks.RequestFinishedData)
---@overload fun(name: "tool:executing", data: flemma.hooks.ToolExecutingData)
---@overload fun(name: "tool:finished", data: flemma.hooks.ToolFinishedData)
---@overload fun(name: "boot:complete", data?: flemma.hooks.BootCompleteData)
---@overload fun(name: "sink:created", data: flemma.hooks.SinkCreatedData)
---@overload fun(name: "sink:destroyed", data: flemma.hooks.SinkDestroyedData)
---@overload fun(name: "config:updated", data?: flemma.hooks.ConfigUpdatedData)
---@param name flemma.hooks.Name Hook name in "domain:action" format
---@param data? table Payload passed to autocmd handlers via ev.data
function M.dispatch(name, data)
  local pattern = name_to_pattern(name)
  local ok, err = pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = pattern,
    data = data or {},
  })
  if not ok then
    local message = string.format("hook '%s' handler error: %s", name, tostring(err))
    log.warn(message)
    vim.notify("Flemma: " .. message, vim.log.levels.WARN)
  end
end

---Exposed for testing only. Do not use in production code.
---@param name string
---@return string
function M._name_to_pattern(name)
  return name_to_pattern(name)
end

return M
