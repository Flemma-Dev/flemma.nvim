---@class flemma.secrets.context
--- Per-resolver config context. Implements flemma.config.ConfigAware by reading
--- state.get_config().secrets[resolver_name] and returning a deep copy.
local M = {}

local state = require("flemma.state")

---@class flemma.secrets.Context : flemma.config.ConfigAware<table>

--- Build a new context for the given resolver name.
--- The resolver name must match the key used in the secrets config table.
--- Convention: resolver.name == config key (e.g. name "gcloud" → secrets.gcloud).
---@param resolver_name string
---@return flemma.secrets.Context
function M.new(resolver_name)
  local ctx = {}

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

  return ctx
end

return M
