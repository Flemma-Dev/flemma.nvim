--- Bash tool definition
--- Execute bash commands and return stdout/stderr
--- Truncation logic ported from pi by Mario Zechner (https://github.com/badlogic/pi-mono)
--- Original: MIT License, Copyright (c) 2025 Mario Zechner
---@class flemma.tools.definitions.Bash
---@field definitions flemma.tools.ToolDefinition[]
local M = {}

-- Module-level require for description constants only (evaluated at load time).
-- Runtime code inside execute() must use ctx.truncate instead.
local truncate = require("flemma.tools.truncate")

M.definitions = {
  {
    name = "bash",
    capabilities = { "can_auto_approve_if_sandboxed" },
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
    format_preview = function(input)
      local parts = { "$ " .. input.command }
      if input.label then
        table.insert(parts, "# " .. input.label)
      end
      return table.concat(parts, "  ")
    end,
    execute = function(input, ctx, callback)
      ---@cast callback -nil
      local cmd = input.command
      if not cmd or cmd == "" then
        callback({ success = false, error = "No command provided" })
        return nil
      end

      local timeout = input.timeout or ctx.timeout

      local sink_module = require("flemma.sink")
      local output_sink = sink_module.create({
        name = "bash/" .. (input.label or "cmd"):gsub("[^%w/%-]", "-"),
      })
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
            output_sink:write(table.concat(data, "\n"))
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
            local all_lines = output_sink:read_lines()
            local full_output = table.concat(all_lines, "\n"):gsub("%s+$", "")
            output_sink:destroy()

            -- Apply tail truncation
            local result = ctx.truncate.truncate_tail(full_output)
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
                local last_line_size = ctx.truncate.format_size(#all_lines[#all_lines])
                output_text = output_text
                  .. string.format(
                    "\n\n[Showing last %s of line %d (line is %s). Full output: %s]",
                    ctx.truncate.format_size(result.output_bytes),
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
                    ctx.truncate.format_size(ctx.truncate.MAX_BYTES),
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
      -- cwd is already resolved by executor (config > $FLEMMA_BUFFER_PATH > Neovim cwd)
      job_opts.cwd = ctx.cwd
      local tool_config = ctx:get_config()
      if tool_config and tool_config.env then
        job_opts.env = tool_config.env
      end

      local shell = (tool_config and tool_config.shell) or "bash"
      -- Redirect stderr to stdout for the entire shell so output is interleaved
      local inner_cmd = { shell, "-c", "exec 2>&1\n" .. cmd }

      -- Sandbox wrapping (if enabled)
      local wrapped_cmd, sandbox_err = ctx.sandbox.wrap_command(inner_cmd)
      if not wrapped_cmd then
        output_sink:destroy()
        callback({ success = false, error = "Sandbox error: " .. sandbox_err })
        return nil
      end

      local job_id = vim.fn.jobstart(wrapped_cmd, job_opts)

      if job_id <= 0 then
        output_sink:destroy()
        callback({ success = false, error = "Failed to start job" })
        return nil
      end

      -- Setup timeout
      timer = vim.uv.new_timer()
      if not timer then
        output_sink:destroy()
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
            local partial_output = output_sink:read():gsub("%s+$", "")
            output_sink:destroy()
            local error_msg = string.format("Command timed out after %d seconds.", timeout)
            if partial_output ~= "" then
              error_msg = partial_output .. "\n\n" .. error_msg
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
        output_sink:destroy()
      end
    end,
  },
}

return M
