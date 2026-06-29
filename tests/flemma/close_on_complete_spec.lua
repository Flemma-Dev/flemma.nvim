local registry = require("flemma.provider.registry")

describe("close_on_complete", function()
  describe("capability defaults", function()
    local original_defaults, original_models

    before_each(function()
      original_defaults = vim.deepcopy(registry.defaults)
      original_models = vim.deepcopy(registry.models)
    end)

    after_each(function()
      registry.clear()
      registry.setup()
      registry.defaults = original_defaults
      registry.models = original_models
    end)

    it("defaults to true for built-in providers", function()
      local caps = registry.get_capabilities("anthropic")
      assert.is_not_nil(caps)
      assert.is_true(caps.close_on_complete)
    end)

    it("defaults to true when not specified in inline registration", function()
      registry.register("test-provider", {
        module = "flemma.provider.adapters.openai",
        capabilities = {
          supports_reasoning = false,
          supports_thinking_budget = false,
          outputs_thinking = false,
        },
        display_name = "Test",
      })
      local caps = registry.get_capabilities("test-provider")
      assert.is_not_nil(caps)
      assert.is_true(caps.close_on_complete)
    end)

    it("can be set to false to opt out", function()
      registry.register("persistent-stream", {
        module = "flemma.provider.adapters.openai",
        capabilities = {
          supports_reasoning = false,
          supports_thinking_budget = false,
          outputs_thinking = false,
          close_on_complete = false,
        },
        display_name = "Persistent",
      })
      local caps = registry.get_capabilities("persistent-stream")
      assert.is_not_nil(caps)
      assert.is_false(caps.close_on_complete)
    end)
  end)

  describe("stream termination", function()
    it("terminates a hanging process after response completes", function()
      local script_path = vim.fn.tempname() .. "_hang_test.sh"
      local f = io.open(script_path, "w")
      f:write("#!/bin/sh\n")
      -- Emit HTTP headers then SSE data with response.completed, then hang
      f:write('printf "HTTP/1.1 200 OK\\r\\n"\n')
      f:write('printf "Content-Type: text/event-stream\\r\\n"\n')
      f:write('printf "\\r\\n"\n')
      f:write('printf "data: {\\"type\\":\\"response.output_text.delta\\",\\"delta\\":\\"Hello\\"}\\n\\n"\n')
      f:write(
        'printf "data: {\\"type\\":\\"response.completed\\",\\"response\\":{\\"usage\\":{\\"input_tokens\\":10,\\"output_tokens\\":5}}}\\n\\n"\n'
      )
      -- Hang indefinitely (simulates Codex backend not closing the connection)
      f:write("sleep 120\n")
      f:close()
      os.execute("chmod +x " .. script_path)

      local content_received = ""
      local response_complete_fired = false
      local request_complete_code = nil ---@type integer|nil

      -- Build a minimal provider that processes Responses API events
      local openai_responses = require("flemma.provider.openai_responses")
      local provider = openai_responses._new_concrete({ model = "test", max_tokens = 100 })

      local callbacks = {
        on_content = function(text)
          content_received = content_received .. text
        end,
        on_response_complete = function()
          response_complete_fired = true
        end,
        on_usage = function() end,
        on_error = function() end,
        on_thinking = function() end,
      }

      -- Launch the hanging script as a job (bypassing client.send_request
      -- fixture mechanism to test real process lifecycle)
      local hang_job_id
      hang_job_id = vim.fn.jobstart({ "sh", script_path }, {
        detach = true,
        on_stdout = function(_, data)
          if not data then
            return
          end
          for _, line in ipairs(data) do
            if line and #line > 0 then
              provider:process_response_line(line, callbacks)
            end
          end
          -- Simulate close_on_complete: after response.completed, stop the job
          if response_complete_fired and hang_job_id then
            vim.defer_fn(function()
              pcall(vim.fn.jobstop, hang_job_id)
            end, 200)
          end
        end,
        on_exit = function(_, code)
          request_complete_code = code
        end,
      })

      assert.is_not_nil(hang_job_id)
      assert.is_true(hang_job_id > 0)

      -- Wait for the response to complete and the process to be killed
      -- (should happen within ~1s: SSE data + 200ms grace + kill)
      vim.wait(3000, function()
        return request_complete_code ~= nil
      end, 50)

      assert.is_true(response_complete_fired, "response.completed should have fired")
      assert.is_not_nil(request_complete_code, "process should have been terminated")
      assert.is_true(content_received:find("Hello") ~= nil, "should have received content before termination")

      -- Cleanup
      os.remove(script_path)
    end)

    it("does not terminate when close_on_complete is false", function()
      local script_path = vim.fn.tempname() .. "_no_close_test.sh"
      local f = io.open(script_path, "w")
      f:write("#!/bin/sh\n")
      f:write('printf "HTTP/1.1 200 OK\\r\\n"\n')
      f:write('printf "Content-Type: text/event-stream\\r\\n"\n')
      f:write('printf "\\r\\n"\n')
      f:write(
        'printf "data: {\\"type\\":\\"response.completed\\",\\"response\\":{\\"usage\\":{\\"input_tokens\\":1,\\"output_tokens\\":1}}}\\n\\n"\n'
      )
      -- Exit after a short delay (simulates a well-behaved server)
      f:write("sleep 0.3\n")
      f:close()
      os.execute("chmod +x " .. script_path)

      local response_complete_fired = false
      local request_complete_code = nil ---@type integer|nil
      local close_on_complete = false

      local openai_responses = require("flemma.provider.openai_responses")
      local provider = openai_responses._new_concrete({ model = "test", max_tokens = 100 })

      local callbacks = {
        on_content = function() end,
        on_response_complete = function()
          response_complete_fired = true
        end,
        on_usage = function() end,
        on_error = function() end,
        on_thinking = function() end,
      }

      local this_job_id
      this_job_id = vim.fn.jobstart({ "sh", script_path }, {
        detach = true,
        on_stdout = function(_, data)
          if not data then
            return
          end
          for _, line in ipairs(data) do
            if line and #line > 0 then
              provider:process_response_line(line, callbacks)
            end
          end
          -- Respect close_on_complete = false: do NOT terminate
          if response_complete_fired and close_on_complete and this_job_id then
            vim.defer_fn(function()
              pcall(vim.fn.jobstop, this_job_id)
            end, 200)
          end
        end,
        on_exit = function(_, code)
          request_complete_code = code
        end,
      })

      -- Wait for the process to exit naturally (0.3s sleep in script)
      vim.wait(2000, function()
        return request_complete_code ~= nil
      end, 50)

      assert.is_true(response_complete_fired)
      assert.is_not_nil(request_complete_code)
      -- Process exited naturally (code 0), not killed
      assert.are.equal(0, request_complete_code)

      os.remove(script_path)
    end)
  end)
end)
