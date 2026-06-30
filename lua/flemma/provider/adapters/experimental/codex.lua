--- Codex provider for Flemma (ChatGPT subscription)
---
--- Implements the Codex backend API, which uses the OpenAI Responses API wire
--- format with ChatGPT subscription authentication. This is an experimental,
--- opt-in provider that requires the user to have logged in via `codex login`.
---
--- Metatable chain: codex -> openai_responses -> base
local base = require("flemma.provider.base")
local bridge = require("flemma.bridge")
local http = require("flemma.utilities.http")
local json = require("flemma.utilities.json")
local openai_responses = require("flemma.provider.openai_responses")
local readiness = require("flemma.readiness")
local secrets = require("flemma.secrets")
local str = require("flemma.utilities.string")

---@class flemma.provider.Codex : flemma.provider.OpenAIResponses
local M = {}

setmetatable(M, { __index = openai_responses })

---@type flemma.provider.Metadata
M.metadata = {
  name = "codex",
  display_name = "Codex (ChatGPT)",
  billing = "subscription",
  models = { "flemma.models.codex" },
  capabilities = {
    supports_reasoning = true,
    supports_thinking_budget = false,
    outputs_thinking = true,
    output_has_thoughts = true,
  },
}

---@param params flemma.provider.Parameters
---@return flemma.provider.Codex
function M.new(params)
  local self = setmetatable({
    parameters = params or {},
    state = {},
    endpoint = "https://chatgpt.com/backend-api/codex/responses",
  }, { __index = setmetatable(M, { __index = setmetatable(openai_responses, { __index = base }) }) })
  self:_new_response_buffer()
  return self --[[@as flemma.provider.Codex]]
end

---@param _self flemma.provider.Codex
---@return flemma.secrets.Credential
function M.get_credential(_self)
  return { kind = "chatgpt_subscription", service = "codex", description = "ChatGPT subscription token" }
end

-- ============================================================================
-- Extension point overrides
-- ============================================================================

--- Place system prompt in the top-level `instructions` field.
---@param _self flemma.provider.Codex
---@param body table<string, any>
---@param _input_items table[]
---@param system_text string
function M._apply_system(_self, body, _input_items, system_text)
  body.instructions = system_text
end

--- Reasoning configuration is inherited from openai_responses._apply_reasoning.

--- Add Codex-specific body fields and remove unsupported parameters.
--- The ChatGPT backend does not accept max_output_tokens or temperature
--- as top-level fields (they are server-controlled).
---@param _self flemma.provider.Codex
---@param body table<string, any>
---@param _context? flemma.Context
function M._apply_extra_body(_self, body, _context)
  body.max_output_tokens = nil
  body.temperature = nil
  body.text = { verbosity = "low" }
  body.include = { "reasoning.encrypted_content" }
  body.parallel_tool_calls = true
end

-- ============================================================================
-- Provider-specific methods
-- ============================================================================

---@param self flemma.provider.Codex
---@return string[]|nil
function M.get_request_headers(self)
  local credential = self:resolve_credential()
  if not credential then
    return nil
  end

  local headers = {
    "Authorization: Bearer " .. credential.value,
    "Content-Type: application/json",
    "accept: text/event-stream",
    "OpenAI-Beta: responses=experimental",
    "originator: flemma",
  }

  if credential.metadata and credential.metadata.account_id then
    table.insert(headers, "chatgpt-account-id: " .. credential.metadata.account_id)
  end

  return headers
end

--- Detect authentication errors from the Codex backend.
---@param _self flemma.provider.Codex
---@param message string|nil
---@return boolean
function M.is_auth_error(_self, message)
  if not message or type(message) ~= "string" then
    return false
  end
  local lower = message:lower()
  if lower:match("unauthorized") or lower:match("authentication") or lower:match("unauthenticated") then
    return true
  end
  if lower:match("invalid token") or lower:match("token expired") then
    return true
  end
  return false
end

-- ============================================================================
-- Usage estimation
-- ============================================================================

--- Estimate input tokens locally without an API call.
---
--- The ChatGPT backend has no count_tokens / input_tokens endpoint — the
--- Platform API equivalent (api.openai.com/v1/responses/input_tokens) requires
--- an API key, not a subscription OAuth token.
---
--- Both OpenAI's own Codex CLI (Rust, truncate.rs) and Pi (TypeScript,
--- compaction.ts) handle this the same way: divide the serialised payload
--- size by 4.  Codex uses byte length, Pi uses character length — for the
--- UTF-8 / ASCII mix in a typical prompt they converge.  Neither ships a
--- local tokenizer.  ¯\_(ツ)_/¯
---
--- After the first real response the prefetch layer seeds from the server's
--- actual usage.input_tokens, so the heuristic only covers the gap before
--- the first round-trip and between edits.
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
  ---@cast provider flemma.provider.Base

  local build_ok, body = pcall(provider.build_request, provider, prompt, context)
  if not build_ok then
    if readiness.is_suspense(body) then
      error(body)
    end
    on_result({ err = "Build request failed: " .. tostring(body) })
    return
  end

  local encode_ok, payload = pcall(json.encode, body)
  if not encode_ok or not payload then
    on_result({ err = "JSON encode failed" })
    return
  end

  local tokens = math.ceil(#payload / 4)
  local model = provider.parameters.model

  on_result({
    response = {
      tokens = tokens,
      cache_key = "codex:" .. model,
      model = model,
    },
  })
end

-- ============================================================================
-- Rate limit snapshot extraction
-- ============================================================================

local HEADER_PREFIX = "x-codex-"

---@param headers table<string, string[]>
---@param tier string "primary" or "secondary"
---@return flemma.session.RateLimitWindow|nil
local function parse_window(headers, tier)
  local used_percent = http.read_header_number(headers, HEADER_PREFIX .. tier .. "-used-percent")
  if not used_percent then
    return nil
  end
  local window_minutes = http.read_header_number(headers, HEADER_PREFIX .. tier .. "-window-minutes")
  local resets_at = http.read_header_number(headers, HEADER_PREFIX .. tier .. "-reset-at")
  return {
    used_percent = used_percent,
    window_seconds = window_minutes and (window_minutes * 60) or 0,
    resets_at = resets_at,
  }
end

---@param self flemma.provider.Codex
---@return flemma.session.RateLimitSnapshot|nil
function M.get_rate_limit_snapshot(self)
  if not self._response_headers then
    return nil
  end

  local primary = parse_window(self._response_headers, "primary")
  if not primary then
    return nil
  end

  local windows = { primary }
  local secondary = parse_window(self._response_headers, "secondary")
  if secondary then
    table.insert(windows, secondary)
  end

  local plan_raw = http.read_header(self._response_headers, HEADER_PREFIX .. "plan-type")
  return {
    plan_name = plan_raw and str.title(plan_raw) or nil,
    windows = windows,
  }
end

secrets.register("flemma.secrets.resolvers.chatgpt")

return M
