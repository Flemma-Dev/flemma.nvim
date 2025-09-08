--- State management for Flemma plugin
--- Centralizes all shared plugin state

local M = {}

-- Local state variables
local config = {}
local provider = nil
local session_usage = {
  input_tokens = 0,
  output_tokens = 0,
  thoughts_tokens = 0,
}

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

-- Session usage management
function M.get_session_usage()
  return session_usage
end

function M.update_session_usage(usage_data)
  if not usage_data then
    return
  end
  
  if usage_data.input_tokens then
    session_usage.input_tokens = session_usage.input_tokens + usage_data.input_tokens
  end
  
  if usage_data.output_tokens then
    session_usage.output_tokens = session_usage.output_tokens + usage_data.output_tokens
  end
  
  if usage_data.thoughts_tokens then
    session_usage.thoughts_tokens = session_usage.thoughts_tokens + usage_data.thoughts_tokens
  end
end

return M
