--- Find file tool definition
--- Locate files by glob pattern using fd, git ls-files, or GNU find
---@class flemma.tools.definitions.Find
---@field definitions flemma.tools.ToolDefinition[]
---@field _reset_backend_cache fun() Reset cached backend detection (for testing)
---@field _build_command fun(backend: "fd"|"git"|"find", pattern: string, search_path: string, exclude: string[]): string[] Build command array for the given backend (exposed for testing)
local M = {}

local truncate = require("flemma.utilities.truncate")
local sink_module = require("flemma.sink")

local DEFAULT_RESULT_LIMIT = 500

---@type ("fd"|"git"|"find"|false)|nil
local cached_backend = nil

---Detect available file-finding backend.
---Result is cached after first call for performance.
---@return "fd"|"git"|"find"|false backend The detected backend, or false if none available
local function detect_backend()
  if cached_backend ~= nil then
    return cached_backend
  end
  if vim.fn.executable("fd") == 1 or vim.fn.executable("fdfind") == 1 then
    cached_backend = "fd"
  elseif vim.fn.system("git rev-parse --is-inside-work-tree 2>/dev/null"):match("true") then
    cached_backend = "git"
  elseif vim.fn.executable("find") == 1 then
    cached_backend = "find"
  else
    cached_backend = false
  end
  return cached_backend
end

---Reset cached backend detection (for testing).
function M._reset_backend_cache()
  cached_backend = nil
end

---Determine whether a glob pattern contains a directory component.
---Patterns with "/" are path-level; patterns without are filename-level.
---@param pattern string The glob pattern to inspect
---@return boolean has_directory True if the pattern contains a path separator
local function pattern_has_directory(pattern)
  return pattern:find("/") ~= nil
end

---Split a path-level glob into its directory prefix and filename portion.
---For example, "src/**/*.tsx" splits into ("src/**/", "*.tsx").
---@param pattern string The glob pattern with directory components
---@return string directory_prefix The directory prefix portion
---@return string filename_part The filename portion
local function split_pattern(pattern)
  local last_slash = pattern:match(".*()/")
  if last_slash then
    return pattern:sub(1, last_slash), pattern:sub(last_slash + 1)
  end
  return "", pattern
end

---Build command array for the given backend and parameters.
---@param backend "fd"|"git"|"find" The file-finding backend
---@param pattern string The glob pattern
---@param search_path string The directory to search in
---@param exclude string[] Patterns to exclude
---@return string[] command The command array for jobstart
function M._build_command(backend, pattern, search_path, exclude)
  if backend == "fd" then
    local fd_binary = vim.fn.executable("fdfind") == 1 and "fdfind" or "fd"
    local cmd = { fd_binary, "--type", "f", "--color", "never" }
    for _, exclusion in ipairs(exclude) do
      table.insert(cmd, "--exclude")
      table.insert(cmd, exclusion)
    end
    if pattern_has_directory(pattern) then
      local directory_prefix, filename_part = split_pattern(pattern)
      table.insert(cmd, "--glob")
      table.insert(cmd, filename_part)
      table.insert(cmd, search_path .. "/" .. directory_prefix)
    else
      table.insert(cmd, "--glob")
      table.insert(cmd, pattern)
      table.insert(cmd, search_path)
    end
    return cmd
  elseif backend == "git" then
    local cmd = { "git", "ls-files", "--cached", "--others", "--exclude-standard" }
    for _, exclusion in ipairs(exclude) do
      table.insert(cmd, "--exclude")
      table.insert(cmd, exclusion)
    end
    table.insert(cmd, "--")
    if pattern_has_directory(pattern) then
      table.insert(cmd, pattern)
    else
      -- git ls-files pathspec "**/*.ext" only matches in subdirectories,
      -- not at the root level. Include both the root-level and recursive
      -- patterns to match files at any depth.
      table.insert(cmd, pattern)
      table.insert(cmd, "**/" .. pattern)
    end
    return cmd
  else
    -- GNU find
    local cmd = { "find" }
    if pattern_has_directory(pattern) then
      local directory_prefix, filename_part = split_pattern(pattern)
      table.insert(cmd, search_path .. "/" .. directory_prefix)
      table.insert(cmd, "-type")
      table.insert(cmd, "f")
      table.insert(cmd, "-name")
      table.insert(cmd, filename_part)
    else
      table.insert(cmd, search_path)
      table.insert(cmd, "-type")
      table.insert(cmd, "f")
      table.insert(cmd, "-name")
      table.insert(cmd, pattern)
    end
    for _, exclusion in ipairs(exclude) do
      table.insert(cmd, "-not")
      table.insert(cmd, "-path")
      table.insert(cmd, "*/" .. exclusion .. "/*")
    end
    return cmd
  end
end

M.definitions = {
  {
    name = "find",
    enabled = function(config)
      return config and config.experimental and config.experimental.tools or false
    end,
    capabilities = { "can_auto_approve_if_sandboxed" },
    description = "Find files by glob pattern. "
      .. "Uses fd, git ls-files, or GNU find (whichever is available). "
      .. "Output is truncated to "
      .. truncate.MAX_LINES
      .. " lines or "
      .. math.floor(truncate.MAX_BYTES / 1024)
      .. "KB. "
      .. "Returns sorted relative paths, one per line.",
    strict = true,
    input_schema = {
      type = "object",
      properties = {
        label = {
          type = "string",
          description = "A short human-readable label for this operation (e.g., 'finding test files')",
        },
        pattern = {
          type = "string",
          description = "Glob pattern to search for (e.g., '*.lua', 'src/**/*.tsx')",
        },
        path = {
          type = { "string", "null" },
          description = "Directory to search in (default: working directory)",
        },
        limit = {
          type = { "number", "null" },
          description = "Maximum number of results (default: " .. DEFAULT_RESULT_LIMIT .. ")",
        },
      },
      required = { "label", "pattern", "path", "limit" },
      additionalProperties = false,
    },
    personalities = {
      ["coding-assistant"] = {
        snippet = "Find files matching a glob pattern in the project",
        guidelines = {
          "Use find to discover file locations before reading or editing",
          "Use specific patterns to narrow results (e.g., '*.test.lua' not '*')",
        },
      },
    },
    async = true,
    ---@return flemma.tools.ToolPreview
    format_preview = function(input)
      local detail_parts = { input.pattern }
      if input.path then
        table.insert(detail_parts, "in " .. input.path)
      end
      return {
        label = input.label,
        detail = detail_parts,
      }
    end,
    execute = function(input, ctx, callback)
      ---@cast callback -nil
      local pattern = input.pattern
      if not pattern or pattern == "" then
        callback({ success = false, error = "No pattern provided" })
        return nil
      end

      local backend = detect_backend()
      if not backend then
        callback({ success = false, error = "No file-finding tool available (install fd, git, or find)" })
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

      -- Get exclude patterns from config
      local tool_config = ctx:get_config()
      local exclude = (tool_config and tool_config.exclude) or {}

      local result_limit = input.limit or DEFAULT_RESULT_LIMIT
      result_limit = math.max(1, math.floor(result_limit))

      -- Build command
      local cmd = M._build_command(backend, pattern, search_path, exclude)

      -- Sandbox wrapping
      local wrapped_cmd, sandbox_err = ctx.sandbox.wrap_command(cmd)
      if not wrapped_cmd then
        callback({ success = false, error = "Sandbox error: " .. (sandbox_err or "unknown") })
        return nil
      end

      local result_count = 0
      local limit_reached = false
      local job_id_ref = { value = nil }

      local output_sink = sink_module.create({
        name = "find/" .. (input.label or "search"):gsub("[^%w/%-]", "-"),
        on_line = function(_)
          result_count = result_count + 1
          if result_count >= result_limit and job_id_ref.value then
            limit_reached = true
            pcall(vim.fn.jobstop, job_id_ref.value)
          end
        end,
      })

      local stderr_lines = {}
      local job_exited = false
      local finished = false
      local timer = nil
      local timeout = ctx.timeout

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
        on_stderr = function(_, data)
          if data then
            for _, line in ipairs(data) do
              if line ~= "" then
                table.insert(stderr_lines, line)
              end
            end
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
            output_sink:destroy()

            -- Filter empty lines
            local results = {}
            for _, line in ipairs(all_lines) do
              if line ~= "" then
                table.insert(results, line)
              end
            end

            -- fd exit code 1 means "no results" (not an error)
            local is_error = code ~= 0 and not (backend == "fd" and code == 1)

            -- Also treat limit_reached + SIGPIPE/SIGTERM exits as non-error
            if limit_reached and code ~= 0 then
              is_error = false
            end

            if is_error and #results == 0 then
              local error_text = #stderr_lines > 0 and table.concat(stderr_lines, "\n")
                or string.format("Command exited with code %d", code)
              callback({ success = false, error = error_text })
              return
            end

            if #results == 0 then
              callback({ success = true, output = "No files found matching pattern." })
              return
            end

            -- Strip cwd prefix to produce relative paths
            local cwd_prefix = ctx.cwd .. "/"
            for i, result_line in ipairs(results) do
              if vim.startswith(result_line, cwd_prefix) then
                results[i] = result_line:sub(#cwd_prefix + 1)
              elseif vim.startswith(result_line, "./") then
                results[i] = result_line:sub(3)
              end
            end

            -- Sort results
            table.sort(results)

            -- Apply result limit (in case on_line counting was approximate)
            local was_limited = #results > result_limit
            if was_limited then
              local trimmed = {}
              for i = 1, result_limit do
                trimmed[i] = results[i]
              end
              results = trimmed
            end

            local output_text = table.concat(results, "\n")

            -- Apply truncation
            local truncation_result = ctx.truncate.truncate_head(output_text)
            output_text = truncation_result.content

            -- Add summary
            if limit_reached or was_limited then
              output_text = output_text
                .. string.format(
                  "\n\n[Results limited to %d entries. Narrow your pattern for more specific results.]",
                  result_limit
                )
            elseif truncation_result.truncated then
              output_text = output_text
                .. string.format(
                  "\n\n[Showing %d of %d results (truncated). Narrow your pattern for more specific results.]",
                  truncation_result.output_lines,
                  truncation_result.total_lines
                )
            end

            callback({ success = true, output = output_text })
          end)
        end,
      }

      local job_id = vim.fn.jobstart(wrapped_cmd, job_opts)

      if job_id <= 0 then
        output_sink:destroy()
        callback({ success = false, error = "Failed to start job" })
        return nil
      end

      job_id_ref.value = job_id

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

            local partial_output = output_sink:read():gsub("%s+$", "")
            output_sink:destroy()
            local error_msg = string.format("Find timed out after %d seconds.", timeout)
            if partial_output ~= "" then
              error_msg = partial_output .. "\n\n" .. error_msg
            end

            callback({ success = false, error = error_msg })
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
