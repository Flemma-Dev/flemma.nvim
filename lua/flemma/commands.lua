--- User command definitions for Flemma
--- Centralizes all vim.api.nvim_create_user_command calls
local M = {}

local function setup_commands()
  local core = require("flemma.core")
  local navigation = require("flemma.navigation")
  local log = require("flemma.logging")
  local provider_config = require("flemma.provider.config")
  local notify_module = require("flemma.notify")

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

  local function parse_key_value_args(args, start_index)
    local result = {}
    for i = start_index or 1, #args do
      local arg = args[i]
      local key, value = arg:match("^([%w_]+)=(.+)$")

      if key and value then
        if value == "true" then
          value = true
        elseif value == "false" then
          value = false
        elseif value == "nil" or value == "null" then
          value = nil
        else
          local number_value = tonumber(value)
          if number_value then
            value = number_value
          end
        end
        result[key] = value
      end
    end
    return result
  end

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
      local ok, err = pcall(vim.cmd, value)
      if not ok then
        vim.notify(("Flemma: %s command failed: %s"):format(label, err), vim.log.levels.ERROR)
      end
    end
  end

  local command_tree = { children = {} }

  local function switch_complete(arglead, ctx)
    if ctx.completing_index == 1 then
      local providers = {}
      for name, _ in pairs(provider_config.models) do
        table.insert(providers, name)
      end
      table.sort(providers)
      return vim.tbl_filter(function(item)
        return vim.startswith(item, arglead)
      end, providers)
    elseif ctx.completing_index == 2 then
      local provider_name = ctx.extra_args[1]
      if not provider_name then
        return {}
      end
      local models = provider_config.models[provider_name]
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
      local named_args = parse_key_value_args(context.extra_args, 1)

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
      core.cancel_request()
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
        for name, _ in pairs(provider_config.models) do
          table.insert(providers, name)
        end
        table.sort(providers)

        vim.ui.select(providers, { prompt = "Select Provider:" }, function(selected_provider)
          if not selected_provider then
            vim.notify("Flemma: Provider selection cancelled", vim.log.levels.INFO)
            return
          end

          local models = provider_config.models[selected_provider] or {}
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

      local switch_opts = {
        provider = args[1],
      }

      if not switch_opts.provider then
        vim.notify("Flemma: Provider name required (use :Flemma switch <provider>)", vim.log.levels.WARN)
        return
      end

      if args[2] and not args[2]:match("^[%w_]+=") then
        switch_opts.model = args[2]
      end

      local key_value_args = parse_key_value_args(args, switch_opts.model and 3 or 2)
      for k, v in pairs(key_value_args) do
        switch_opts[k] = v
      end

      core.switch_provider(switch_opts.provider, switch_opts.model, key_value_args)
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

  local function resolve_command(token)
    if not token or token == "" then
      return nil
    end

    local segments = vim.split(token, ":", { plain = true, trimempty = true })
    local current = command_tree

    for _, segment in ipairs(segments) do
      current = find_child(current, segment)
      if not current then
        return nil
      end
    end

    return current
  end

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

M.setup = function()
  setup_commands()
end

return M
