--- Moonshot AI (Kimi) provider for Flemma
---
--- Implements the Moonshot Chat Completions API integration for Kimi models.
--- Inherits from the OpenAI Chat Completions intermediate base, overriding
--- extension points for Moonshot-specific thinking behavior and parameters.
---
--- Metatable chain: moonshot -> openai_chat -> base
local base = require("flemma.provider.base")
local log = require("flemma.logging")
local normalize = require("flemma.provider.normalize")
local openai_chat = require("flemma.provider.openai_chat")
local provider_registry = require("flemma.provider.registry")
local s = require("flemma.schema")
local sink = require("flemma.sink")

---@class flemma.provider.Moonshot : flemma.provider.OpenAIChat
local M = {}

-- Inherit from openai_chat provider
setmetatable(M, { __index = openai_chat })

-- Models where thinking is forced on regardless of user configuration
---@type table<string, boolean>
local FORCED_THINKING_MODELS = {
  ["kimi-k2-thinking"] = true,
  ["kimi-k2-thinking-turbo"] = true,
}

-- Models that support optional thinking (can be enabled or disabled)
---@type table<string, boolean>
local THINKING_CAPABLE_MODELS = {
  ["kimi-k2.5"] = true,
}

---@type flemma.provider.Metadata
M.metadata = {
  name = "moonshot",
  display_name = "Moonshot AI",
  models = { "flemma.models.moonshot" },
  capabilities = {
    supports_reasoning = false,
    supports_thinking_budget = true,
    outputs_thinking = true,
    output_has_thoughts = false,
  },
  config_schema = s.object({
    prompt_cache_key = s.optional(s.string()),
  }),
}

---@param params flemma.provider.Parameters
---@return flemma.provider.Moonshot
function M.new(params)
  local self = setmetatable({
    parameters = params or {},
    state = {},
    endpoint = "https://api.moonshot.ai/v1/chat/completions",
  }, { __index = setmetatable(M, { __index = setmetatable(openai_chat, { __index = base }) }) })
  self:_new_response_buffer()
  self._response_buffer.extra.tool_calls = {}
  self._response_buffer.extra.thinking_sink = sink.create({ name = "moonshot/thinking" })
  self._response_buffer.extra.usage_emitted = false
  return self --[[@as flemma.provider.Moonshot]]
end

---@param _self flemma.provider.Moonshot
---@return flemma.secrets.Credential
function M.get_credential(_self)
  return { kind = "api_key", service = "moonshot", description = "Moonshot API key" }
end

---@param self flemma.provider.Moonshot
---@return string[]|nil
function M.get_request_headers(self)
  local api_key = self:get_api_key()

  return {
    "Authorization: Bearer " .. api_key,
    "Content-Type: application/json",
  }
end

-- ============================================================================
-- Extension point overrides
-- ============================================================================

--- Return the provider prefix for thinking block signatures.
--- Moonshot thinking blocks use "moonshot" as the provider prefix.
---@param _self flemma.provider.Moonshot
---@return string
function M._thinking_provider_prefix(_self)
  return "moonshot"
end

--- Apply Moonshot-specific thinking configuration to the request body.
---
--- Thinking behavior is model-dependent:
--- - kimi-k2-thinking / kimi-k2-thinking-turbo: Thinking is FORCED ON.
---   Always sets body.thinking = {type = "enabled"} and locks temperature to 1.0.
--- - kimi-k2.5 with thinking enabled: Sets body.thinking = {type = "enabled"}
---   and locks temperature to 1.0.
--- - kimi-k2.5 with thinking disabled: Sets body.thinking = {type = "disabled"}
---   and locks temperature to 0.6.
--- - Other models (moonshot-v1-*): No thinking parameter.
---@param self flemma.provider.Moonshot
---@param body table<string, any> The request body (mutated in place)
---@param resolution flemma.provider.ThinkingResolution The resolved thinking configuration
function M._apply_thinking(self, body, resolution)
  local model = self.parameters.model

  -- Models where thinking is forced on regardless of user configuration
  if FORCED_THINKING_MODELS[model] then
    body.thinking = { type = "enabled" }
    body.temperature = 1.0
    log.debug("moonshot._apply_thinking: Forced thinking on for " .. model .. ", temperature locked to 1.0")
    return
  end

  -- Models that support optional thinking (kimi-k2.5)
  if THINKING_CAPABLE_MODELS[model] then
    if resolution.enabled then
      body.thinking = { type = "enabled" }
      body.temperature = 1.0
      log.debug("moonshot._apply_thinking: Thinking enabled for " .. model .. ", temperature locked to 1.0")
    else
      body.thinking = { type = "disabled" }
      body.temperature = 0.6
      log.debug("moonshot._apply_thinking: Thinking disabled for " .. model .. ", temperature locked to 0.6")
    end
    return
  end

  -- Other models (moonshot-v1-*): no thinking support, don't modify body
  log.debug("moonshot._apply_thinking: Model " .. model .. " does not support thinking, skipping")
end

--- Apply additional provider-specific parameters to the request body.
--- Adds prompt_cache_key from provider parameters if present.
---@param self flemma.provider.Moonshot
---@param body table<string, any> The request body (mutated in place)
---@param _context? flemma.Context The shared context object
function M._apply_provider_params(self, body, _context)
  if self.parameters.prompt_cache_key then
    body.prompt_cache_key = self.parameters.prompt_cache_key
    log.debug("moonshot._apply_provider_params: Added prompt_cache_key: " .. self.parameters.prompt_cache_key)
  end
end

-- ============================================================================
-- Context overflow detection
-- ============================================================================

--- Detect whether an error message indicates a context window overflow.
--- Adds Moonshot-specific patterns on top of the base patterns.
---@param self flemma.provider.Moonshot
---@param message string|nil The error message to check
---@return boolean
function M:is_context_overflow(message)
  -- Check base patterns first
  if base.is_context_overflow(self, message) then
    return true
  end

  if not message or type(message) ~= "string" then
    return false
  end
  local lower = message:lower()

  if lower:match("input token length too long") then
    return true
  end
  if lower:match("your request exceeded model token limit") then
    return true
  end

  return false
end

-- ============================================================================
-- Parameter validation
-- ============================================================================

--- Validate Moonshot-specific parameters.
--- Warns about kimi-k2.5 fixed parameters that the API will override.
---@param model_name string The model name
---@param parameters table<string, any> The parameters to validate
---@return boolean success Always true (warnings don't fail validation)
---@return string[]|nil warnings Human-readable warning strings, or nil when clean
function M.validate_parameters(model_name, parameters)
  if not THINKING_CAPABLE_MODELS[model_name] then
    return true
  end

  -- Determine thinking state for validation messages
  local model_info = provider_registry.get_model_info("moonshot", model_name)
  local thinking = normalize.resolve_thinking(parameters, M.metadata.capabilities, model_info)
  local expected_temperature = thinking.enabled and 1.0 or 0.6

  -- Only warn about parameters the user has explicitly set to a value that
  -- differs from the kimi-k2.5 fixed value. Parameters that are nil (not set
  -- by the user) are not considered intentional conflicts.
  local warnings = {}

  ---@param value any The flattened parameter value
  ---@param fixed any The kimi-k2.5 enforced value
  ---@param default any The Flemma schema default value
  ---@return boolean intentional True when the user has explicitly set a conflicting value
  local function is_intentional_conflict(value, fixed, default)
    return value ~= nil and value ~= fixed and value ~= default
  end

  if is_intentional_conflict(parameters.temperature, expected_temperature, nil) then
    table.insert(
      warnings,
      string.format(
        "temperature will be locked to %.1f (%s thinking)",
        expected_temperature,
        thinking.enabled and "with" or "without"
      )
    )
  end

  if is_intentional_conflict(parameters.top_p, 0.95, 1.0) then
    table.insert(warnings, "top_p will be fixed to 0.95")
  end

  if parameters.n ~= nil and parameters.n ~= 1 then
    table.insert(warnings, "n will be fixed to 1")
  end

  if is_intentional_conflict(parameters.presence_penalty, 0.0, nil) then
    table.insert(warnings, "presence_penalty will be fixed to 0.0")
  end

  if is_intentional_conflict(parameters.frequency_penalty, 0.0, nil) then
    table.insert(warnings, "frequency_penalty will be fixed to 0.0")
  end

  if #warnings > 0 then
    return true, warnings
  end
  return true
end

return M
