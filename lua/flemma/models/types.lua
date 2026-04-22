--- Shared type annotations for model data modules.
---
--- NOTE: Cost prediction & the invisible tool-use tax
---
--- Today Flemma reports costs *after* each response using the token counts the API
--- hands back. That works — but it means the user has no idea what a message will
--- cost until they've already sent it.
---
--- It turns out the APIs quietly inject a system prompt whenever you send tools.
--- Anthropic calls it the "tool use system prompt" and it can be significant — 346
--- tokens for Opus 4.6, 159 for Opus 4.0. You're billed for those tokens even
--- though they never appear in your messages. The API's `input_tokens` count
--- includes them, so our post-hoc cost tracking is accurate. But if we ever want
--- to *predict* the cost of a request before sending it — say, a little "~$0.12"
--- hint in the statusline as the user types — we'd need to account for this
--- invisible overhead ourselves.
---
--- LiteLLM's model database (model_prices_and_context_window.json) tracks these
--- values as `tool_use_system_prompt_tokens` per model. If we add cost prediction,
--- that's the missing piece: estimate token count from buffer content, add the
--- tool-use tax, multiply by the per-token price, and show it live. Something for
--- a rainy day.

---@class flemma.models.Types
local M = {}

---@class flemma.models.ThinkingBudgets
---@field minimal? integer Token budget for "minimal" effort level
---@field low? integer Token budget for "low" effort level
---@field medium? integer Token budget for "medium" effort level
---@field high? integer Token budget for "high" effort level

---@class flemma.models.Pricing
---@field input number USD per million input tokens
---@field output number USD per million output tokens
---@field cache_read? number USD per million cache-read tokens
---@field cache_write? number USD per million cache-write tokens

---@class flemma.models.ModelInfo
--- Pricing and cache constraints
---@field pricing flemma.models.Pricing
---@field min_cache_tokens? integer Minimum tokens for cache prefix to be accepted (informational)
--- Token limits
---@field max_input_tokens? integer Maximum context window size (input tokens)
---@field max_output_tokens? integer Maximum tokens the model can generate in a single response
---@field min_output_tokens? integer Minimum max_tokens the API accepts for this model
--- Thinking / reasoning
---@field thinking_budgets? flemma.models.ThinkingBudgets Per-model token budgets for each thinking level
---@field min_thinking_budget? integer Minimum thinking budget the API accepts
---@field max_thinking_budget? integer Maximum thinking budget the API accepts
---@field thinking_effort_map? table<string, string> Maps Flemma canonical levels to provider API values
--- Provider-specific extension point. Keys are documented by the owning adapter;
--- absence on a model means "not applicable." Mirrors the `meta` pattern used on
--- tool_result AST nodes for round-tripping unrecognized tokens.
---@field meta? table<string, any> Provider-specific metadata; see owning adapter for accepted keys

---@class flemma.models.ProviderModels
---@field default string Default model name for this provider
---@field models table<string, flemma.models.ModelInfo>

return M
