--- Bash tool definition
--- Execute bash commands and return stdout/stderr
---@class flemma.tools.definitions.Bash
---@field definitions flemma.tools.ToolDefinition[]
local M = {}

M.definitions = {
  {
    name = "bash",
    description = "Execute a bash command and return stdout/stderr. "
      .. "The command runs in the user's shell environment with their permissions.",
    input_schema = {
      type = "object",
      properties = {
        command = {
          type = "string",
          description = "The bash command to execute",
        },
        timeout = {
          type = "number",
          description = "Timeout in seconds (default: 30)",
        },
      },
      required = { "command" },
    },
    async = true,
    execute = function(input, callback)
      local cmd = input.command
      if not cmd or cmd == "" then
        callback({ success = false, error = "No command provided" })
        return nil
      end

      local state = require("flemma.state")
      local config = state.get_config()
      local default_timeout = (config.tools and config.tools.default_timeout) or 30
      local timeout = input.timeout or default_timeout

      local stdout = {}
      local stderr = {}
      local job_exited = false

      local job_opts = {
        on_stdout = function(_, data)
          if data then
            vim.list_extend(stdout, data)
          end
        end,
        on_stderr = function(_, data)
          if data then
            vim.list_extend(stderr, data)
          end
        end,
        on_exit = function(_, code)
          job_exited = true
          vim.schedule(function()
            -- Trim trailing empty string from vim.fn.jobstart output
            if #stdout > 0 and stdout[#stdout] == "" then
              table.remove(stdout)
            end
            if #stderr > 0 and stderr[#stderr] == "" then
              table.remove(stderr)
            end

            local output = table.concat(stdout, "\n")
            local err_output = table.concat(stderr, "\n")

            if code ~= 0 then
              local error_msg = string.format("Command failed with exit code %d", code)
              if err_output ~= "" then
                error_msg = error_msg .. ": " .. err_output
              end
              callback({
                success = false,
                error = error_msg,
                output = output,
              })
            else
              callback({
                success = true,
                output = output ~= "" and output or err_output,
              })
            end
          end)
        end,
      }

      -- Apply bash-specific config
      if config.tools and config.tools.bash then
        if config.tools.bash.cwd then
          job_opts.cwd = config.tools.bash.cwd
        end
        if config.tools.bash.env then
          job_opts.env = config.tools.bash.env
        end
      end

      local shell = (config.tools and config.tools.bash and config.tools.bash.shell) or "bash"
      local job_id = vim.fn.jobstart({ shell, "-c", cmd }, job_opts)

      if job_id <= 0 then
        callback({ success = false, error = "Failed to start job" })
        return nil
      end

      -- Setup timeout
      local timer = vim.uv.new_timer()
      timer:start(
        timeout * 1000,
        0,
        vim.schedule_wrap(function()
          if not job_exited then
            vim.fn.jobstop(job_id)
            callback({
              success = false,
              error = string.format("Command timed out after %d seconds.", timeout),
            })
          end
          if not timer:is_closing() then
            timer:close()
          end
        end)
      )

      -- Return cancel function
      return function()
        if not timer:is_closing() then
          timer:close()
        end
        if not job_exited then
          pcall(vim.fn.jobstop, job_id)
        end
      end
    end,
  },
}

return M
