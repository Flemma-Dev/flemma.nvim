--- Flemma plugin core functionality
--- Provides chat interface and API integration
---@class flemma.Plugin
local M = {}

local plugin_config = require("flemma.config")
local config_facade = require("flemma.config.facade")
local schema_definition = require("flemma.config.schema.definition")
local log = require("flemma.logging")
local state = require("flemma.state")
local core = require("flemma.core")
local presets = require("flemma.presets")
local ui = require("flemma.ui")
local commands = require("flemma.commands")
local keymaps = require("flemma.keymaps")
local highlight = require("flemma.highlight")
local provider_registry = require("flemma.provider.registry")
local loader = require("flemma.loader")
local config_manager = require("flemma.core.config.manager")
local notifications = require("flemma.notifications")
local personalities = require("flemma.personalities")
local secrets = require("flemma.secrets")
local tools = require("flemma.tools")
local preprocessor = require("flemma.preprocessor")
local templating = require("flemma.templating")
local tools_presets = require("flemma.tools.presets")
local tools_approval = require("flemma.tools.approval")
local cursor = require("flemma.cursor")
local sandbox = require("flemma.sandbox")
local lsp = require("flemma.lsp")

-- Module configuration (will hold merged user opts and defaults)
local config = {}

---Setup function to initialize the plugin
---@param user_opts? flemma.Config.Opts User configuration overrides (merged with defaults)
M.setup = function(user_opts)
  if vim.fn.has("nvim-0.11") ~= 1 then
    local msg = "Flemma requires Neovim 0.11 or newer. Please upgrade Neovim to use this plugin."
    local notifier = vim.notify
      or function(message)
        vim.api.nvim_echo({ { message, "ErrorMsg" } }, true, {})
      end
    -- Use a scheduled notification so initialization exits gracefully
    vim.schedule(function()
      notifier(msg, vim.log and vim.log.levels and vim.log.levels.ERROR or nil)
    end)
    return
  end

  user_opts = user_opts or {}

  -- Initialize new config system: schema defaults (L10) + user opts (L20).
  -- DISCOVER-backed keys (tool/provider-specific config) are deferred until
  -- after module registration. Known keys are validated immediately.
  config_facade.init(schema_definition)
  local _, apply_err, deferred = config_facade.apply(config_facade.LAYERS.SETUP, user_opts, { defer_discover = true })
  if apply_err then
    log.warn("setup(): config validation: " .. apply_err)
  end

  -- Old config system remains primary during the transition.
  -- The new system validates and stores ops; the old system feeds consumers.
  config = vim.tbl_deep_extend("force", {}, plugin_config, user_opts)

  -- Store config in state module
  state.set_config(config)

  -- Hydrate preset definitions for fast lookup
  presets.refresh(config.presets)

  -- Configure logging based on user settings
  log.configure({
    enabled = state.get_config().logging.enabled,
    path = state.get_config().logging.path,
    level = state.get_config().logging.level,
  })

  -- Associate .chat files with the markdown treesitter parser
  vim.treesitter.language.register("markdown", { "chat" })

  log.info("setup(): Flemma starting...")

  -- Initialize secrets module with built-in resolvers
  secrets.setup()

  -- Initialize provider registry with built-in providers
  provider_registry.setup()

  -- If provider is a module path, validate and register it
  if loader.is_module_path(config.provider) then
    loader.assert_exists(config.provider)
    provider_registry.register(config.provider)
    -- Update config.provider to the registered name (from metadata.name)
    local mod = loader.load(config.provider)
    config.provider = mod.metadata.name
    state.set_config(config)
  end

  -- Resolve preset reference in model field (e.g., model = "$gemini-3-pro")
  local resolved_preset, preset_error = presets.resolve_default(config.model, user_opts.provider)
  if preset_error then
    vim.notify(preset_error, vim.log.levels.ERROR)
    return
  end
  if resolved_preset then
    config.provider = resolved_preset.provider
    config.model = resolved_preset.model
  end

  -- Initialize provider based on the merged config
  local current_config = state.get_config()
  if resolved_preset then
    -- Merge preset parameters on top of config parameters (same pattern as switch_provider)
    local merged_params =
      config_manager.merge_parameters(current_config.parameters, resolved_preset.provider, resolved_preset.parameters)
    core.initialize_provider(current_config.provider, current_config.model, merged_params)
  else
    core.initialize_provider(current_config.provider, current_config.model, current_config.parameters)
  end

  -- Set up filetype detection for .chat files
  vim.filetype.add({
    extension = {
      chat = "chat",
    },
    pattern = {
      [".*%.chat"] = "chat",
    },
  })

  -- Set up UI module
  ui.setup()

  -- Set up cursor engine
  cursor.setup()

  -- Set up user commands
  commands.setup()

  -- Set up keymaps
  keymaps.setup()

  -- Set up highlighting
  highlight.setup()

  -- Set up notifications
  notifications.setup()

  -- Set up chat filetype handling
  ui.setup_chat_filetype_autocmds()

  -- Initialize templating registry with built-in populators
  templating.setup()

  -- Initialize tool registry with built-in tools
  tools.setup()

  -- Initialize preprocessor with built-in rewriters and post-parse hook
  preprocessor.setup()

  -- Initialize personality registry with built-in personalities
  personalities.setup()

  -- Initialize tool approval presets (built-ins + user-defined)
  tools_presets.setup(config.tools and config.tools.presets)

  -- Initialize approval resolver chain from config
  tools_approval.setup()

  -- Register built-in sandbox backends and validate availability
  sandbox.setup()

  -- Set up experimental LSP if enabled
  if config.experimental and config.experimental.lsp then
    lsp.setup()
  end

  -- Replay deferred DISCOVER writes now that modules are registered.
  -- Failures are expected until tools/providers expose metadata.config_schema.
  if deferred then
    local failures = config_facade.apply_deferred(config_facade.LAYERS.SETUP, deferred)
    if failures then
      for _, msg in ipairs(failures) do
        log.debug("setup(): deferred config key not resolved: " .. msg)
      end
    end
  end

  -- Defer sandbox backend check until the user enters a .chat buffer.
  -- By that time, other plugins may have registered additional backends.
  if config.sandbox and config.sandbox.enabled then
    local sandbox_ok = sandbox.validate_backend()
    if not sandbox_ok then
      local backend_mode = config.sandbox.backend
      local augroup = vim.api.nvim_create_augroup("FlemmaSandbox", { clear = true })
      vim.api.nvim_create_autocmd("BufEnter", {
        group = augroup,
        pattern = "*.chat",
        once = true,
        callback = function()
          -- Re-check — a backend may have been registered since init
          local ok, err = sandbox.validate_backend()
          if not ok then
            if backend_mode == "required" then
              vim.notify(
                "Flemma: Tool execution is not sandboxed -- no compatible backend found. "
                  .. "Run :Flemma sandbox:status for details, or set sandbox.enabled = false to disable.",
                vim.log.levels.WARN
              )
            else
              -- "auto" mode: log quietly, don't bother the user
              log.warn("Sandbox: no compatible backend found, running unsandboxed. " .. (err or ""))
            end
          end
        end,
      })
    end
  end
end

---Get the current model name
---@return string|nil
function M.get_current_model_name()
  local current_config = state.get_config()
  if current_config and current_config.model then
    return current_config.model
  end
  return nil -- Or an empty string, depending on desired behavior for uninitialized model
end

---Get the current provider name
---@return string|nil
function M.get_current_provider_name()
  local current_config = state.get_config()
  if current_config and current_config.provider then
    return current_config.provider
  end
  return nil
end

return M
