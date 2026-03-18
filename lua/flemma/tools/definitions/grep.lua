--- Grep tool definition
--- Search file contents using ripgrep or grep with structured output
---@class flemma.tools.definitions.Grep
---@field definitions flemma.tools.ToolDefinition[]
---@field _reset_backend_cache fun() Reset cached backend for testing
---@field _translate_ere_pattern fun(pattern: string): string Translate shorthand character classes for ERE (exposed for testing)
---@field _build_command fun(backend: "rg"|"grep-p"|"grep-e", pattern: string, search_path: string|nil, glob_filter: string|nil, exclude_patterns: string[]): string[] Build command array (exposed for testing)
local M = {}

local json = require("flemma.utilities.json")
local truncate = require("flemma.utilities.truncate")
local sink_module = require("flemma.sink")

---Default maximum number of matches before stopping
local DEFAULT_LIMIT = 100

---@type ("rg"|"grep-p"|"grep-e"|false)|nil
local cached_backend = nil

---Detect the best available grep backend.
---Returns "rg" if ripgrep is installed, "grep-p" if GNU grep with PCRE is
---available, "grep-e" for POSIX ERE fallback, or false if no backend exists.
---@return "rg"|"grep-p"|"grep-e"|false
local function detect_backend()
  if cached_backend ~= nil then
    return cached_backend
  end
  if vim.fn.executable("rg") == 1 then
    cached_backend = "rg"
  elseif vim.fn.executable("grep") == 1 then
    vim.fn.system("grep -P '' /dev/null 2>/dev/null")
    local exit_code = vim.v.shell_error
    cached_backend = (exit_code == 0 or exit_code == 1) and "grep-p" or "grep-e"
  else
    cached_backend = false
  end
  return cached_backend
end

---Reset the backend cache (for testing).
function M._reset_backend_cache()
  cached_backend = nil
end

---Translate Perl-style shorthand character classes to POSIX ERE equivalents.
---Only needed for the grep -E backend which does not support \d, \w, \s.
---@param pattern string
---@return string
local function translate_ere_pattern(pattern)
  return (pattern:gsub("\\d", "[0-9]"):gsub("\\w", "[a-zA-Z0-9_]"):gsub("\\s", "[[:space:]]"))
end

M._translate_ere_pattern = translate_ere_pattern

---Determine whether an exclude pattern refers to a directory or a file.
---Patterns containing a dot are treated as file globs; others as directories.
---@param exclude string The exclude pattern
---@return boolean is_directory
local function is_directory_exclude(exclude)
  return not exclude:find("%.")
end

---Build the command array for the given backend.
---@param backend "rg"|"grep-p"|"grep-e" The detected backend
---@param pattern string The search pattern
---@param search_path string|nil Directory to search (defaults to ".")
---@param glob_filter string|nil File glob filter (e.g., "*.lua")
---@param exclude_patterns string[] Patterns to exclude
---@return string[] command The command array suitable for jobstart
function M._build_command(backend, pattern, search_path, glob_filter, exclude_patterns)
  if backend == "rg" then
    local cmd = { "rg", "--json", "--no-messages", pattern }
    if glob_filter then
      table.insert(cmd, "--glob")
      table.insert(cmd, glob_filter)
    end
    for _, exclude in ipairs(exclude_patterns) do
      table.insert(cmd, "--glob")
      table.insert(cmd, "!" .. exclude)
    end
    table.insert(cmd, search_path or ".")
    return cmd
  end

  -- grep-p or grep-e
  local effective_pattern = pattern
  local flag = "-P"
  if backend == "grep-e" then
    effective_pattern = translate_ere_pattern(pattern)
    flag = "-E"
  end

  local cmd = { "grep", "-rn", "--binary-files=without-match", flag, effective_pattern }
  if glob_filter then
    table.insert(cmd, "--include=" .. glob_filter)
  end
  for _, exclude in ipairs(exclude_patterns) do
    if is_directory_exclude(exclude) then
      table.insert(cmd, "--exclude-dir=" .. exclude)
    else
      table.insert(cmd, "--exclude=" .. exclude)
    end
  end
  table.insert(cmd, search_path or ".")
  return cmd
end

M.definitions = {
  {
    name = "grep",
    enabled = function(config)
      return config and config.experimental and config.experimental.tools or false
    end,
    capabilities = { "can_auto_approve_if_sandboxed" },
    description = "Search file contents using ripgrep (rg) or grep. "
      .. "Returns matching lines with file paths and line numbers. "
      .. "Output is limited to "
      .. DEFAULT_LIMIT
      .. " matches by default. "
      .. "Supports regex patterns. "
      .. "When using grep -E fallback, \\d, \\w, \\s are automatically translated to POSIX equivalents.",
    strict = true,
    input_schema = {
      type = "object",
      properties = {
        label = {
          type = "string",
          description = "A short human-readable label for this operation (e.g., 'searching for TODO comments')",
        },
        pattern = {
          type = "string",
          description = "Regular expression pattern to search for",
        },
        path = {
          type = { "string", "null" },
          description = "Directory to search in (default: working directory)",
        },
        glob = {
          type = { "string", "null" },
          description = "File glob filter (e.g., '*.lua', '*.{ts,tsx}')",
        },
        limit = {
          type = { "number", "null" },
          description = "Maximum number of matches (default: " .. DEFAULT_LIMIT .. ")",
        },
      },
      required = { "label", "pattern", "path", "glob", "limit" },
      additionalProperties = false,
    },
    personalities = {
      ["coding-assistant"] = {
        snippet = "Search file contents for patterns using ripgrep or grep",
        guidelines = {
          "Use grep to find specific patterns, symbols, or text across the codebase",
          "Prefer specific patterns over broad ones to reduce noise",
          "Use glob filter to narrow search to relevant file types",
        },
      },
    },
    async = true,
    ---@return flemma.tools.ToolPreview
    format_preview = function(input)
      local detail_parts = { "/" .. input.pattern .. "/" }
      if input.path then
        table.insert(detail_parts, input.path)
      end
      if input.glob then
        table.insert(detail_parts, input.glob)
      end
      return {
        label = input.label,
        detail = detail_parts,
      }
    end,
    ---@param input table<string, any>
    ---@param ctx flemma.tools.ExecutionContext
    ---@param callback fun(result: flemma.tools.ExecutionResult)
    ---@return fun()|nil cancel Cancel function
    execute = function(input, ctx, callback)
      ---@cast callback -nil
      local pattern = input.pattern
      if not pattern or pattern == "" then
        callback({ success = false, error = "No pattern provided" })
        return nil
      end

      local backend = detect_backend()
      if not backend then
        callback({ success = false, error = "No search backend available (install rg or grep)" })
        return nil
      end

      -- Normalize search path relative to cwd (job runs with cwd = ctx.cwd).
      -- If an absolute path matches cwd, replace with "." so output paths stay relative.
      local search_path = input.path
      if not search_path or search_path == "" then
        search_path = "."
      elseif vim.startswith(search_path, ctx.cwd .. "/") then
        search_path = "." .. search_path:sub(#ctx.cwd + 1)
      elseif search_path == ctx.cwd then
        search_path = "."
      end

      -- Gather exclude patterns from config
      local tool_config = ctx:get_config()
      local exclude_patterns = (tool_config and tool_config.exclude) or {}

      local limit = input.limit or DEFAULT_LIMIT
      local cmd = M._build_command(backend, pattern, search_path, input.glob, exclude_patterns)

      -- Track match count and collected output lines
      local match_count = 0
      ---@type string[]
      local output_lines = {}
      local limit_reached = false
      ---@type integer|nil
      local job_id = nil

      ---@type fun(line: string)
      local on_line_callback

      if backend == "rg" then
        -- rg --json mode: parse each JSON line and reconstruct grep-style output
        on_line_callback = function(line)
          if limit_reached then
            return
          end
          local ok, parsed = pcall(json.decode, line)
          if not ok or not parsed then
            return
          end
          if parsed.type == "match" then
            match_count = match_count + 1
            local file_path = parsed.data and parsed.data.path and parsed.data.path.text or "?"
            local line_number = parsed.data and parsed.data.line_number or 0
            local line_text = parsed.data and parsed.data.lines and parsed.data.lines.text or ""
            -- rg includes trailing newline in lines.text; strip it
            line_text = line_text:gsub("\n$", "")
            local truncated_line = truncate.truncate_line(line_text)
            table.insert(output_lines, file_path .. ":" .. line_number .. ":" .. truncated_line.text)
            if match_count >= limit then
              limit_reached = true
              if job_id then
                pcall(vim.fn.jobstop, job_id)
              end
            end
          end
        end
      else
        -- grep mode: collect raw lines, apply per-line truncation
        on_line_callback = function(line)
          if limit_reached then
            return
          end
          match_count = match_count + 1
          local truncated_line = truncate.truncate_line(line)
          table.insert(output_lines, truncated_line.text)
          if match_count >= limit then
            limit_reached = true
            if job_id then
              pcall(vim.fn.jobstop, job_id)
            end
          end
        end
      end

      local output_sink = sink_module.create({
        name = "grep/" .. (input.label or "search"):gsub("[^%w/%-]", "-"),
        on_line = on_line_callback,
      })

      local finished = false
      local job_exited = false
      local timer = nil

      local function close_timer()
        if timer and not timer:is_closing() then
          timer:close()
        end
      end

      local job_opts = {
        cwd = ctx.cwd,
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
            output_sink:destroy()

            -- Exit code handling:
            -- rg/grep exit 0: matches found
            -- rg/grep exit 1: no matches (not an error)
            -- rg/grep exit >= 2: actual error
            -- Signal-killed (from jobstop on limit): treat as success
            local is_error = code >= 2 and not limit_reached

            if is_error then
              callback({
                success = false,
                error = "Search failed with exit code " .. code,
              })
              return
            end

            if match_count == 0 then
              callback({
                success = true,
                output = "No matches found.",
              })
              return
            end

            -- Build result from collected output lines
            local content = table.concat(output_lines, "\n")

            -- Apply head truncation for overall size limits
            local result = ctx.truncate.truncate_head(content)
            local output_text = result.content

            -- Add summary footer
            local footer
            if limit_reached then
              footer = string.format("[%d matches, limit reached]", match_count)
            else
              footer = string.format("[%d matches]", match_count)
            end

            if result.truncated then
              output_text = output_text .. "\n\n" .. footer
            else
              output_text = content .. "\n\n" .. footer
            end

            callback({
              success = true,
              output = output_text,
            })
          end)
        end,
      }

      -- Sandbox wrapping
      local wrapped_cmd, sandbox_err = ctx.sandbox.wrap_command(cmd)
      if not wrapped_cmd then
        output_sink:destroy()
        callback({ success = false, error = "Sandbox error: " .. sandbox_err })
        return nil
      end

      job_id = vim.fn.jobstart(wrapped_cmd, job_opts)

      if job_id <= 0 then
        output_sink:destroy()
        callback({ success = false, error = "Failed to start search process" })
        return nil
      end

      -- Setup timeout
      local timeout = ctx.timeout
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

            local partial_output = output_sink:read():gsub("%s+$", "")
            output_sink:destroy()
            local error_msg = string.format("Search timed out after %d seconds.", timeout)
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
