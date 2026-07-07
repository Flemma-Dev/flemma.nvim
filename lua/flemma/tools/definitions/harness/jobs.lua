--- Harness tools: flemma.jobs.*
--- Allows the LLM to query the status of background jobs
---@class flemma.tools.definitions.harness.Jobs
---@field definitions flemma.tools.ToolDefinition[]
local M = {}

local json = require("flemma.utilities.json")
local log = require("flemma.logging")
local messages = require("flemma.messages")
local query = require("flemma.ast.query")
local s = require("flemma.schema")
local state = require("flemma.state")

M.definitions = {
  {
    name = "flemma.jobs.status",
    description = messages["tool.flemma.jobs.status.description"]{},
    strict = true,
    async = false,
    capabilities = { "disables_background", "disables_save_to" },
    ---@return flemma.tools.ToolPreview
    format_preview = function(input)
      return input.job_id
    end,
    input_schema = s.object({
      job_id = s.string():describe(messages["tool.flemma.jobs.status.input.job_id"]),
    }),
    ---@param input { job_id: string }
    ---@param ctx flemma.tools.ExecutionContext
    ---@return flemma.tools.ExecutionResult
    execute = function(input, ctx)
      local bufnr = ctx.bufnr
      local job_id = input.job_id
      log.debug("flemma.jobs.status: querying job " .. job_id .. " for buffer " .. bufnr)

      local buffer_state = state.get_buffer_state(bufnr)
      local pending = buffer_state.pending_executions or {}

      for tool_id, entry in pairs(pending) do
        if entry.job_id == job_id then
          local status = messages["tool.flemma.jobs.status.state_running"]{}
          local elapsed = os.time() - entry.started_at
          if entry.completed then
            -- The job has finished; its result sits in the delivery queue.
            -- Report it as completed — a bare "queued" reads as "waiting to
            -- start" to the model — and freeze elapsed at the actual runtime
            -- so it stops growing after completion.
            status = messages["tool.flemma.jobs.status.state_delivery_pending"]{}
            for _, delivery in ipairs(buffer_state.delivery_queue or {}) do
              if delivery.job_id == job_id and delivery.completed_at then
                elapsed = delivery.completed_at - entry.started_at
                break
              end
            end
          end
          log.debug("flemma.jobs.status: job " .. job_id .. " → " .. status .. " (elapsed=" .. elapsed .. "s)")
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
          log.debug("flemma.jobs.status: job " .. job_id .. " → completed (delivery pending) (in delivery_queue)")
          return {
            success = true,
            output = json.encode({
              status = messages["tool.flemma.jobs.status.state_delivery_pending"]{},
              job_id = job_id,
              tool_id = delivery.tool_id,
              tool_name = delivery.tool_name,
              -- No pending entry → runtime unknown. Omit elapsed_seconds
              -- rather than report a misleading 0 ("just queued").
            }),
          }
        end
      end

      local doc = ctx:get_parsed_document()
      local found_in_buffer = query.find_job_result(doc, job_id) ~= nil

      local status = found_in_buffer and messages["tool.flemma.jobs.status.state_completed"]{}
        or messages["tool.flemma.jobs.status.state_removed"]{}
      log.debug("flemma.jobs.status: job " .. job_id .. " → " .. status)
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
