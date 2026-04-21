--- Optional devicons integration — registers a .chat file icon with whichever
--- devicons plugin the user has installed.
---
--- Auto-loaded during flemma.setup() when integrations.devicons.enabled is true.
--- Tries providers in order and stops at the first available one.
---@class flemma.integrations.Devicons
local M = {}

local log = require("flemma.logging")

---@class flemma.integrations.devicons.Opts
---@field icon string

---@alias flemma.integrations.devicons.RegisterFn fun(mod: table, opts: flemma.integrations.devicons.Opts)

---@class flemma.integrations.devicons.Provider
---@field module string
---@field register flemma.integrations.devicons.RegisterFn

---Register the .chat icon with nvim-web-devicons.
---@param mod table
---@param opts flemma.integrations.devicons.Opts
local function register_web_devicons(mod, opts)
  mod.set_icon({
    chat = {
      icon = opts.icon,
      name = "Chat",
    },
  })
end

---@type flemma.integrations.devicons.Provider[]
local PROVIDERS = {
  { module = "nvim-web-devicons", register = register_web_devicons },
}

---Register the .chat icon with the first available devicons provider.
---@param opts flemma.integrations.devicons.Opts
function M.setup(opts)
  for _, provider in ipairs(PROVIDERS) do
    local loaded, mod = pcall(require, provider.module)
    if loaded then
      local registered, err = pcall(provider.register, mod, opts)
      if not registered then
        log.warn("devicons: " .. provider.module .. " register failed: " .. tostring(err))
      else
        log.debug("devicons: registered via " .. provider.module)
      end
      return
    end
  end
end

return M
