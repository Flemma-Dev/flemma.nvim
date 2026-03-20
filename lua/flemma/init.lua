--- Flemma plugin core functionality
--- Provides chat interface and API integration
---@class flemma.Plugin
local M = {}

local config_facade = require("flemma.config")
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

  -- Phase 1: Config foundation
  -- Schema defaults (L10) + user opts (L20). DISCOVER-backed keys
  -- (tool/provider/sandbox-specific config) are deferred until modules register.
  config_facade.init(schema_definition)
  local _, apply_err, deferred = config_facade.apply(config_facade.LAYERS.SETUP, user_opts, { defer_discover = true })
  if apply_err then
    log.warn("setup(): config validation: " .. apply_err)
  end

  -- Early materialize for consumers during module registration. DISCOVER
  -- defaults aren't in L10 yet — those arrive as each module registers.
  local config = config_facade.materialize()
  state.set_config(config)

  -- Hydrate preset definitions for fast lookup
  presets.refresh(config.presets)

  -- Configure logging based on user settings
  log.configure({
    enabled = config.logging.enabled,
    path = config.logging.path,
    level = config.logging.level,
  })

  -- Associate .chat files with the markdown treesitter parser
  vim.treesitter.language.register("markdown", { "chat" })

  log.info("setup(): Flemma starting...")

  -- Phase 2: Module registration (populates DISCOVER caches)
  -- These must run before the deferred apply so DISCOVER callbacks resolve.

  -- Initialize secrets module with built-in resolvers
  secrets.setup()

  -- Initialize provider registry with built-in providers
  provider_registry.setup()

  -- If provider is a module path, validate and register it
  if loader.is_module_path(config.provider) then
    loader.assert_exists(config.provider)
    provider_registry.register(config.provider)
    -- Write the resolved name to the SETUP layer so re-materialize picks it up.
    local mod = loader.load(config.provider)
    local w = config_facade.writer(nil, config_facade.LAYERS.SETUP)
    w.provider = mod.metadata.name
    config.provider = mod.metadata.name
  end

  -- Initialize tool registry with built-in tools
  tools.setup()

  -- Register built-in sandbox backends and validate availability
  sandbox.setup()

  -- Initialize tool approval presets before finalize so that the auto_approve
  -- coerce function can expand $preset references during the coerce pass.
  -- Read presets config from the store — L20 has the user's setup values.
  local presets_cfg = config_facade.get()
  tools_presets.setup(presets_cfg.tools and presets_cfg.tools.presets)

  -- Phase 3: Finalize — replay deferred DISCOVER writes + run coerce transforms
  -- Deferred user opts (e.g., parameters.vertex, tools.bash) now resolve.
  -- Coerce transforms re-run with populated ctx (preset expansion, etc.).
  local failures = config_facade.finalize(config_facade.LAYERS.SETUP, deferred)
  if failures then
    local paths = {}
    for _, f in ipairs(failures) do
      table.insert(paths, f.path)
    end
    vim.notify("Flemma: unknown config keys: " .. table.concat(paths, ", "), vim.log.levels.WARN)
  end

  -- Re-materialize with complete config: DISCOVER defaults, deferred user
  -- opts, and coerced values are now resolved. This is the authoritative
  -- config for provider init.
  config = config_facade.materialize()
  state.set_config(config)

  -- Phase 4: Provider initialization (needs complete config)

  -- Resolve preset reference in model field (e.g., model = "$gemini-3-pro")
  local resolved_preset, preset_error = presets.resolve_default(config.model, user_opts.provider)
  if preset_error then
    vim.notify(preset_error, vim.log.levels.ERROR)
    return
  end
  if resolved_preset then
    -- Write resolved preset values to the SETUP layer.
    local w = config_facade.writer(nil, config_facade.LAYERS.SETUP)
    w.provider = resolved_preset.provider
    w.model = resolved_preset.model
    config.provider = resolved_preset.provider
    config.model = resolved_preset.model
  end

  -- Initialize provider based on the resolved config. Pass SETUP layer so the
  -- validated provider/model go to the same layer as user opts (not RUNTIME).
  -- Only pass the preset's extra parameters as explicit overrides — the user's
  -- setup parameters are already in L20 from config_facade.apply() above.
  if resolved_preset then
    core.initialize_provider(
      resolved_preset.provider or config.provider,
      resolved_preset.model or config.model,
      resolved_preset.parameters or {},
      config_facade.LAYERS.SETUP
    )
  else
    core.initialize_provider(config.provider, config.model, {}, config_facade.LAYERS.SETUP)
  end

  -- Phase 5: Remaining setup

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

  -- Initialize preprocessor with built-in rewriters and post-parse hook
  preprocessor.setup()

  -- Initialize personality registry with built-in personalities
  personalities.setup()

  -- Initialize approval resolver chain from config
  -- (tools_presets.setup() already called before finalize in Phase 2)
  tools_approval.setup()

  -- Set up experimental LSP if enabled
  if config.experimental and config.experimental.lsp then
    lsp.setup()
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
