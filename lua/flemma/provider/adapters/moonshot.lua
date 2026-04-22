--- Moonshot AI (Kimi) provider for Flemma
---
--- Implements the Moonshot Chat Completions API integration for Kimi models.
--- Inherits from the OpenAI Chat Completions intermediate base, overriding
--- extension points for Moonshot-specific thinking behavior and parameters.
---
--- Metatable chain: moonshot -> openai_chat -> base
local base = require("flemma.provider.base")
local bridge = require("flemma.bridge")
local client = require("flemma.client")
local json = require("flemma.utilities.json")
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

-- Per-model thinking behaviour is declared in `lua/flemma/models/moonshot.lua`
-- via `meta.thinking_mode`. Accepted values:
--   "forced"   — thinking is always on (kimi-k2-thinking, kimi-k2-thinking-turbo);
--                request always sends `thinking.type = "enabled"` and locks
--                temperature to 1.0 regardless of user configuration.
--   "optional" — thinking can be toggled (kimi-k2.6, kimi-k2.5); request sends
--                `thinking.type = "enabled"|"disabled"` based on the user's
--                resolved thinking state, with temperature locked accordingly
--                (1.0 when enabled, 0.6 when disabled).
--   nil        — no thinking support (moonshot-v1-*, kimi-k2 preview/turbo);
--                no `thinking` parameter is sent.

---@param model_name string
---@return "forced"|"optional"|nil
local function get_thinking_mode(model_name)
  local info = provider_registry.get_model_info("moonshot", model_name)
  if info and info.meta then
    return info.meta.thinking_mode
  end
  return nil
end

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
--- Behaviour is driven by `meta.thinking_mode` on the model info — see the
--- comment on `get_thinking_mode` above for the value semantics.
---@param self flemma.provider.Moonshot
---@param body table<string, any> The request body (mutated in place)
---@param resolution flemma.provider.ThinkingResolution The resolved thinking configuration
function M._apply_thinking(self, body, resolution)
  local model = self.parameters.model
  local mode = get_thinking_mode(model)

  if mode == "forced" then
    body.thinking = { type = "enabled" }
    body.temperature = 1.0
    log.debug("moonshot._apply_thinking: Forced thinking on for " .. model .. ", temperature locked to 1.0")
    return
  end

  if mode == "optional" then
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

  -- No thinking support (moonshot-v1-*, kimi-k2 preview/turbo): leave body alone
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
--- Warns about fixed sampling parameters that the API will override on
--- thinking-toggle models (K2.6, K2.5).
---@param model_name string The model name
---@param parameters table<string, any> The parameters to validate
---@return boolean success Always true (warnings don't fail validation)
---@return string[]|nil warnings Human-readable warning strings, or nil when clean
function M.validate_parameters(model_name, parameters)
  if get_thinking_mode(model_name) ~= "optional" then
    return true
  end

  -- Determine thinking state for validation messages
  local model_info = provider_registry.get_model_info("moonshot", model_name)
  local thinking = normalize.resolve_thinking(parameters, M.metadata.capabilities, model_info)
  local expected_temperature = thinking.enabled and 1.0 or 0.6

  -- Only warn about parameters the user has explicitly set to a value that
  -- conflicts with the enforced fixed value. Parameters that are nil (not set
  -- by the user) are not considered intentional conflicts.
  local warnings = {}

  ---@param value any The flattened parameter value
  ---@param fixed any The enforced value for thinking-toggle models
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

-- ============================================================================
-- Token estimation
-- ============================================================================

---Query Moonshot's `/v1/tokenizers/estimate-token-count` endpoint and report
---the result via on_result. Caller owns formatting + notifying. Reuses the
---full `build_request` pipeline, minus fields irrelevant to counting.
---@param bufnr integer
---@param on_result flemma.usage.EstimateCallback
function M.try_estimate_usage(bufnr, on_result)
  local prompt, context, provider, _evaluated, failure = bridge.build_prompt_and_provider(bufnr)
  if failure then
    on_result({ err = failure.message })
    return
  end
  ---@cast prompt flemma.pipeline.Prompt
  ---@cast context flemma.Context
  ---@cast provider flemma.provider.Moonshot

  local endpoint = "https://api.moonshot.ai/v1/tokenizers/estimate-token-count"
  local fixture_path = client.find_fixture_for_endpoint(endpoint)

  local headers
  if fixture_path then
    headers = { "content-type: application/json" }
  else
    local api_key, api_key_diagnostics = provider:get_api_key()
    if not api_key then
      local msg = "No API key available for Moonshot."
      if api_key_diagnostics then
        for _, d in ipairs(api_key_diagnostics) do
          msg = msg .. "\n  [" .. d.resolver .. "] " .. d.message
        end
      end
      on_result({ err = msg })
      return
    end
    headers = provider:get_request_headers()
  end

  local build_ok, body = pcall(provider.build_request, provider, prompt, context)
  if not build_ok then
    on_result({ err = tostring(body) })
    return
  end

  -- Count endpoint takes the chat-completions shape but these fields are
  -- irrelevant to tokenization; strip them to keep the payload minimal.
  body.stream = nil
  body.stream_options = nil
  body.max_tokens = nil
  body.max_completion_tokens = nil
  body.temperature = nil
  body.thinking = nil

  local request_opts = {
    endpoint = endpoint,
    headers = headers,
    request_body = body,
    parameters = provider.parameters,
    trailing_keys = provider:get_trailing_keys(),
  }

  client.send_json_request(request_opts, function(response_body, exit_code, curl_err)
    if curl_err or exit_code ~= 0 or not response_body or response_body == "" then
      local reason = curl_err or ("curl exit code " .. tostring(exit_code))
      on_result({ err = reason })
      return
    end

    local parse_ok, parsed = pcall(json.decode, response_body)
    if not parse_ok or type(parsed) ~= "table" then
      on_result({ err = "could not parse response" })
      return
    end

    -- Moonshot's error shape is not uniform:
    --   auth errors    → {error: {message, type}}                            (object)
    --   validation     → {code, error: "...", message: "非法输入", ...}     (string)
    -- Base's extract_json_response_error handles both (Pattern 1 for the
    -- object form with `error.type` prefix, Pattern 2 for the string form).
    if parsed.error ~= nil then
      on_result({ err = provider:extract_json_response_error(parsed) or "unknown Moonshot error" })
      return
    end

    if type(parsed.data) ~= "table" or type(parsed.data.total_tokens) ~= "number" then
      on_result({ err = "missing data.total_tokens in response" })
      return
    end

    local model = provider.parameters.model
    on_result({
      response = {
        tokens = parsed.data.total_tokens,
        cache_key = "moonshot:" .. model,
        model = model,
      },
    })
  end)
end

return M
