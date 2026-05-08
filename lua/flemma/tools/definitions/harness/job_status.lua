--- Harness tool: flemma:job_status
--- Allows the LLM to query the status of a background job by its job ID
---@class flemma.tools.definitions.harness.JobStatus
---@field definitions flemma.tools.ToolDefinition[]
local M = {}

local json = require("flemma.utilities.json")
local log = require("flemma.logging")
local s = require("flemma.schema")
local state = require("flemma.state")

M.definitions = {
  {
    name = "flemma:job_status",
    description = "Check the status of a background job. "
      .. "Returns whether the job is still running, queued for delivery, or already completed. "
      .. "Use this to check on long-running background tasks instead of retrying them.",
    strict = true,
    async = false,
    backgroundable = false,
    input_schema = s.object({
      job_id = s.string("The background job ID (e.g., 'bg_xxx') from the tool result placeholder."),
    }),
    ---@param input { job_id: string }
    ---@param ctx flemma.tools.ExecutionContext
    ---@return flemma.tools.ExecutionResult
    execute = function(input, ctx)
      local bufnr = ctx.bufnr
      local job_id = input.job_id
      log.debug("flemma:job_status: querying job " .. job_id .. " for buffer " .. bufnr)

      local buffer_state = state.get_buffer_state(bufnr)
      local pending = buffer_state.pending_executions or {}

      for tool_id, entry in pairs(pending) do
        if entry.job_id == job_id then
          local elapsed = os.time() - entry.started_at
          local status = entry.completed and "queued" or "running"
          log.debug("flemma:job_status: job " .. job_id .. " → " .. status .. " (elapsed=" .. elapsed .. "s)")
          return {
            success = true,
            output = json.encode({
              status = status,
              job_id = job_id,
              tool_id = tool_id,
              tool_name = entry.tool_name,
              elapsed_seconds = elapsed,
            }),
          }
        end
      end

      local queue = buffer_state.delivery_queue or {}
      for _, delivery in ipairs(queue) do
        if delivery.job_id == job_id then
          log.debug("flemma:job_status: job " .. job_id .. " → queued (in delivery_queue)")
          return {
            success = true,
            output = json.encode({
              status = "queued",
              job_id = job_id,
              tool_id = delivery.tool_id,
              tool_name = delivery.tool_name,
              elapsed_seconds = 0,
            }),
          }
        end
      end

      local doc = ctx:get_parsed_document()
      local found_in_buffer = false
      for _, msg in ipairs(doc.messages) do
        for _, seg in ipairs(msg.segments) do
          if seg.kind == "job_result" and seg.job_id == job_id then
            found_in_buffer = true
            break
          end
        end
        if found_in_buffer then
          break
        end
      end

      local status = found_in_buffer and "completed" or "completed (removed from conversation)"
      log.debug("flemma:job_status: job " .. job_id .. " → " .. status)
      return {
        success = true,
        output = json.encode({
          status = status,
          job_id = job_id,
          tool_id = nil,
          tool_name = nil,
          elapsed_seconds = nil,
        }),
      }
    end,
  },
}

return M
