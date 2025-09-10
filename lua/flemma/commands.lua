--- User command definitions for Flemma
--- Centralizes all vim.api.nvim_create_user_command calls
local M = {}

local function setup_commands()
  local core = require("flemma.core")
  local navigation = require("flemma.navigation")
  local buffers = require("flemma.buffers")
  local log = require("flemma.logging")
  local provider_config = require("flemma.provider.config")

  -- Helper function to toggle logging
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

  -- Parse key=value arguments
  local function parse_key_value_args(args, start_index)
    local result = {}
    for i = start_index or 3, #args do
      local arg = args[i]
      local key, value = arg:match("^([%w_]+)=(.+)$")

      if key and value then
        -- Convert value to appropriate type
        if value == "true" then
          value = true
        elseif value == "false" then
          value = false
        elseif value == "nil" or value == "null" then
          value = nil
        elseif tonumber(value) then
          value = tonumber(value)
        end

        result[key] = value
      end
    end
    return result
  end

  -- Core commands
  vim.api.nvim_create_user_command("FlemmaSend", function()
    core.send_to_provider()
  end, {})

  vim.api.nvim_create_user_command("FlemmaCancel", function()
    core.cancel_request()
  end, {})

  vim.api.nvim_create_user_command("FlemmaImport", function()
    local state = require("flemma.state")
    local provider = state.get_provider()

    if not provider or not provider.try_import_from_buffer then
      vim.notify("FlemmaImport: Current provider does not support importing", vim.log.levels.ERROR)
      return
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local chat_content = provider:try_import_from_buffer(lines)
    if chat_content then
      -- Replace buffer contents with the imported chat
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(chat_content, "\n", {}))
      -- Set filetype to chat
      vim.bo[bufnr].filetype = "chat"
    end
  end, {})

  vim.api.nvim_create_user_command("FlemmaSendAndInsert", function()
    local bufnr = vim.api.nvim_get_current_buf()
    buffers.buffer_cmd(bufnr, "stopinsert")
    core.send_to_provider({
      on_complete = function()
        buffers.buffer_cmd(bufnr, "startinsert!")
      end,
    })
  end, {})

  -- Command to switch providers
  vim.api.nvim_create_user_command("FlemmaSwitch", function(opts)
    local args = opts.fargs

    if #args == 0 then
      -- Interactive selection if no arguments are provided
      local providers = {}
      for name, _ in pairs(provider_config.models) do
        table.insert(providers, name)
      end
      table.sort(providers) -- Sort providers for the selection list

      vim.ui.select(providers, { prompt = "Select Provider:" }, function(selected_provider)
        if not selected_provider then
          vim.notify("Flemma: Provider selection cancelled", vim.log.levels.INFO)
          return
        end

        -- Get models for the selected provider (unsorted)
        local models = provider_config.models[selected_provider] or {}
        if type(models) ~= "table" or #models == 0 then
          vim.notify("Flemma: No models found for provider " .. selected_provider, vim.log.levels.WARN)
          -- Switch to provider with default model
          core.switch_provider(selected_provider, nil, {})
          return
        end

        vim.ui.select(models, { prompt = "Select Model for " .. selected_provider .. ":" }, function(selected_model)
          if not selected_model then
            vim.notify("Flemma: Model selection cancelled", vim.log.levels.INFO)
            return
          end
          -- Call core.switch_provider with selected provider and model, no extra params
          core.switch_provider(selected_provider, selected_model, {})
        end)
      end)
    else
      -- Existing logic for handling command-line arguments
      local switch_opts = {
        provider = args[1],
      }

      if args[2] and not args[2]:match("^[%w_]+=") then
        switch_opts.model = args[2]
      end

      -- Parse any key=value pairs
      local key_value_args = parse_key_value_args(args, switch_opts.model and 3 or 2)
      for k, v in pairs(key_value_args) do
        switch_opts[k] = v
      end

      -- Call the refactored core.switch_provider function
      core.switch_provider(switch_opts.provider, switch_opts.model, key_value_args)
    end
  end, {
    nargs = "*", -- Allow zero arguments for interactive mode
    complete = function(arglead, cmdline, _)
      local args = vim.split(cmdline, "%s+", { trimempty = true })
      local num_args = #args
      local trailing_space = cmdline:match("%s$")

      -- If completing the provider name (argument 2)
      if num_args == 1 or (num_args == 2 and not trailing_space) then
        local providers = {}
        for name, _ in pairs(provider_config.models) do
          table.insert(providers, name)
        end
        table.sort(providers)
        return vim.tbl_filter(function(p)
          return vim.startswith(p, arglead)
        end, providers)
      -- If completing the model name (argument 3)
      elseif (num_args == 2 and trailing_space) or (num_args == 3 and not trailing_space) then
        local provider_name = args[2]
        -- Access the model list directly from the new structure
        local models = provider_config.models[provider_name] or {}

        -- Ensure models is a table before sorting and filtering
        if type(models) == "table" then
          -- Filter the original (unsorted) list
          return vim.tbl_filter(function(model)
            return vim.startswith(model, arglead)
          end, models)
        end
        -- If the provider doesn't exist or models isn't a table, return empty
        return {}
      end

      -- Default: return empty list if no completion matches
      return {}
    end,
  })

  -- Navigation commands
  vim.api.nvim_create_user_command("FlemmaNextMessage", function()
    navigation.find_next_message()
  end, {})

  vim.api.nvim_create_user_command("FlemmaPrevMessage", function()
    navigation.find_prev_message()
  end, {})

  -- Logging commands
  vim.api.nvim_create_user_command("FlemmaEnableLogging", function()
    toggle_logging(true)
  end, {})

  vim.api.nvim_create_user_command("FlemmaDisableLogging", function()
    toggle_logging(false)
  end, {})

  vim.api.nvim_create_user_command("FlemmaOpenLog", function()
    if not log.is_enabled() then
      vim.notify("Flemma: Logging is currently disabled", vim.log.levels.WARN)
      -- Give user time to see the warning
      vim.defer_fn(function()
        vim.cmd("tabedit " .. log.get_path())
      end, 1000)
    else
      vim.cmd("tabedit " .. log.get_path())
    end
  end, {})

  -- Command to recall last notification
  vim.api.nvim_create_user_command("FlemmaRecallNotification", function()
    require("flemma.notify").recall_last()
  end, {
    desc = "Recall the last notification",
  })
end

-- Setup function to initialize all commands
M.setup = function()
  setup_commands()
end

return M
