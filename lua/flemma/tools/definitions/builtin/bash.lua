--- Bash tool definition
--- Execute bash commands and return stdout/stderr
--- Truncation logic ported from pi by Mario Zechner (https://github.com/badlogic/pi-mono)
--- Original: MIT License, Copyright (c) 2025 Mario Zechner
---@class flemma.tools.definitions.builtin.Bash
---@field definitions flemma.tools.ToolDefinition[]
local M = {}

-- Module-level require for description constants only (evaluated at load time).
-- Runtime code inside execute() must use ctx.truncate instead.
local log = require("flemma.logging")
local messages = require("flemma.messages")
local s = require("flemma.schema")
local sink_module = require("flemma.sink")
local store = require("flemma.tools.store")
local truncate = require("flemma.tools.truncate")

--- Neovim 0.12+ fixes a libuv bug (libuv#4992) where PTY master data is lost
--- under load. The terminal backend is only safe on 0.12+.
local HAS_TERMINAL_PTY_FIX = vim.fn.has("nvim-0.12") == 1

-- Terminal backend helpers (0.12+ only) --

-- -1 on a terminal buffer = Neovim's compiled maximum (SB_MAX: 100K on 0.11, 1M on 0.12+).
local SCROLLBACK = -1
local next_terminal_id = 0

--- The terminal backend runs commands under a termopen PTY, so stdout is a tty
--- and git/less/man launch their interactive pager. The window-less terminal
--- buffer's PTY is only ~5 rows (Neovim's aucmd_win), so any multi-line output
--- (e.g. `git log`) pages and blocks forever — nothing can press a key. These
--- force non-interactive pagers, matching the jobstart backend (piped stdout
--- never triggers a pager). Merged over the inherited env, so they override an
--- existing PAGER / git core.pager.
---@type table<string, string>
local NON_INTERACTIVE_PAGER_ENV = { GIT_PAGER = "cat", PAGER = "cat" }

---Sanitize a string for use in buffer names: keep alphanumerics, dots, hyphens,
---underscores, colons; replace everything else with hyphens, collapse runs.
---@param label string
---@return string
local function sanitize_label(label)
  return (label:gsub("[^%w%.%-_:]", "-"):gsub("%-+", "-"):gsub("^%-", ""):gsub("%-$", ""))
end

---Delete a terminal buffer using the same visibility heuristic as Sink:destroy().
---If visible in a window, defers cleanup via bufhidden=wipe. Otherwise deletes immediately.
---Handles the E11 command-line window edge case.
---@param bufnr integer
---@param label string
local function destroy_terminal_buffer(bufnr, label)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if vim.fn.getcmdwintype() ~= "" then
    vim.api.nvim_create_autocmd("CmdwinLeave", {
      once = true,
      callback = function()
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(bufnr) then
            return
          end
          if #vim.fn.win_findbuf(bufnr) > 0 then
            vim.bo[bufnr].bufhidden = "wipe"
            log.debug("bash terminal '" .. label .. "': buffer visible, deferring wipe (post-cmdwin)")
          else
            vim.api.nvim_buf_delete(bufnr, { force = true })
            log.debug("bash terminal '" .. label .. "': buffer deleted (post-cmdwin)")
          end
        end)
      end,
    })
    return
  end

  if #vim.fn.win_findbuf(bufnr) > 0 then
    vim.bo[bufnr].bufhidden = "wipe"
    log.debug("bash terminal '" .. label .. "': buffer visible, deferring wipe")
  else
    vim.api.nvim_buf_delete(bufnr, { force = true })
    log.debug("bash terminal '" .. label .. "': buffer deleted")
  end
end

---Read all lines from a terminal buffer, joining into a single string.
---@param bufnr integer
---@return string
local function read_terminal_output(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return ""
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, "\n"):gsub("%s+$", "")
  return text
end

-- Execute backends --

---Execute a bash command using termopen (Neovim 0.12+ only).
---@param input table<string, any>
---@param ctx flemma.tools.ExecutionContext
---@param callback fun(result: flemma.tools.ExecutionResult)
---@return fun()|nil cancel
local function execute_terminal(input, ctx, callback)
  local cmd = input.command
  if not cmd or cmd == "" then
    callback({ success = false, error = messages["tool.bash.error.no_command"]{} })
    return nil
  end

  local timeout = input.timeout or ctx.timeout
  local label = input.label or "cmd"

  local job_exited = false
  local finished = false
  local timer = nil

  local function close_timer()
    if timer and not timer:is_closing() then
      timer:close()
    end
  end

  -- Create hidden buffer for terminal use (not scratch — termopen needs buftype="")
  local term_bufnr = vim.api.nvim_create_buf(false, false)
  vim.bo[term_bufnr].buflisted = false
  vim.bo[term_bufnr].swapfile = false

  -- Apply bash-specific config
  -- cwd is already resolved by executor (config > urn:flemma:buffer:path > Neovim cwd)
  local tool_config = ctx:get_config()

  local shell = (tool_config and tool_config.shell) or "bash"
  -- Redirect stdin from /dev/null so interactive programs see non-interactive
  -- input (isatty(0) = false) and don't block waiting for user input.
  local inner_cmd = { shell, "-c", "exec </dev/null\n" .. cmd }

  -- Create the store directory before sandbox wrapping: rw_paths resolve at
  -- wrap time, and a not-yet-created store directory drops out of the policy.
  if cmd:find("FLEMMA_TOOLS_STORE_PATH", 1, true) then
    local ensure_ok, ensure_err = pcall(store.ensure_buffer_store_path, ctx.bufnr)
    if not ensure_ok then
      log.warn("bash: could not create store directory: " .. tostring(ensure_err))
    end
  end

  -- Sandbox wrapping (if enabled)
  local wrapped_cmd, sandbox_err = ctx.sandbox.wrap_command(inner_cmd)
  if not wrapped_cmd then
    vim.api.nvim_buf_delete(term_bufnr, { force = true })
    callback({ success = false, error = messages["tool.error.sandbox"]{ detail = sandbox_err } })
    return nil
  end

  ---@param code integer
  local function handle_completion(code)
    if finished then
      return
    end
    finished = true
    job_exited = true
    close_timer()
    vim.schedule(function()
      local full_output = read_terminal_output(term_bufnr)
      destroy_terminal_buffer(term_bufnr, label)

      -- Apply tail truncation with overflow handling
      local result = ctx.truncate.truncate_with_overflow(full_output, {
        direction = "tail",
      })
      local output_text = result.content ~= "" and result.content or messages["tool.bash.no_output"]{}

      if code ~= 0 then
        output_text = output_text .. "\n\n" .. messages["tool.error.exit_code"]{ code = code }
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
  end

  -- TermClose fires after the terminal emulator has fully processed all
  -- PTY data, unlike on_exit which fires from the job layer and may race
  -- with terminal rendering on large outputs.
  vim.api.nvim_create_autocmd("TermClose", {
    buffer = term_bufnr,
    once = true,
    callback = function()
      handle_completion(vim.v.event.status --[[@as integer]])
    end,
  })

  local job_opts = {
    cwd = ctx.cwd,
  }

  -- Disable interactive pagers (see NON_INTERACTIVE_PAGER_ENV).
  job_opts.env = vim.tbl_extend("force", vim.fn.environ(), NON_INTERACTIVE_PAGER_ENV)
  if tool_config and tool_config.env then
    job_opts.env = vim.tbl_extend("force", job_opts.env, tool_config.env)
  end
  local store_ok, store_path = pcall(store.get_buffer_store_path, ctx.bufnr)
  if store_ok and store_path then
    job_opts.env = vim.tbl_extend("force", job_opts.env, {
      FLEMMA_TOOLS_STORE_PATH = store_path,
    })
  end

  -- Run the command inside the terminal buffer.
  -- termopen is deprecated in newer Neovim but jobstart({term=true}) is
  -- unavailable on 0.11.x; termopen is the only working API here.
  local job_id
  vim.api.nvim_buf_call(term_bufnr, function()
    ---@diagnostic disable-next-line: deprecated
    job_id = vim.fn.termopen(wrapped_cmd, job_opts)
  end)

  if not job_id or job_id <= 0 then
    vim.api.nvim_buf_delete(term_bufnr, { force = true })
    callback({ success = false, error = messages["tool.error.job_start"]{} })
    return nil
  end

  -- Configure terminal buffer options (scrollback is only valid after termopen).
  vim.bo[term_bufnr].scrollback = SCROLLBACK
  vim.bo[term_bufnr].bufhidden = "hide"

  -- Rename from the default term://{cwd}//{pid}:{cmd} to our scheme.
  --
  -- nvim_buf_set_name on a buffer with a non-empty name creates a "ghost"
  -- buffer for the old name — Neovim's rename_buffer() in ex_cmds.c calls
  -- buflist_new(old_name) to preserve it as the alternate file (Ctrl-^).
  -- There is no API flag to suppress this.
  --
  -- Cleanup: capture the old name before renaming, then find and delete
  -- the ghost buffer that holds it. The term:// format includes the
  -- process PID (term://{cwd}//{pid}:{cmd}), so the exact match is
  -- globally unique — it will only ever hit the one ghost.
  --
  -- See: https://github.com/neovim/neovim/blob/v0.11.7/src/nvim/ex_cmds.c#L1508
  local old_term_name = vim.api.nvim_buf_get_name(term_bufnr)
  next_terminal_id = next_terminal_id + 1
  vim.api.nvim_buf_set_name(term_bufnr, "flemma://terminal/bash/" .. sanitize_label(label) .. "#" .. next_terminal_id)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if b ~= term_bufnr and vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b) == old_term_name then
      vim.api.nvim_buf_delete(b, { force = true })
      break
    end
  end

  -- Setup timeout
  timer = vim.uv.new_timer()
  if not timer then
    pcall(vim.fn.jobstop, job_id)
    vim.api.nvim_buf_delete(term_bufnr, { force = true })
    callback({ success = false, error = messages["tool.error.timer"]{} })
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
        local partial_output = read_terminal_output(term_bufnr)
        destroy_terminal_buffer(term_bufnr, label)
        local error_msg = messages["tool.bash.timeout"]{ count = timeout }
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
    destroy_terminal_buffer(term_bufnr, label)
  end
end

---Execute a bash command using jobstart + sink (Neovim 0.11.x safe path).
---@param input table<string, any>
---@param ctx flemma.tools.ExecutionContext
---@param callback fun(result: flemma.tools.ExecutionResult)
---@return fun()|nil cancel
local function execute_jobstart(input, ctx, callback)
  local cmd = input.command
  if not cmd or cmd == "" then
    callback({ success = false, error = messages["tool.bash.error.no_command"]{} })
    return nil
  end

  local timeout = input.timeout or ctx.timeout
  local label = input.label or "cmd"

  local output_sink = sink_module.create({
    name = "bash/" .. label,
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

        -- Apply tail truncation with overflow handling
        local result = ctx.truncate.truncate_with_overflow(full_output, {
          direction = "tail",
        })
        local output_text = result.content ~= "" and result.content or messages["tool.bash.no_output"]{}

        if code ~= 0 then
          output_text = output_text .. "\n\n" .. messages["tool.error.exit_code"]{ code = code }
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
  -- cwd is already resolved by executor (config > urn:flemma:buffer:path > Neovim cwd)
  job_opts.cwd = ctx.cwd
  local tool_config = ctx:get_config()
  if tool_config and tool_config.env then
    job_opts.env = tool_config.env
  end
  local store_ok, store_path = pcall(store.get_buffer_store_path, ctx.bufnr)
  if store_ok and store_path then
    job_opts.env = vim.tbl_extend("force", job_opts.env or vim.fn.environ(), {
      FLEMMA_TOOLS_STORE_PATH = store_path,
    })
    if cmd:find("FLEMMA_TOOLS_STORE_PATH", 1, true) then
      local ensure_ok, ensure_err = pcall(store.ensure_buffer_store_path, ctx.bufnr)
      if not ensure_ok then
        log.warn("bash: could not create store directory: " .. tostring(ensure_err))
      end
    end
  end

  local shell = (tool_config and tool_config.shell) or "bash"
  -- Redirect stderr to stdout for the entire shell so output is interleaved
  local inner_cmd = { shell, "-c", "exec 2>&1\n" .. cmd }

  -- Sandbox wrapping (if enabled)
  local wrapped_cmd, sandbox_err = ctx.sandbox.wrap_command(inner_cmd)
  if not wrapped_cmd then
    output_sink:destroy()
    callback({ success = false, error = messages["tool.error.sandbox"]{ detail = sandbox_err } })
    return nil
  end

  local job_id = vim.fn.jobstart(wrapped_cmd, job_opts)

  if job_id <= 0 then
    output_sink:destroy()
    callback({ success = false, error = messages["tool.error.job_start"]{} })
    return nil
  end

  -- Setup timeout
  timer = vim.uv.new_timer()
  if not timer then
    pcall(vim.fn.jobstop, job_id)
    output_sink:destroy()
    callback({ success = false, error = messages["tool.error.timer"]{} })
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
        local all_lines = output_sink:read_lines()
        local partial_output = table.concat(all_lines, "\n"):gsub("%s+$", "")
        output_sink:destroy()
        local error_msg = messages["tool.bash.timeout"]{ count = timeout }
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
end

-- Definition --

M.definitions = {
  {
    name = "bash",
    metadata = {
      config_schema = s.object({
        shell = s.optional(s.string()),
        cwd = s.optional(s.string("urn:flemma:buffer:path")),
        env = s.optional(s.map(s.string(), s.string())),
      }),
    },
    capabilities = { "auto_approves_if_sandboxed" },
    description = messages["tool.bash.description"]{
      max_lines = truncate.MAX_LINES,
      max_bytes_kb = math.floor(truncate.MAX_BYTES / 1024),
    },
    strict = true,
    input_schema = s.object({
      label = s.string():describe(messages["tool.bash.input.label"]),
      command = s.string():describe(messages["tool.bash.input.command"]),
      timeout = s.number():nullable():describe(messages["tool.bash.input.timeout"]),
    }):strict(),
    personalities = {
      ["coding-assistant"] = {
        snippet = messages["tool.bash.personality.snippet"]{},
        guidelines = messages["tool.bash.personality.guidelines"]{},
      },
    },
    async = true,
    ---@return flemma.tools.ToolPreview
    format_preview = function(input)
      return {
        label = input.label,
        detail = "$ " .. input.command,
        highlight = { lang = "bash" },
      }
    end,
    execute = HAS_TERMINAL_PTY_FIX and execute_terminal or execute_jobstart,
  },
}

return M
