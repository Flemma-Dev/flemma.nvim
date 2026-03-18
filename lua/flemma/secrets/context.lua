---@class flemma.secrets.context
--- Per-resolver config context. Implements flemma.config.ConfigAware by reading
--- state.get_config().secrets[resolver_name] and returning a deep copy.
local M = {}

local state = require("flemma.state")

---@class flemma.secrets.Context : flemma.config.ConfigAware<table>
---@field diagnostic fun(self: flemma.secrets.Context, message: string)
---@field get_diagnostics fun(self: flemma.secrets.Context): flemma.secrets.ResolverDiagnostic[]

---@class flemma.secrets.ResolverDiagnostic
---@field resolver string
---@field message string

--- Build a new context for the given resolver name.
--- The resolver name must match the key used in the secrets config table.
--- Convention: resolver.name == config key (e.g. name "gcloud" → secrets.gcloud).
---@param resolver_name string
---@return flemma.secrets.Context
function M.new(resolver_name)
  local ctx = {}
  ---@type flemma.secrets.ResolverDiagnostic[]
  local diagnostics = {}

  ---@return table|nil
  function ctx:get_config()
    local cfg = state.get_config().secrets
    if not cfg then
      return nil
    end
    local subtree = cfg[resolver_name]
    if subtree == nil then
      return nil
    end
    return vim.deepcopy(subtree)
  end

  --- Record a diagnostic message explaining why this resolver could not help.
  ---@param message string
  function ctx:diagnostic(message)
    table.insert(diagnostics, { resolver = resolver_name, message = message })
  end

  --- Return all diagnostics recorded by this resolver. Always returns a table (possibly empty).
  ---@return flemma.secrets.ResolverDiagnostic[]
  function ctx:get_diagnostics()
    return diagnostics
  end

  return ctx
end

return M
