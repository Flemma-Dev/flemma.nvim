--- User command definitions for Flemma
--- Centralizes all vim.api.nvim_create_user_command calls
---@class flemma.Commands
local M = {}

---@class flemma.commands.ActionContext
---@field extra_args string[]
---@field fargs string[]
---@field opts table<string, any>

---@class flemma.commands.CommandNode
---@field children? table<string, flemma.commands.CommandNode>
---@field action? fun(context: flemma.commands.ActionContext)
---@field complete? fun(arglead: string, ctx: { completing_index: integer, extra_args: string[] }): string[]
---@field aliases? string[]

---@private
local function setup_commands()
  local core = require("flemma.core")
  local navigation = require("flemma.navigation")
  local log = require("flemma.logging")
  local registry = require("flemma.provider.registry")
  local notify_module = require("flemma.notify")
  local modeline = require("flemma.modeline")
  local presets = require("flemma.presets")

  ---@param enable? boolean
  local function toggle_logging(enable)
    if enable == nil then
      enable = not log.is_enabled()
    end
    log.set_enabled(enable)
    if enable then
      vim.notify("Flemma: Logging enabled - " .. log.get_path())
    else
      vim.notify("Flemma: Logging disabled")
    end
  end

  local function open_log()
    if not log.is_enabled() then
      vim.notify("Flemma: Logging is currently disabled", vim.log.levels.WARN)
      vim.defer_fn(function()
        vim.cmd("tabedit " .. log.get_path())
      end, 1000)
      return
    end
    vim.cmd("tabedit " .. log.get_path())
  end

  ---@param value string|function|nil
  ---@param label string
  ---@return function|nil
  local function build_action_callback(value, label)
    if value == nil or value == "" then
      return nil
    end

    if type(value) == "function" then
      return function(...)
        local ok, err = pcall(value, ...)
        if not ok then
          vim.notify(("Flemma: %s callback failed: %s"):format(label, err), vim.log.levels.ERROR)
        end
      end
    end

    if type(value) ~= "string" then
      vim.notify(
        ("Flemma: %s expects a string or function, received %s"):format(label, type(value)),
        vim.log.levels.WARN
      )
      return nil
    end

    return function()
      local ok, err = pcall(vim.cmd --[[@as function]], value)
      if not ok then
        vim.notify(("Flemma: %s command failed: %s"):format(label, err), vim.log.levels.ERROR)
      end
    end
  end

  ---@type flemma.commands.CommandNode
  local command_tree = { children = {} }

  ---@param arglead string
  ---@param ctx { completing_index: integer, extra_args: string[] }
  ---@return string[]
  local function switch_complete(arglead, ctx)
    if ctx.completing_index == 1 then
      local preset_suggestions = presets.list()
      local provider_suggestions = {}
      for name, _ in pairs(registry.models) do
        table.insert(provider_suggestions, name)
      end
      table.sort(provider_suggestions)

      local function matches_prefix(item)
        return vim.startswith(item, arglead)
      end

      local ordered = {}
      for _, item in ipairs(preset_suggestions) do
        if matches_prefix(item) then
          table.insert(ordered, item)
        end
      end
      for _, item in ipairs(provider_suggestions) do
        if matches_prefix(item) then
          table.insert(ordered, item)
        end
      end

      return ordered
    elseif ctx.completing_index == 2 then
      local first_arg = ctx.extra_args[1]
      if not first_arg then
        return {}
      end

      if vim.startswith(first_arg, "$") then
        local preset = presets.get(first_arg)
        if not preset or not preset.model then
          return {}
        end
        local options = { preset.model }
        return vim.tbl_filter(function(model)
          return vim.startswith(model, arglead)
        end, options)
      end

      local models = registry.models[first_arg]
      if type(models) ~= "table" then
        return {}
      end
      return vim.tbl_filter(function(model)
        return vim.startswith(model, arglead)
      end, models)
    end
    return {}
  end

  command_tree.children.send = {
    action = function(context)
      local named_args = modeline.parse_args(context.extra_args, 1)

      local on_request_start = build_action_callback(named_args.on_request_start, "on_request_start")
      named_args.on_request_start = nil

      local on_request_complete = build_action_callback(named_args.on_request_complete, "on_request_complete")
      if on_request_complete then
        named_args.on_request_complete = on_request_complete
      else
        named_args.on_request_complete = nil
      end

      if on_request_start then
        on_request_start()
      end

      if next(named_args) then
        core.send_to_provider(named_args)
      else
        core.send_to_provider()
      end
    end,
    complete = function(arglead, ctx)
      if ctx.completing_index == 1 then
        local suggestions = { "on_request_start=", "on_request_complete=" }
        return vim.tbl_filter(function(item)
          return vim.startswith(item, arglead)
        end, suggestions)
      end
      return {}
    end,
  }

  command_tree.children.cancel = {
    action = function()
      local bufnr = vim.api.nvim_get_current_buf()
      local executor = require("flemma.tools.executor")
      if not executor.cancel_for_buffer(bufnr) then
        vim.notify("Flemma: Nothing to cancel", vim.log.levels.INFO)
      end
    end,
  }

  command_tree.children.import = {
    action = function()
      local state = require("flemma.state")
      local provider = state.get_provider()

      if not provider or not provider.try_import_from_buffer then
        vim.notify("Flemma import: Current provider does not support importing", vim.log.levels.ERROR)
        return
      end

      local bufnr = vim.api.nvim_get_current_buf()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      local chat_content = provider:try_import_from_buffer(lines)
      if chat_content then
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(chat_content, "\n", {}))
        vim.bo[bufnr].filetype = "chat"
      end
    end,
  }

  command_tree.children.switch = {
    action = function(context)
      local args = context.extra_args

      if #args == 0 then
        local providers = {}
        for name, _ in pairs(registry.models) do
          table.insert(providers, name)
        end
        table.sort(providers)

        vim.ui.select(providers, { prompt = "Select Provider:" }, function(selected_provider)
          if not selected_provider then
            vim.notify("Flemma: Provider selection cancelled", vim.log.levels.INFO)
            return
          end

          local models = registry.models[selected_provider] or {}
          if type(models) ~= "table" or #models == 0 then
            vim.notify("Flemma: No models found for provider " .. selected_provider, vim.log.levels.WARN)
            core.switch_provider(selected_provider, nil, {})
            return
          end

          vim.ui.select(models, { prompt = "Select Model for " .. selected_provider .. ":" }, function(selected_model)
            if not selected_model then
              vim.notify("Flemma: Model selection cancelled", vim.log.levels.INFO)
              return
            end
            core.switch_provider(selected_provider, selected_model, {})
          end)
        end)
        return
      end

      local first_arg = args[1]
      if first_arg and vim.startswith(first_arg, "$") then
        local preset = presets.get(first_arg)
        if not preset then
          vim.notify(("Flemma: Unknown preset '%s'"):format(first_arg), vim.log.levels.WARN)
          return
        end

        local provider = preset.provider
        local model = preset.model
        local key_value_args = vim.deepcopy(preset.parameters or {})

        local remaining_args = {}
        for i = 2, #args do
          remaining_args[#remaining_args + 1] = args[i]
        end

        local overrides = modeline.parse_args(remaining_args, 1)
        local extracted_overrides = registry.extract_switch_arguments(overrides)

        if extracted_overrides.has_explicit_provider and extracted_overrides.provider ~= nil then
          provider = extracted_overrides.provider
        end

        if extracted_overrides.has_explicit_model and extracted_overrides.model ~= nil then
          model = extracted_overrides.model
        elseif extracted_overrides.positionals[1] ~= nil then
          model = extracted_overrides.positionals[1]
        end

        local consumed_positionals = 0
        if not extracted_overrides.has_explicit_model and extracted_overrides.positionals[1] ~= nil then
          consumed_positionals = 1
        end

        if #extracted_overrides.positionals > consumed_positionals then
          local ignored = {}
          for i = consumed_positionals + 1, #extracted_overrides.positionals do
            ignored[#ignored + 1] = extracted_overrides.positionals[i]
          end
          if #ignored > 0 then
            vim.notify(
              ("Flemma: Ignoring extra positional arguments for preset '%s': %s"):format(
                first_arg,
                table.concat(ignored, ", ")
              ),
              vim.log.levels.WARN
            )
          end
        end

        for k, v in pairs(extracted_overrides.parameters) do
          key_value_args[k] = v
        end

        if not provider then
          vim.notify(("Flemma: Preset '%s' must define a provider"):format(first_arg), vim.log.levels.WARN)
          return
        end

        core.switch_provider(provider, model, key_value_args)
        return
      end

      local parsed_args = modeline.parse_args(args, 1)
      local extracted = registry.extract_switch_arguments(parsed_args)
      local provider = extracted.provider

      if not provider then
        vim.notify("Flemma: Provider name required (use :Flemma switch <provider>)", vim.log.levels.WARN)
        return
      end

      if #extracted.extra_positionals > 0 then
        vim.notify(
          ("Flemma: Ignoring extra positional arguments: %s"):format(table.concat(extracted.extra_positionals, ", ")),
          vim.log.levels.WARN
        )
      end

      local parameters = {}
      for k, v in pairs(extracted.parameters) do
        parameters[k] = v
      end

      core.switch_provider(provider, extracted.model, parameters)
    end,
    complete = switch_complete,
  }

  command_tree.children.message = {
    children = {
      next = {
        action = function()
          navigation.find_next_message()
        end,
      },
      previous = {
        action = function()
          navigation.find_prev_message()
        end,
        aliases = { "prev" },
      },
    },
  }

  command_tree.children.logging = {
    children = {
      enable = {
        action = function()
          toggle_logging(true)
        end,
      },
      disable = {
        action = function()
          toggle_logging(false)
        end,
      },
      open = {
        action = function()
          open_log()
        end,
      },
    },
  }

  command_tree.children.notification = {
    children = {
      recall = {
        action = function()
          notify_module.recall_last()
        end,
      },
    },
  }

  command_tree.children.autopilot = {
    children = {
      enable = {
        action = function()
          local autopilot = require("flemma.autopilot")
          autopilot.set_enabled(true)
          vim.notify("Flemma: Autopilot enabled", vim.log.levels.INFO)
        end,
      },
      disable = {
        action = function()
          local autopilot = require("flemma.autopilot")
          autopilot.set_enabled(false)
          vim.notify("Flemma: Autopilot disabled", vim.log.levels.INFO)
        end,
      },
      status = {
        action = function()
          local autopilot = require("flemma.autopilot")
          local bufnr = vim.api.nvim_get_current_buf()
          local enabled = autopilot.is_enabled(bufnr)
          local buffer_state = autopilot.get_state(bufnr)
          vim.notify(
            string.format("Flemma: Autopilot %s (buffer state: %s)", enabled and "enabled" or "disabled", buffer_state),
            vim.log.levels.INFO
          )
        end,
      },
    },
  }

  command_tree.children.tool = {
    children = {
      execute = {
        action = function()
          local bufnr = vim.api.nvim_get_current_buf()
          local executor = require("flemma.tools.executor")
          local ok, err = executor.execute_at_cursor(bufnr)
          if not ok then
            vim.notify("Flemma: " .. (err or "Execution failed"), vim.log.levels.ERROR)
          end
        end,
      },
      cancel = {
        action = function()
          local bufnr = vim.api.nvim_get_current_buf()
          local executor = require("flemma.tools.executor")
          local cancelled = executor.cancel_at_cursor(bufnr)
          if cancelled then
            vim.notify("Flemma: Tool execution cancelled", vim.log.levels.INFO)
          else
            vim.notify("Flemma: No pending tool executions", vim.log.levels.INFO)
          end
        end,
      },
      ["cancel-all"] = {
        action = function()
          local bufnr = vim.api.nvim_get_current_buf()
          local executor = require("flemma.tools.executor")
          executor.cancel_all(bufnr)
          vim.notify("Flemma: All tool executions cancelled", vim.log.levels.INFO)
        end,
      },
      list = {
        action = function()
          local bufnr = vim.api.nvim_get_current_buf()
          local executor = require("flemma.tools.executor")
          local pending = executor.get_pending(bufnr)
          if #pending == 0 then
            vim.notify("Flemma: No pending tool executions", vim.log.levels.INFO)
          else
            table.sort(pending, function(a, b)
              return a.started_at < b.started_at
            end)
            local lines = { "Flemma: Pending tool executions:" }
            for _, p in ipairs(pending) do
              table.insert(
                lines,
                string.format("  %s (%s) - started %ds ago", p.tool_name, p.tool_id, os.time() - p.started_at)
              )
            end
            vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
          end
        end,
      },
    },
  }

  ---@param node flemma.commands.CommandNode
  ---@param prefix string|nil
  ---@param acc string[]
  ---@param seen table<string, boolean>
  local function collect_commands(node, prefix, acc, seen)
    if not node.children then
      return
    end

    local keys = vim.tbl_keys(node.children)
    table.sort(keys)

    for _, name in ipairs(keys) do
      local child = node.children[name]
      local new_prefix = prefix and (prefix .. ":" .. name) or name

      if child.action and not seen[new_prefix] then
        table.insert(acc, new_prefix)
        seen[new_prefix] = true
      end

      if child.aliases then
        for _, alias in ipairs(child.aliases) do
          local alias_path = prefix and (prefix .. ":" .. alias) or alias
          if not seen[alias_path] then
            table.insert(acc, alias_path)
            seen[alias_path] = true
          end
        end
      end

      collect_commands(child, new_prefix, acc, seen)
    end
  end

  local available_commands = {}
  collect_commands(command_tree, nil, available_commands, {})
  table.sort(available_commands)

  ---@param node flemma.commands.CommandNode
  ---@param segment string
  ---@return flemma.commands.CommandNode|nil
  local function find_child(node, segment)
    if not node.children then
      return nil
    end

    if node.children[segment] then
      return node.children[segment]
    end

    for _, child in pairs(node.children) do
      if child.aliases then
        for _, alias in ipairs(child.aliases) do
          if alias == segment then
            return child
          end
        end
      end
    end

    return nil
  end

  ---@param token string|nil
  ---@return flemma.commands.CommandNode|nil
  local function resolve_command(token)
    if not token or token == "" then
      return nil
    end

    local segments = vim.split(token, ":", { plain = true, trimempty = true })
    local current = command_tree

    for _, segment in ipairs(segments) do
      local child = find_child(current, segment)
      if not child then
        return nil
      end
      current = child
    end

    return current
  end

  ---@param node flemma.commands.CommandNode
  ---@param prefix string|nil
  ---@return string[]
  local function list_child_names(node, prefix)
    local names = {}
    if not node.children then
      return names
    end

    for name, child in pairs(node.children) do
      table.insert(names, prefix and (prefix .. ":" .. name) or name)
      if child.aliases then
        for _, alias in ipairs(child.aliases) do
          table.insert(names, prefix and (prefix .. ":" .. alias) or alias)
        end
      end
    end

    table.sort(names)
    return names
  end

  ---@param fargs string[]
  ---@param opts table
  local function run_command(fargs, opts)
    if #fargs == 0 then
      vim.notify("Flemma: Available commands → " .. table.concat(available_commands, ", "), vim.log.levels.INFO)
      return
    end

    local command_token = fargs[1]
    local node = resolve_command(command_token)
    if not node then
      vim.notify(("Flemma: Unknown command '%s'"):format(command_token), vim.log.levels.ERROR)
      return
    end

    if not node.action then
      local child_names = list_child_names(node, command_token)
      if #child_names == 0 then
        vim.notify(("Flemma: '%s' is not invokable"):format(command_token), vim.log.levels.WARN)
      else
        vim.notify(
          ("Flemma: '%s' expects a sub-command (%s)"):format(command_token, table.concat(child_names, ", ")),
          vim.log.levels.INFO
        )
      end
      return
    end

    local extra_args = {}
    for i = 2, #fargs do
      extra_args[#extra_args + 1] = fargs[i]
    end

    node.action({
      extra_args = extra_args,
      fargs = fargs,
      opts = opts,
    })
  end

  ---@param arglead string
  ---@param cmdline string
  ---@return string[]
  local function completion(arglead, cmdline, _)
    local args = vim.split(cmdline, "%s+", { trimempty = true })
    local trailing_space = cmdline:match("%s$")
    local command_args = {}
    for i = 2, #args do
      table.insert(command_args, args[i])
    end

    if #command_args == 0 or (#command_args == 1 and not trailing_space) then
      return vim.tbl_filter(function(item)
        return vim.startswith(item, arglead)
      end, available_commands)
    end

    local command_token = command_args[1]
    local node = resolve_command(command_token)
    if not node or not node.complete then
      return {}
    end

    local extra_args = {}
    for i = 2, #command_args do
      table.insert(extra_args, command_args[i])
    end

    local completing_index = trailing_space and (#extra_args + 1) or #extra_args

    return node.complete(arglead, {
      extra_args = extra_args,
      completing_index = completing_index,
    }) or {}
  end

  vim.api.nvim_create_user_command("Flemma", function(opts)
    run_command(opts.fargs, opts)
  end, {
    nargs = "*",
    complete = completion,
  })

  ---@param arglead string
  ---@param cmdline string
  ---@return string[]
  local function switch_legacy_completion(arglead, cmdline, _)
    local args = vim.split(cmdline, "%s+", { trimempty = true })
    local trailing_space = cmdline:match("%s$")
    local extra_args = {}
    for i = 2, #args do
      table.insert(extra_args, args[i])
    end
    local completing_index = trailing_space and (#extra_args + 1) or #extra_args

    return switch_complete(arglead, {
      extra_args = extra_args,
      completing_index = completing_index,
    }) or {}
  end

  local legacy_commands = {
    { name = "FlemmaSend", new_usage = "Flemma send", fargs = { "send" }, forward_args = true },
    { name = "FlemmaCancel", new_usage = "Flemma cancel", fargs = { "cancel" } },
    { name = "FlemmaImport", new_usage = "Flemma import", fargs = { "import" } },
    {
      name = "FlemmaSendAndInsert",
      new_usage = "Flemma send on_request_start=stopinsert on_request_complete=startinsert!",
      fargs = { "send", "on_request_start=stopinsert", "on_request_complete=startinsert!" },
    },
    {
      name = "FlemmaSwitch",
      new_usage = "Flemma switch",
      fargs = { "switch" },
      forward_args = true,
      nargs = "*",
      complete = switch_legacy_completion,
    },
    { name = "FlemmaNextMessage", new_usage = "Flemma message:next", fargs = { "message:next" } },
    { name = "FlemmaPrevMessage", new_usage = "Flemma message:previous", fargs = { "message:previous" } },
    { name = "FlemmaEnableLogging", new_usage = "Flemma logging:enable", fargs = { "logging:enable" } },
    { name = "FlemmaDisableLogging", new_usage = "Flemma logging:disable", fargs = { "logging:disable" } },
    { name = "FlemmaOpenLog", new_usage = "Flemma logging:open", fargs = { "logging:open" } },
    { name = "FlemmaRecallNotification", new_usage = "Flemma notification:recall", fargs = { "notification:recall" } },
  }

  for _, spec in ipairs(legacy_commands) do
    vim.api.nvim_create_user_command(spec.name, function(opts)
      vim.notify((":%s has moved to :%s"):format(spec.name, spec.new_usage), vim.log.levels.WARN)

      local new_fargs = { unpack(spec.fargs or {}) }
      if spec.forward_args and #opts.fargs > 0 then
        new_fargs = vim.list_extend(new_fargs, opts.fargs)
      end
      run_command(new_fargs, opts)
    end, {
      nargs = spec.nargs or 0,
      complete = spec.complete,
    })
  end
end

---Setup function to register all user commands
M.setup = function()
  setup_commands()
end

return M
