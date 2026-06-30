--- Tests for flemma:jobs:status harness tool

package.loaded["flemma.state"] = nil
package.loaded["flemma.tools.definitions.harness.jobs"] = nil

local state = require("flemma.state")
local json = require("flemma.utilities.json")
local parser = require("flemma.parser")

---Build a minimal execution context with get_parsed_document support.
---@param bufnr integer
---@return table
local function make_ctx(bufnr)
  return {
    bufnr = bufnr,
    get_parsed_document = function(self)
      return parser.get_parsed_document(self.bufnr)
    end,
  }
end

describe("flemma.jobs.status", function()
  local jobs_module
  local execute

  before_each(function()
    package.loaded["flemma.tools.definitions.harness.jobs"] = nil
    package.loaded["flemma.parser"] = nil
    parser = require("flemma.parser")
    jobs_module = require("flemma.tools.definitions.harness.jobs")
    execute = jobs_module.definitions[1].execute
  end)

  it("exports a single definition with correct name", function()
    assert.equals(1, #jobs_module.definitions)
    assert.equals("flemma.jobs.status", jobs_module.definitions[1].name)
  end)

  it("is synchronous with disables_background and disables_save_to capabilities", function()
    local definition = jobs_module.definitions[1]
    assert.is_false(definition.async)
    assert.is_truthy(vim.tbl_contains(definition.capabilities, "disables_background"))
    assert.is_truthy(vim.tbl_contains(definition.capabilities, "disables_save_to"))
  end)

  describe("execute", function()
    it("returns 'running' for an active background job", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_01"] = {
          tool_id = "tool_01",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 1,
          end_line = 2,
          started_at = os.time() - 10,
          completed = false,
          placeholder_modified = true,
          job_id = "job_abc12",
        },
      }

      local result = execute({ job_id = "job_abc12" }, make_ctx(bufnr))
      assert.is_true(result.success)
      local data = json.decode(result.output)
      assert.equals("running", data.status)
      assert.equals("job_abc12", data.job_id)
      assert.equals("tool_01", data.tool_id)
      assert.equals("bash", data.tool_name)
      assert.truthy(data.elapsed_seconds >= 10)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("reports a completed but not yet drained job as completed with delivery pending", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_02"] = {
          tool_id = "tool_02",
          tool_name = "grep",
          bufnr = bufnr,
          start_line = 1,
          end_line = 2,
          started_at = os.time() - 10,
          completed = true,
          placeholder_modified = true,
          job_id = "job_def34",
        },
      }
      buffer_state.delivery_queue = {
        {
          job_id = "job_def34",
          tool_id = "tool_02",
          tool_name = "grep",
          result = { success = true, output = "matches found" },
          completed_at = os.time() - 7,
        },
      }

      local result = execute({ job_id = "job_def34" }, make_ctx(bufnr))
      assert.is_true(result.success)
      local data = json.decode(result.output)
      -- A bare "queued" reads as "waiting to start" to the model — the job has
      -- finished and its result is queued for delivery, so say exactly that.
      assert.equals("completed (delivery pending)", data.status)
      assert.equals("job_def34", data.job_id)
      assert.equals("tool_02", data.tool_id)
      assert.equals("grep", data.tool_name)
      -- elapsed_seconds freezes at the actual runtime (completed_at - started_at).
      -- A counter that keeps growing after completion compounds the "never
      -- started" misread.
      assert.equals(3, data.elapsed_seconds)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("reports a job in the completion queue as completed with delivery pending", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {}
      buffer_state.delivery_queue = {
        {
          job_id = "job_queue1",
          tool_id = "tool_q1",
          tool_name = "find",
          result = { success = true, output = "found it" },
        },
      }

      local result = execute({ job_id = "job_queue1" }, make_ctx(bufnr))
      assert.is_true(result.success)
      local data = json.decode(result.output)
      assert.equals("completed (delivery pending)", data.status)
      assert.equals("job_queue1", data.job_id)
      assert.equals("tool_q1", data.tool_id)
      assert.equals("find", data.tool_name)
      -- No pending entry → runtime unknown. Omit elapsed_seconds rather than
      -- report a misleading 0 ("just queued").
      assert.is_nil(data.elapsed_seconds)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("returns 'completed' when job result is present in buffer", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "**Job Result:** `job_done1`",
        "",
        "```",
        "all tests passed",
        "```",
      })
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {}
      buffer_state.delivery_queue = {}

      local result = execute({ job_id = "job_done1" }, make_ctx(bufnr))
      assert.is_true(result.success)
      local data = json.decode(result.output)
      assert.equals("completed", data.status)
      assert.equals("job_done1", data.job_id)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("returns 'completed (removed from conversation)' when job result was removed", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "@You:",
        "Hello",
      })
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {}
      buffer_state.delivery_queue = {}

      local result = execute({ job_id = "job_undone1" }, make_ctx(bufnr))
      assert.is_true(result.success)
      local data = json.decode(result.output)
      assert.equals("completed (removed from conversation)", data.status)
      assert.equals("job_undone1", data.job_id)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("does not match a foreground tool (no job_id)", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_fg"] = {
          tool_id = "tool_fg",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 1,
          end_line = 2,
          started_at = os.time(),
          completed = false,
          placeholder_modified = true,
        },
      }

      local result = execute({ job_id = "job_nope" }, make_ctx(bufnr))
      assert.is_true(result.success)
      local data = json.decode(result.output)
      assert.equals("completed (removed from conversation)", data.status)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("checks pending_executions before delivery_queue", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local buffer_state = state.get_buffer_state(bufnr)
      buffer_state.pending_executions = {
        ["tool_both"] = {
          tool_id = "tool_both",
          tool_name = "bash",
          bufnr = bufnr,
          start_line = 1,
          end_line = 2,
          started_at = os.time(),
          completed = false,
          placeholder_modified = true,
          job_id = "job_both",
        },
      }
      buffer_state.delivery_queue = {
        {
          job_id = "job_both",
          tool_id = "tool_both",
          tool_name = "bash",
          result = { success = true, output = "done" },
        },
      }

      local result = execute({ job_id = "job_both" }, make_ctx(bufnr))
      local data = json.decode(result.output)
      assert.equals("running", data.status)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
