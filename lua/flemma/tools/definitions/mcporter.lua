--- MCPorter tool integration — discovers MCP servers via the mcporter CLI
--- and registers each tool as a Flemma tool definition.
---
--- Exports `{ resolve, timeout }` for the async source pattern consumed by
--- `tools.init.register_async()`. Discovery is gated behind
--- `tools.mcporter.enabled` (default false).
---@class flemma.tools.definitions.MCPorter
local M = {}

local config_facade = require("flemma.config")
local json = require("flemma.utilities.json")
local log = require("flemma.logging")
local sink_module = require("flemma.sink")

local SEPARATOR = "__"

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

---Replace dots with hyphens in server names (dots are not allowed in tool names).
---@param name string
---@return string
local function sanitize_server_name(name)
  local sanitized = name:gsub("%.", "-")
  return sanitized
end

---Convert a glob pattern (with `*` wildcards) to a Lua pattern.
---@param glob string
---@return string
local function glob_to_pattern(glob)
  local escaped = glob:gsub("([%.%+%-%^%$%(%)%%'%[%]])", "%%%1")
  return "^" .. escaped:gsub("%*", ".*") .. "$"
end

---Test whether a name matches any pattern in a list.
---@param name string
---@param patterns string[]
---@return boolean
local function matches_any(name, patterns)
  for _, pattern in ipairs(patterns) do
    if M._glob_match(name, pattern) then
      return true
    end
  end
  return false
end

---Check whether all possible tools from a server would be excluded.
---Used to skip the schema fetch entirely for fully-excluded servers.
---@param server_name string
---@param exclude string[]
---@return boolean
local function server_fully_excluded(server_name, exclude)
  local prefix = sanitize_server_name(server_name) .. SEPARATOR
  for _, pattern in ipairs(exclude) do
    local lua_pat = glob_to_pattern(pattern)
    -- If the exclude pattern matches `server__*`, all tools from this server
    -- would be excluded. We test by checking if the prefix + wildcard matches.
    if (prefix .. "anything"):find(lua_pat) then
      return true
    end
  end
  return false
end

--------------------------------------------------------------------------------
-- Exported test helpers (prefixed with _ for test access)
--------------------------------------------------------------------------------

---Test whether a name matches a single glob pattern.
---@param name string
---@param glob string
---@return boolean
function M._glob_match(name, glob)
  local pattern = glob_to_pattern(glob)
  return name:find(pattern) ~= nil
end

---Apply include/exclude filtering to a list of tool stubs.
---
---Semantics:
---1. Exclude pass: tools matching any exclude pattern are removed entirely.
---2. Include pass: remaining tools matching any include pattern get `enabled = true`.
---3. Remainder: tools not matching include get `enabled = false`.
---@param tools { name: string }[]
---@param include string[]
---@param exclude string[]
---@return { name: string, enabled: boolean }[]
function M._filter_tools(tools, include, exclude)
  local result = {}
  for _, tool in ipairs(tools) do
    if not matches_any(tool.name, exclude) then
      local enabled = matches_any(tool.name, include)
      table.insert(result, { name = tool.name, enabled = enabled })
    end
  end
  return result
end

---Parse the JSON output of `mcporter list --json`.
---@param raw string
---@return { name: string, status: string, tools: table[] }[]|nil servers Healthy servers, or nil on parse error
function M._parse_server_list(raw)
  local ok, data = pcall(json.decode, raw)
  if not ok or type(data) ~= "table" then
    return nil
  end
  if type(data.servers) ~= "table" then
    return nil
  end
  local healthy = {}
  for _, server in ipairs(data.servers) do
    if server.status == "ok" then
      table.insert(healthy, server)
    end
  end
  return healthy
end

---Parse an MCP call response, extracting text content.
---
---Tries two formats in order:
---1. MCP content wrapper: `{ content: [{ type: "text", text: "..." }] }`
---2. Raw text passthrough: any non-empty string returned as-is.
---@param raw string
---@return string|nil text Extracted text, or nil on error
---@return string|nil error Error message if parsing failed
function M._parse_call_response(raw)
  if raw == "" then
    return nil, "mcporter returned empty output"
  end

  -- Try MCP content wrapper first
  local ok, data = pcall(json.decode, raw)
  if ok and type(data) == "table" and type(data.content) == "table" then
    local texts = {}
    for _, block in ipairs(data.content) do
      if block.type == "text" and type(block.text) == "string" then
        table.insert(texts, block.text)
      end
    end
    if #texts > 0 then
      return table.concat(texts, "\n\n"), nil
    end
  end

  -- Fall back to raw text passthrough (--output raw returns content directly)
  return raw, nil
end

---Build a `flemma.tools.ToolDefinition` from a single mcporter tool schema entry.
---@param server_name string Original server name (may contain dots)
---@param tool_data { name: string, description: string, inputSchema: table }
---@param exec_opts { path: string, timeout: integer }
---@return flemma.tools.ToolDefinition
function M._build_tool_definition(server_name, tool_data, exec_opts)
  local safe_server = sanitize_server_name(server_name)
  local tool_name = safe_server .. SEPARATOR .. tool_data.name
  local selector = server_name .. "." .. tool_data.name
  local mcporter_path = exec_opts.path
  local call_timeout = exec_opts.timeout

  ---@type flemma.tools.ToolDefinition
  local definition = {
    name = tool_name,
    description = tool_data.description or "",
    input_schema = tool_data.inputSchema or { type = "object", properties = {} },
    async = true,
    execute = function(input, ctx, callback)
      ---@cast callback -nil
      local args_json = json.encode(input)
      local cmd = { mcporter_path, "call", selector, "--args", args_json, "--output", "raw" }

      local output_sink = sink_module.create({
        name = "mcporter/" .. tool_name,
      })
      local stderr_lines = {}
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
            local raw_output = output_sink:read()
            output_sink:destroy()

            local stderr_text = #stderr_lines > 0 and table.concat(stderr_lines, "\n") or nil

            if code ~= 0 then
              local err_msg = stderr_text or ("mcporter call failed with exit code " .. code)
              callback({ success = false, error = err_msg })
              return
            end

            local text, parse_err = M._parse_call_response(raw_output)
            if not text then
              local diagnostic = parse_err or "Failed to parse response"
              if stderr_text then
                diagnostic = diagnostic .. "\nstderr: " .. stderr_text
              end
              callback({ success = false, error = diagnostic })
              return
            end

            callback({ success = true, output = text })
          end)
        end,
      }

      local job_id = vim.fn.jobstart(cmd, job_opts)
      if job_id <= 0 then
        output_sink:destroy()
        callback({ success = false, error = "Failed to start mcporter call" })
        return nil
      end

      -- Setup timeout
      timer = vim.uv.new_timer()
      if not timer then
        finished = true
        pcall(vim.fn.jobstop, job_id)
        output_sink:destroy()
        callback({ success = false, error = "Failed to create timer" })
        return nil
      end

      timer:start(
        call_timeout * 1000,
        0,
        vim.schedule_wrap(function()
          if finished then
            close_timer()
            return
          end
          finished = true
          if not job_exited then
            vim.fn.jobstop(job_id)
            output_sink:destroy()
            callback({
              success = false,
              error = string.format("mcporter call timed out after %d seconds", call_timeout),
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
  }

  return definition
end

---Concurrency-controlled schema fanout: fetch detailed tool schemas for each server.
---@param servers { name: string }[]
---@param opts { path: string, timeout: integer, concurrency: integer }
---@param on_server fun(server_name: string, tool_defs: table[]) Called per completed server
---@param on_done fun() Called when all servers complete
function M._fanout_schema_fetches(servers, opts, on_server, on_done)
  if #servers == 0 then
    vim.schedule(on_done)
    return
  end

  local remaining = #servers
  local queue_index = 0
  local active = 0

  local function launch_next()
    while active < opts.concurrency and queue_index < #servers do
      queue_index = queue_index + 1
      active = active + 1
      local server = servers[queue_index]

      local cmd = { opts.path, "list", server.name, "--json", "--schema" }
      local output_sink = sink_module.create({
        name = "mcporter/schema/" .. server.name,
      })
      local server_finished = false
      local server_job_exited = false
      local server_timer = nil

      local function close_server_timer()
        if server_timer and not server_timer:is_closing() then
          server_timer:close()
        end
      end

      local function complete_server(server_name, tool_defs)
        if tool_defs then
          on_server(server_name, tool_defs)
        end
        active = active - 1
        remaining = remaining - 1
        if remaining == 0 then
          on_done()
        else
          launch_next()
        end
      end

      local job_opts = {
        on_stdout = function(_, data)
          if data then
            output_sink:write(table.concat(data, "\n"))
          end
        end,
        on_exit = function(_, code)
          if server_finished then
            close_server_timer()
            return
          end
          server_finished = true
          server_job_exited = true
          close_server_timer()
          vim.schedule(function()
            local raw_output = output_sink:read()
            output_sink:destroy()

            if code ~= 0 then
              log.warn("mcporter: schema fetch failed for server '" .. server.name .. "'")
              complete_server(server.name, nil)
              return
            end

            local parse_ok, data = pcall(json.decode, raw_output)
            if not parse_ok or type(data) ~= "table" or type(data.tools) ~= "table" then
              log.warn("mcporter: malformed schema response for server '" .. server.name .. "'")
              complete_server(server.name, nil)
              return
            end

            complete_server(server.name, data.tools)
          end)
        end,
      }

      local job_id = vim.fn.jobstart(cmd, job_opts)
      if job_id <= 0 then
        output_sink:destroy()
        log.warn("mcporter: failed to start schema fetch for server '" .. server.name .. "'")
        server_finished = true
        complete_server(server.name, nil)
      else
        -- Per-process timeout
        server_timer = vim.uv.new_timer()
        if server_timer then
          server_timer:start(
            opts.timeout * 1000,
            0,
            vim.schedule_wrap(function()
              if server_finished then
                close_server_timer()
                return
              end
              server_finished = true
              if not server_job_exited then
                vim.fn.jobstop(job_id)
                output_sink:destroy()
                log.warn("mcporter: schema fetch timed out for server '" .. server.name .. "'")
              end
              close_server_timer()
              complete_server(server.name, nil)
            end)
          )
        end
      end
    end
  end

  launch_next()
end

---Full discovery flow with explicit config, register callback, and done callback.
---@param cfg { enabled: boolean, path?: string, timeout?: integer, startup?: { concurrency?: integer }, include?: string[], exclude?: string[] }
---@param register fun(name: string, def: flemma.tools.ToolDefinition)
---@param done fun()
function M._resolve_with_config(cfg, register, done)
  -- Phase 1: Gate checks
  if not cfg.enabled then
    done()
    return
  end

  local mcporter_path = cfg.path or "mcporter"
  if vim.fn.executable(mcporter_path) ~= 1 then
    log.debug("mcporter: binary not found at '" .. mcporter_path .. "'")
    done()
    return
  end

  local call_timeout = cfg.timeout or 60
  local concurrency = (cfg.startup and cfg.startup.concurrency) or 4
  local include = cfg.include or {}
  local exclude = cfg.exclude or {}

  -- Phase 2: Server manifest
  local cmd = { mcporter_path, "list", "--json" }
  local list_sink = sink_module.create({ name = "mcporter/list" })
  local list_finished = false
  local list_job_exited = false
  local list_timer = nil

  local function close_list_timer()
    if list_timer and not list_timer:is_closing() then
      list_timer:close()
    end
  end

  local list_opts = {
    on_stdout = function(_, data)
      if data then
        list_sink:write(table.concat(data, "\n"))
      end
    end,
    on_exit = function(_, code)
      if list_finished then
        close_list_timer()
        return
      end
      list_finished = true
      list_job_exited = true
      close_list_timer()
      vim.schedule(function()
        local raw = list_sink:read()
        list_sink:destroy()

        if code ~= 0 then
          log.warn("mcporter: list command failed with exit code " .. code)
          done()
          return
        end

        local servers = M._parse_server_list(raw)
        if not servers then
          log.warn("mcporter: failed to parse server list")
          done()
          return
        end

        if #servers == 0 then
          log.debug("mcporter: no healthy servers found")
          done()
          return
        end

        -- Filter out fully-excluded servers before schema fanout
        local servers_to_fetch = {}
        for _, server in ipairs(servers) do
          if not server_fully_excluded(server.name, exclude) then
            table.insert(servers_to_fetch, server)
          end
        end

        if #servers_to_fetch == 0 then
          log.debug("mcporter: all servers excluded")
          done()
          return
        end

        -- Phase 3: Schema fanout
        M._fanout_schema_fetches(servers_to_fetch, {
          path = mcporter_path,
          timeout = call_timeout,
          concurrency = concurrency,
        }, function(server_name, tool_defs)
          -- Build and register tools for this server
          local tool_stubs = {}
          for _, tool_data in ipairs(tool_defs) do
            local safe_server = sanitize_server_name(server_name)
            local tool_name = safe_server .. SEPARATOR .. tool_data.name
            table.insert(tool_stubs, { name = tool_name })
          end

          -- Apply include/exclude filtering
          local filtered = M._filter_tools(tool_stubs, include, exclude)
          local enabled_map = {}
          for _, entry in ipairs(filtered) do
            enabled_map[entry.name] = entry.enabled
          end

          -- Register each tool that survived filtering
          for _, tool_data in ipairs(tool_defs) do
            local def = M._build_tool_definition(server_name, tool_data, {
              path = mcporter_path,
              timeout = call_timeout,
            })
            local is_enabled = enabled_map[def.name]
            if is_enabled ~= nil then
              def.enabled = is_enabled
              register(def.name, def)
            end
            -- If name not in enabled_map, it was excluded — skip registration
          end
        end, done)
      end)
    end,
  }

  local list_job_id = vim.fn.jobstart(cmd, list_opts)
  if list_job_id <= 0 then
    list_sink:destroy()
    log.warn("mcporter: failed to start list command")
    done()
    return
  end

  -- Timeout for the list command
  list_timer = vim.uv.new_timer()
  if list_timer then
    list_timer:start(
      call_timeout * 1000,
      0,
      vim.schedule_wrap(function()
        if list_finished then
          close_list_timer()
          return
        end
        list_finished = true
        if not list_job_exited then
          vim.fn.jobstop(list_job_id)
          list_sink:destroy()
          log.warn("mcporter: list command timed out")
        end
        close_list_timer()
        done()
      end)
    )
  end
end

---Async source resolver — reads config and delegates to `_resolve_with_config`.
---@param register fun(name: string, def: flemma.tools.ToolDefinition)
---@param done fun()
function M.resolve(register, done)
  local resolved_config = config_facade.get()
  local cfg = (resolved_config and resolved_config.tools and resolved_config.tools.mcporter) or {}

  M._resolve_with_config(cfg, register, done)
end

---Global timeout in seconds for the async source registration.
---@type integer
M.timeout = 120

return M
