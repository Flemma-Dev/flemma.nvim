--- Moonshot AI model definitions.
--- Moonshot uses automatic caching with no separate write fee.
--- The API reports `cached_tokens` (hit count) but never `cache_creation` tokens,
--- so `cache_write` is intentionally omitted from pricing. Verified against live API
--- responses (2026-03-26): usage contains `cached_tokens` + `prompt_tokens_details.cached_tokens`
--- but no cache creation/write fields.
--- @see flemma.models.Types for type annotations

---@type flemma.models.ProviderModels
return {
  default = "kimi-k2.6",
  -- Moonshot uses automatic caching with no separate write fee.
  -- The API reports `cached_tokens` (hit count) but never `cache_creation` tokens,
  -- so `cache_write` is intentionally omitted from pricing. Verified against live API
  -- responses (2026-03-26): usage contains `cached_tokens` + `prompt_tokens_details.cached_tokens`
  -- but no cache creation/write fields.
  models = {
    -- Kimi K3 (1M context) — flagship. Always reasons; depth is configured through the
    -- top-level `reasoning_effort` field, not the `thinking` object the K2 family uses.
    -- The API accepts only `low`/`high`/`max` (default `max`), so `medium` clamps up to
    -- `high` and `minimal` down to `low` — matching Moonshot's own effort aliases, which
    -- fold `medium` into `high` and `minimum`/`light` into `low`. The clamp matters:
    -- /v1/chat/completions answers 200 to an effort it does not accept rather than
    -- rejecting it, so a stray `medium` would silently reason at some other depth.
    -- `GET /v1/models` publishes the accepted set as `reasoning_efforts`.
    ["kimi-k3"] = {
      pricing = { input = 3.00, output = 15.00, cache_read = 0.30 },
      max_input_tokens = 1048576,
      max_output_tokens = 131072,
      min_output_tokens = 16000,
      meta = { thinking_mode = "effort" },
      thinking_effort_map = { minimal = "low", low = "low", medium = "high", high = "high", max = "max" },
    },

    -- Kimi K2.7 Code (256K context, thinking toggle) — coding-focused flagship
    ["kimi-k2.7-code"] = {
      pricing = { input = 0.95, output = 4.00, cache_read = 0.19 },
      max_input_tokens = 262144,
      max_output_tokens = 65536,
      min_output_tokens = 16000,
      meta = { thinking_mode = "optional" },
    },

    -- Kimi K2.7 Code HighSpeed (256K context, thinking toggle) — faster, higher-priced tier
    ["kimi-k2.7-code-highspeed"] = {
      pricing = { input = 1.90, output = 8.00, cache_read = 0.38 },
      max_input_tokens = 262144,
      max_output_tokens = 65536,
      min_output_tokens = 16000,
      meta = { thinking_mode = "optional" },
    },

    -- Kimi K2.6 (256K context, thinking toggle)
    ["kimi-k2.6"] = {
      pricing = { input = 0.95, output = 4.00, cache_read = 0.16 },
      max_input_tokens = 262144,
      max_output_tokens = 65536,
      min_output_tokens = 16000,
      meta = { thinking_mode = "optional" },
    },

    -- Kimi K2.5 (256K context)
    ["kimi-k2.5"] = {
      pricing = { input = 0.60, output = 3.00, cache_read = 0.10 },
      max_input_tokens = 262144,
      max_output_tokens = 65536,
      min_output_tokens = 16000,
      meta = { thinking_mode = "optional" },
    },

    -- Moonshot V1 text models (legacy, shared context window)
    -- Platform sunset expected August 31, 2026 — see the Kimi chat pricing index.
    ["moonshot-v1-8k"] = {
      pricing = { input = 0.20, output = 2.00, cache_read = 0.20 },
      max_input_tokens = 8192,
      max_output_tokens = 8192,
    },
    ["moonshot-v1-32k"] = {
      pricing = { input = 1.00, output = 3.00, cache_read = 1.00 },
      max_input_tokens = 32768,
      max_output_tokens = 32768,
    },
    ["moonshot-v1-128k"] = {
      pricing = { input = 2.00, output = 5.00, cache_read = 2.00 },
      max_input_tokens = 131072,
      max_output_tokens = 131072,
    },
  },
}
