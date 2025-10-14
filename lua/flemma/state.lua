--- State management for Flemma plugin
--- Centralizes all shared plugin state

local M = {}
local session_module = require("flemma.session")

-- Local state variables
local config = {}
local provider = nil
local session = session_module.Session.new()

-- Configuration management
function M.set_config(conf)
  config = conf or {}
end

function M.get_config()
  return config
end

-- Provider management
function M.set_provider(p)
  provider = p
end

function M.get_provider()
  return provider
end

-- Session management
function M.get_session()
  return session
end

function M.reset_session()
  session = session_module.Session.new()
end

return M
