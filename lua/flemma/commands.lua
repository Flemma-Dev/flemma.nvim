--- User command definitions for Flemma
--- Centralizes all vim.api.nvim_create_user_command calls
---@class flemma.Commands
local M = {}

local messages = require("flemma.messages")
local notify = require("flemma.notify")
local string_utils = require("flemma.utilities.string")

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
  ---@param enable? boolean
  ---@param level? string Optional log level to set (e.g. "TRACE", "DEBUG")
  local function toggle_logging(enable, level)
    local log = require("flemma.logging")
    if enable == nil then
      enable = not log.is_enabled()
    end
    if level then
      if not log.is_valid_level(level) then
        notify.error(messages["ui.logging.invalid_level"]{ level = level })
        return
      end
      log.configure({ level = level:upper() })
    end
    log.set_enabled(enable)
    if enable then
      local level_display = log.get_level()
      notify.info(messages["ui.logging.enabled"]{ level = level_display, path = log.get_path() })
    else
      notify.info(messages["ui.logging.disabled"]{})
    end
  end

  local function open_log()
    local log = require("flemma.logging")
    if not log.is_enabled() then
      notify.warn(messages["ui.logging.currently_disabled"]{})
      vim.defer_fn(function()
        vim.cmd("tabedit " .. require("flemma.logging").get_path())
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
          notify.error(messages["ui.callback.failed"]{ label = label, reason = err })
        end
      end
    end

    if type(value) ~= "string" then
      notify.warn(messages["ui.callback.invalid_type"]{ label = label, received = type(value) })
      return nil
    end

    return function()
      local ok, err = pcall(vim.cmd --[[@as function]], value)
      if not ok then
        notify.error(messages["ui.callback.command_failed"]{ label = label, reason = err })
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
      local presets = require("flemma.presets")
      local provider_registry = require("flemma.provider.registry")
      local preset_suggestions = vim.tbl_filter(function(name)
        local preset = presets.get(name)
        if not preset or not preset.provider then
          return false
        end
        return true
      end, presets.list())
      local provider_suggestions = {}
      for name, _ in pairs(provider_registry.models) do
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
        local preset = require("flemma.presets").get(first_arg)
        if not preset or not preset.model then
          return {}
        end
        local options = { preset.model }
        return vim.tbl_filter(function(model)
          return vim.startswith(model, arglead)
        end, options)
      end

      local models = require("flemma.provider.registry").models[first_arg]
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
      local modeline = require("flemma.utilities.modeline")
      local core = require("flemma.core")
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
      if not require("flemma.tools.executor").cancel_for_buffer(bufnr) then
        notify.info(messages["ui.tool.nothing_to_cancel"]{})
      end
    end,
  }

  command_tree.children.switch = {
    action = function(context)
      local core = require("flemma.core")
      local modeline = require("flemma.utilities.modeline")
      local presets = require("flemma.presets")
      local provider_registry = require("flemma.provider.registry")
      local args = context.extra_args
      local bufnr = vim.api.nvim_get_current_buf()

      if #args == 0 then
        local providers = {}
        for name, _ in pairs(provider_registry.models) do
          table.insert(providers, name)
        end
        table.sort(providers)

        vim.ui.select(providers, { prompt = messages["ui.provider.select_prompt"]{} }, function(selected_provider)
          if not selected_provider then
            notify.info(messages["ui.provider.select_cancelled"]{})
            return
          end

          local models = provider_registry.models[selected_provider] or {}
          if type(models) ~= "table" or #models == 0 then
            notify.warn(messages["ui.provider.no_models"]{ provider = selected_provider })
            core.switch_provider(selected_provider, nil, {}, { bufnr = bufnr })
            return
          end

          vim.ui.select(
            models,
            { prompt = messages["ui.provider.select_model_prompt"]{ provider = selected_provider } },
            function(selected_model)
              if not selected_model then
                notify.info(messages["ui.provider.model_select_cancelled"]{})
                return
              end
              core.switch_provider(selected_provider, selected_model, {}, { bufnr = bufnr })
            end
          )
        end)
        return
      end

      local first_arg = args[1]
      if first_arg and vim.startswith(first_arg, "$") then
        local preset = presets.get(first_arg)
        if not preset then
          notify.warn(messages["ui.provider.unknown_preset"]{ preset = first_arg })
          return
        end

        local config_facade = require("flemma.config")
        if preset.tools then
          config_facade.writer(bufnr, config_facade.LAYERS.RUNTIME).tools = preset.tools
        end
        if preset.auto_approve then
          config_facade.writer(bufnr, config_facade.LAYERS.RUNTIME).tools.auto_approve = preset.auto_approve
        end

        local provider = preset.provider
        local model = preset.model

        -- route_parameters writes a provider-bearing preset's config-shaped
        -- parameters structurally — like preset.tools above, and BEFORE
        -- switch_provider's own writes so command-line overrides (matrix or
        -- space form) win on store order — and returns a provider-less preset's
        -- flat parameters for the explicit channel.
        local key_value_args = presets.route_parameters(preset, config_facade.writer(nil, config_facade.LAYERS.RUNTIME))

        local remaining_args = {}
        for i = 2, #args do
          remaining_args[#remaining_args + 1] = args[i]
        end

        local overrides = modeline.parse_args(remaining_args, 1, { preserve_nil = true })
        local extracted_overrides = provider_registry.extract_switch_arguments(overrides)

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
            notify.warn(messages["ui.provider.ignoring_positionals_preset"]{
              preset = first_arg,
              args = table.concat(ignored, ", "),
            })
          end
        end

        for k, v in pairs(extracted_overrides.parameters) do
          key_value_args[k] = v
        end

        if provider then
          core.switch_provider(provider, model, key_value_args, { bufnr = bufnr })
        end
        return
      end

      local parsed_args = modeline.parse_args(args, 1, { preserve_nil = true })
      local extracted = provider_registry.extract_switch_arguments(parsed_args)
      local provider = extracted.provider

      if not provider then
        notify.warn(messages["ui.provider.name_required"]{})
        return
      end

      if #extracted.extra_positionals > 0 then
        notify.warn(
          messages["ui.provider.ignoring_positionals"]{ args = table.concat(extracted.extra_positionals, ", ") }
        )
      end

      local parameters = {}
      for k, v in pairs(extracted.parameters) do
        parameters[k] = v
      end

      core.switch_provider(provider, extracted.model, parameters, { bufnr = bufnr })
    end,
    complete = switch_complete,
  }

  command_tree.children.message = {
    children = {
      next = {
        action = function()
          require("flemma.navigation").find_next_message()
        end,
      },
      previous = {
        action = function()
          require("flemma.navigation").find_prev_message()
        end,
        aliases = { "prev" },
      },
    },
  }

  command_tree.children.logging = {
    children = {
      enable = {
        action = function(context)
          toggle_logging(true, context.extra_args[1])
        end,
        complete = function(arglead)
          local levels = { "TRACE", "DEBUG", "INFO", "WARN", "ERROR" }
          return vim.tbl_filter(function(item)
            return vim.startswith(item, arglead:upper())
          end, levels)
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

  command_tree.children.diagnostics = {
    children = {
      diff = {
        action = function(context)
          local bufnr = vim.api.nvim_get_current_buf()
          local normalized = context.extra_args[1] == "normalized"
          require("flemma.diagnostics").open_diff(bufnr, normalized)
        end,
        complete = function(arglead)
          local options = { "normalized" }
          return vim.tbl_filter(function(item)
            return vim.startswith(item, arglead)
          end, options)
        end,
      },
      enable = {
        action = function()
          local w = require("flemma.config").writer(nil, require("flemma.config").LAYERS.RUNTIME)
          w.diagnostics.enabled = true
          notify.info(messages["ui.diagnostics.enabled"]{})
        end,
      },
      disable = {
        action = function()
          local w = require("flemma.config").writer(nil, require("flemma.config").LAYERS.RUNTIME)
          w.diagnostics.enabled = false
          notify.info(messages["ui.diagnostics.disabled"]{})
        end,
      },
    },
  }

  command_tree.children.ast = {
    children = {
      diff = {
        action = function()
          local bufnr = vim.api.nvim_get_current_buf()
          require("flemma.ast.dump").open_diff(bufnr)
        end,
      },
    },
  }

  command_tree.children.usage = {
    children = {
      recall = {
        action = function()
          require("flemma.usage").recall_last()
        end,
      },
      estimate = {
        action = function()
          local bufnr = vim.api.nvim_get_current_buf()
          local cfg = require("flemma.config").materialize(bufnr)
          local provider_registry = require("flemma.provider.registry")
          local readiness = require("flemma.readiness")
          local provider_module_path = provider_registry.get(cfg.provider)
          if not provider_module_path then
            notify.error(messages["ui.usage.no_provider"]{})
            return
          end

          local provider_module = require("flemma.loader").load(provider_module_path)
          if not provider_module or not provider_module.try_estimate_usage then
            notify.error(messages["ui.usage.estimate_unsupported"]{})
            return
          end

          local function on_result(result)
            if result.err then
              notify.error(messages["ui.usage.estimate_failed"]{ reason = result.err })
              return
            end
            local response = result.response
            local model_info = provider_registry.get_model_info(cfg.provider, response.model)
            local pricing = model_info and model_info.pricing
            notify.info(string_utils.format_estimate(response.tokens, response.model, pricing))
          end

          local diagnostic_format = require("flemma.utilities.diagnostic")

          local function attempt()
            local ok, err = pcall(provider_module.try_estimate_usage, bufnr, on_result)
            if ok then
              return
            end
            if not readiness.is_suspense(err) then
              notify.error(messages["ui.usage.estimate_failed"]{ reason = tostring(err) })
              return
            end
            ---@cast err flemma.readiness.Suspense
            local deferred = notify.delay(600).info(err.message)
            err.boundary:subscribe(function(boundary_result)
              deferred.cancel()
              if not boundary_result or not boundary_result.ok then
                local diag_msg =
                  diagnostic_format.format_resolver_diagnostics(boundary_result and boundary_result.diagnostics)
                notify.error(messages["ui.usage.estimate_failed"]{ reason = diag_msg or err.message })
                return
              end
              attempt()
            end)
          end
          attempt()
        end,
      },
    },
  }

  command_tree.children.autopilot = {
    children = {
      enable = {
        action = function()
          require("flemma.autopilot").set_enabled(true)
          notify.info(messages["ui.autopilot.enabled"]{})
        end,
      },
      disable = {
        action = function()
          require("flemma.autopilot").set_enabled(false)
          notify.info(messages["ui.autopilot.disabled"]{})
        end,
      },
      status = {
        action = function()
          require("flemma.status").show({ jump_to = "Autopilot", bufnr = vim.api.nvim_get_current_buf() })
        end,
      },
    },
  }

  command_tree.children.sandbox = {
    children = {
      enable = {
        action = function()
          local sandbox = require("flemma.sandbox")
          local ok, err = sandbox.validate_backend()
          if not ok then
            notify.error(messages["ui.sandbox.enable_failed"]{ reason = err })
            return
          end
          sandbox.set_enabled(true)
          notify.info(messages["ui.sandbox.enabled"]{})
        end,
      },
      disable = {
        action = function()
          require("flemma.sandbox").set_enabled(false)
          notify.info(messages["ui.sandbox.disabled"]{})
        end,
      },
      status = {
        action = function()
          require("flemma.status").show({ jump_to = "Sandbox", bufnr = vim.api.nvim_get_current_buf() })
        end,
      },
    },
  }

  command_tree.children.status = {
    action = function(context)
      local verbose = false
      for _, arg in ipairs(context.extra_args) do
        if arg == "verbose" then
          verbose = true
        end
      end
      require("flemma.status").show({ verbose = verbose, bufnr = vim.api.nvim_get_current_buf() })
    end,
    complete = function(arglead)
      local suggestions = { "verbose" }
      return vim.tbl_filter(function(item)
        return vim.startswith(item, arglead)
      end, suggestions)
    end,
  }

  command_tree.children.format = {
    action = function()
      require("flemma.migration").migrate_buffer(vim.api.nvim_get_current_buf())
    end,
  }

  command_tree.children.tool = {
    children = {
      execute = {
        action = function()
          local bufnr = vim.api.nvim_get_current_buf()

          local ok, err = require("flemma.tools.executor").execute_at_cursor(bufnr)
          if not ok then
            notify.error(err or messages["ui.tool.execute_failed"]{})
          end
        end,
      },
      background = {
        action = function()
          local bufnr = vim.api.nvim_get_current_buf()

          local ok, err = require("flemma.tools.executor").background_at_cursor(bufnr)
          if not ok then
            notify.error(err or messages["ui.tool.background_failed"]{})
          else
            notify.info(messages["ui.tool.backgrounded"]{})
          end
        end,
      },
      approve = {
        action = function()
          local bufnr = vim.api.nvim_get_current_buf()

          local ok, err = require("flemma.tools.executor").approve_at_cursor(bufnr)
          if not ok then
            notify.error(err or messages["ui.tool.approve_failed"]{})
          end
        end,
      },
      reject = {
        action = function(context)
          local bufnr = vim.api.nvim_get_current_buf()
          local message = nil
          if context.extra_args and #context.extra_args > 0 then
            message = table.concat(context.extra_args, " ")
          end

          local ok, err = require("flemma.tools.executor").reject_at_cursor(bufnr, message)
          if not ok then
            notify.error(err or messages["ui.rejection.reject_failed"]{})
          end
        end,
      },
      cancel = {
        action = function()
          local bufnr = vim.api.nvim_get_current_buf()

          local cancelled = require("flemma.tools.executor").cancel_at_cursor(bufnr)
          if cancelled then
            notify.info(messages["ui.tool.cancelled"]{})
          else
            notify.info(messages["ui.tool.none_pending"]{})
          end
        end,
      },
      ["cancel-all"] = {
        action = function()
          local bufnr = vim.api.nvim_get_current_buf()

          require("flemma.tools.executor").cancel_all(bufnr)
          notify.info(messages["ui.tool.all_cancelled"]{})
        end,
      },
      ["approve-all"] = {
        action = function()
          local bufnr = vim.api.nvim_get_current_buf()

          local ok, err = require("flemma.tools.executor").approve_all_pending(bufnr)
          if not ok then
            notify.error(err or messages["ui.tool.no_pending_approve"]{})
          end
        end,
      },
      list = {
        action = function()
          local bufnr = vim.api.nvim_get_current_buf()

          local pending = require("flemma.tools.executor").get_pending(bufnr)
          if #pending == 0 then
            notify.info(messages["ui.tool.none_pending"]{})
          else
            table.sort(pending, function(a, b)
              return a.started_at < b.started_at
            end)
            local lines = { messages["ui.tool.list_header"]{} }
            for _, p in ipairs(pending) do
              table.insert(
                lines,
                messages["ui.tool.list_row"]{
                  tool_name = p.tool_name,
                  tool_id = p.tool_id,
                  seconds = os.time() - p.started_at,
                }
              )
            end
            notify.info(table.concat(lines, "\n"))
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

    if prefix then
      prefix = prefix:gsub(":+$", "")
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
      notify.info(messages["ui.command.available"]{ commands = table.concat(available_commands, ", ") })
      return
    end

    local command_token = fargs[1]
    local node = resolve_command(command_token)
    if not node then
      local suggestion = string_utils.closest_match(command_token, available_commands)
      local message
      if suggestion then
        message = messages["ui.command.unknown_suggestion"]{ command = command_token, suggestion = suggestion }
      else
        message = messages["ui.command.unknown"]{ command = command_token }
      end
      notify.error(message)
      return
    end

    if not node.action then
      local child_names = list_child_names(node, command_token)
      if #child_names == 0 then
        notify.warn(messages["ui.command.not_invokable"]{ command = command_token })
      else
        notify.info(messages["ui.command.expects_subcommand"]{
          command = command_token,
          subcommands = table.concat(child_names, ", "),
        })
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
end

---Setup function to register all user commands
M.setup = function()
  setup_commands()
end

return M
