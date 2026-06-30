--- OpenAI provider for Flemma
--- Implements the OpenAI Responses API integration via the openai_responses
--- intermediate base. Overrides extension points for OpenAI-specific behavior:
--- phase labeling, reasoning configuration, and prompt caching.
---
--- Metatable chain: openai -> openai_responses -> base
local base = require("flemma.provider.base")
local openai_responses = require("flemma.provider.openai_responses")
local s = require("flemma.schema")

---@class flemma.provider.OpenAI : flemma.provider.OpenAIResponses
local M = {}

setmetatable(M, { __index = openai_responses })

local PHASE_DIAGNOSTIC_PATH = "openai.assistant_message_phases"

---@type flemma.provider.Metadata
M.metadata = {
  name = "openai",
  display_name = "OpenAI",
  models = { "flemma.models.openai" },
  capabilities = {
    supports_reasoning = true,
    supports_thinking_budget = false,
    outputs_thinking = true,
    output_has_thoughts = true,
  },
  config_schema = s.object({
    experimental = s.optional(s.object({
      phase = s.boolean(true),
    })),
    reasoning_summary = s.optional(s.string("auto")),
    reasoning = s.optional(s.string()),
  }),
}

---@param self flemma.provider.OpenAI
---@return boolean
local function phase_labeling_enabled(self)
  local experimental = self.parameters.experimental
  if type(experimental) ~= "table" then
    return true
  end
  return experimental.phase ~= false
end

---@param params flemma.provider.Parameters
---@return flemma.provider.OpenAI
function M.new(params)
  local self = setmetatable({
    parameters = params or {},
    state = {},
    endpoint = "https://api.openai.com/v1/responses",
  }, { __index = setmetatable(M, { __index = setmetatable(openai_responses, { __index = base }) }) })
  self:_new_response_buffer()
  return self --[[@as flemma.provider.OpenAI]]
end

---@param _self flemma.provider.OpenAI
---@return flemma.secrets.Credential
function M.get_credential(_self)
  return { kind = "api_key", service = "openai", description = "OpenAI API key" }
end

-- ============================================================================
-- Extension point overrides
-- ============================================================================

--- Initialize phase diagnostics tracking before build_request runs.
---@param self flemma.provider.OpenAI
function M._init_build(self)
  self:_diagnostics_start(phase_labeling_enabled(self))
end

--- System prompt and reasoning configuration are inherited from openai_responses.
--- No override needed — inherited _apply_system and _apply_reasoning work for OpenAI.

--- Add prompt caching configuration for OpenAI.
---@param self flemma.provider.OpenAI
---@param body table<string, any>
---@param context? flemma.Context
function M._apply_extra_body(self, body, context)
  local cache_retention = self.parameters.cache_retention or "short"
  if cache_retention ~= "none" then
    local filename = context and context:get_filename() or ""
    if filename ~= "" then
      body.prompt_cache_key = filename
    end
    body.prompt_cache_retention = cache_retention == "long" and "24h" or "in_memory"
  end
end

--- Decorate assistant message items with phase labels.
---@param self flemma.provider.OpenAI
---@param item table The assistant message item being built
---@param phase string The resolved phase ("commentary" or "final_answer")
function M._decorate_assistant_item(self, item, phase)
  if phase_labeling_enabled(self) then
    item.phase = phase
    self:_diagnostics_append("actual", PHASE_DIAGNOSTIC_PATH, phase)
  end
end

--- Record expected phase from output_item.done message events.
---@param self flemma.provider.OpenAI
---@param item table The completed output item
function M._on_output_message_done(self, item)
  if item.phase then
    self:_diagnostics_append("expected", PHASE_DIAGNOSTIC_PATH, item.phase)
  end
end

-- ============================================================================
-- Provider-specific methods
-- ============================================================================

---@param self flemma.provider.OpenAI
---@return string[]
function M.get_request_headers(self)
  local credential = self:resolve_credential()
  local api_key = credential and credential.value

  return {
    "Authorization: Bearer " .. api_key,
    "Content-Type: application/json",
  }
end

---Query OpenAI's `/v1/responses/input_tokens` endpoint and report the result
---via on_result. Caller owns formatting + notifying. Reuses the same request
---builder as Responses API sends, minus fields rejected by the token endpoint.
---@param bufnr integer
---@param on_result flemma.usage.EstimateCallback
function M.try_estimate_usage(bufnr, on_result)
  base.send_count_tokens({
    bufnr = bufnr,
    endpoint = "https://api.openai.com/v1/responses/input_tokens",
    transform_body = function(body)
      body.stream = nil
      body.store = nil
      body.max_output_tokens = nil
      body.temperature = nil
      body.include = nil
      body.prompt_cache_key = nil
      body.prompt_cache_retention = nil
      return body
    end,
    parse_response = function(parsed)
      return parsed.input_tokens
    end,
    cache_key_prefix = "openai",
    error_label = "OpenAI",
  }, on_result)
end

return M
