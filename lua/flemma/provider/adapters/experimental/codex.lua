--- Codex provider for Flemma (ChatGPT subscription)
---
--- Implements the Codex backend API, which uses the OpenAI Responses API wire
--- format with ChatGPT subscription authentication. This is an experimental,
--- opt-in provider that requires the user to have logged in via `codex login`.
---
--- Metatable chain: codex -> openai_responses -> base
local base = require("flemma.provider.base")
local openai_responses = require("flemma.provider.openai_responses")
local secrets = require("flemma.secrets")

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

secrets.register("flemma.secrets.resolvers.chatgpt")

return M
