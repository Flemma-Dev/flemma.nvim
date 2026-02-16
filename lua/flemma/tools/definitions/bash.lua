--- Bash tool definition
--- Execute bash commands and return stdout/stderr
--- Truncation logic ported from pi by Mario Zechner (https://github.com/badlogic/pi-mono)
--- Original: MIT License, Copyright (c) 2025 Mario Zechner
---@class flemma.tools.definitions.Bash
---@field definitions flemma.tools.ToolDefinition[]
local M = {}

local truncate = require("flemma.tools.truncate")

M.definitions = {
  {
    name = "bash",
    description = "Execute a bash command in the current working directory. "
      .. "Returns stdout and stderr. Output is truncated to last "
      .. truncate.MAX_LINES
      .. " lines or "
      .. math.floor(truncate.MAX_BYTES / 1024)
      .. "KB (whichever is hit first). "
      .. "If truncated, full output is saved to a temp file. "
      .. "Optionally provide a timeout in seconds.",
    strict = true,
    input_schema = {
      type = "object",
      properties = {
        label = {
          type = "string",
          description = "A short human-readable label for this operation (e.g., 'running tests')",
        },
        command = {
          type = "string",
          description = "The bash command to execute",
        },
        timeout = {
          type = { "number", "null" },
          description = "Timeout in seconds (default: 30)",
        },
      },
      required = { "label", "command", "timeout" },
      additionalProperties = false,
    },
    async = true,
    execute = function(input, callback, ctx)
      local cmd = input.command
      if not cmd or cmd == "" then
        callback({ success = false, error = "No command provided" })
        return nil
      end

      local state = require("flemma.state")
      local config = state.get_config()
      local default_timeout = (config.tools and config.tools.default_timeout) or 30
      local timeout = input.timeout or default_timeout

      local output_lines = {}
      local partial_line = "" -- buffer for incomplete line across chunks
      local job_exited = false
      local finished = false
      local timer = nil

      local function close_timer()
        if timer and not timer:is_closing() then
          timer:close()
        end
      end

      local job_opts = {
        on_stdout = function(_, data)
          if data then
            -- Per :h channel-callback, the last element is a partial line
            -- that must be joined with the first element of the next chunk
            data[1] = partial_line .. data[1]
            partial_line = table.remove(data)
            vim.list_extend(output_lines, data)
          end
        end,
        on_exit = function(_, code)
          if finished then
            close_timer()
            return
          end
          finished = true
          job_exited = true
          close_timer()
          vim.schedule(function()
            -- Flush remaining partial line
            if partial_line ~= "" then
              table.insert(output_lines, partial_line)
            end

            local full_output = table.concat(output_lines, "\n"):gsub("%s+$", "")

            -- Apply tail truncation
            local result = truncate.truncate_tail(full_output)
            local output_text = result.content ~= "" and result.content or "(no output)"

            if result.truncated then
              -- Save full output to temp file
              local temp_path = vim.fn.tempname()
              local f = io.open(temp_path, "w")
              if f then
                f:write(full_output)
                f:close()
              end

              -- Build actionable notice
              local start_line = result.total_lines - result.output_lines + 1
              local end_line = result.total_lines

              if result.last_line_partial then
                local last_line_size = truncate.format_size(#output_lines[#output_lines])
                output_text = output_text
                  .. string.format(
                    "\n\n[Showing last %s of line %d (line is %s). Full output: %s]",
                    truncate.format_size(result.output_bytes),
                    end_line,
                    last_line_size,
                    temp_path
                  )
              elseif result.truncated_by == "lines" then
                output_text = output_text
                  .. string.format(
                    "\n\n[Showing lines %d-%d of %d. Full output: %s]",
                    start_line,
                    end_line,
                    result.total_lines,
                    temp_path
                  )
              else
                output_text = output_text
                  .. string.format(
                    "\n\n[Showing lines %d-%d of %d (%s limit). Full output: %s]",
                    start_line,
                    end_line,
                    result.total_lines,
                    truncate.format_size(truncate.MAX_BYTES),
                    temp_path
                  )
              end
            end

            if code ~= 0 then
              output_text = output_text .. string.format("\n\nCommand exited with code %d", code)
              callback({
                success = false,
                error = output_text,
              })
            else
              callback({
                success = true,
                output = output_text,
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
      -- Wrap in group command so stderr redirect covers all pipeline stages
      local inner_cmd = { shell, "-c", "{ " .. cmd .. "; } 2>&1" }

      -- Sandbox wrapping (if enabled)
      local sandbox = require("flemma.sandbox")
      local sandbox_bufnr = ctx and ctx.bufnr or vim.api.nvim_get_current_buf()
      local sandbox_opts = ctx and ctx.opts or nil
      local wrapped_cmd, sandbox_err = sandbox.wrap_command(inner_cmd, sandbox_bufnr, sandbox_opts)
      if not wrapped_cmd then
        callback({ success = false, error = "Sandbox error: " .. sandbox_err })
        return nil
      end

      local job_id = vim.fn.jobstart(wrapped_cmd, job_opts)

      if job_id <= 0 then
        callback({ success = false, error = "Failed to start job" })
        return nil
      end

      -- Setup timeout
      timer = vim.uv.new_timer()
      if not timer then
        callback({ success = false, error = "Failed to create timer" })
        return nil
      end
      timer:start(
        timeout * 1000,
        0,
        vim.schedule_wrap(function()
          if finished then
            close_timer()
            return
          end
          finished = true
          if not job_exited then
            vim.fn.jobstop(job_id)

            -- Include any partial output collected before the timeout
            if partial_line ~= "" then
              table.insert(output_lines, partial_line)
            end
            local partial = table.concat(output_lines, "\n"):gsub("%s+$", "")
            local error_msg = string.format("Command timed out after %d seconds.", timeout)
            if partial ~= "" then
              error_msg = partial .. "\n\n" .. error_msg
            end

            callback({
              success = false,
              error = error_msg,
            })
          end
          close_timer()
        end)
      )

      -- Return cancel function
      return function()
        finished = true
        close_timer()
        if not job_exited then
          pcall(vim.fn.jobstop, job_id)
        end
      end
    end,
  },
}

return M
