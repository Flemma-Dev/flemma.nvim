--- Moonshot AI model definitions.
--- Moonshot uses automatic caching with no separate write fee.
--- The API reports `cached_tokens` (hit count) but never `cache_creation` tokens,
--- so `cache_write` is intentionally omitted from pricing. Verified against live API
--- responses (2026-03-26): usage contains `cached_tokens` + `prompt_tokens_details.cached_tokens`
--- but no cache creation/write fields.
---
--- `max_output_tokens` is an estimate on the K2 family. Moonshot publishes only a
--- context window (`GET /v1/models` exposes `context_length` and nothing else), and
--- third-party figures disagree — 32,768 (the documented default cap), 131,072, and
--- 262,144 all circulate. 65,536 is a conservative middle that keeps the default
--- "50%" max_tokens at the documented 32,768 cap. K3's 131,072 is the documented
--- `max_completion_tokens` default.
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
    -- Temperature is fixed at 1.0 (as on kimi-k2.7-code); any other value errors.
    ["kimi-k3"] = {
      pricing = { input = 3.00, output = 15.00, cache_read = 0.30 },
      max_input_tokens = 1048576,
      max_output_tokens = 131072,
      min_output_tokens = 16000,
      meta = { thinking_mode = "effort" },
      thinking_effort_map = { minimal = "low", low = "low", medium = "high", high = "high", max = "max" },
    },

    -- Kimi K2.7 Code (256K context) — coding-focused flagship. Thinking is always
    -- on and cannot be disabled: `thinking.type = "disabled"` errors, and the only
    -- explicitly accepted form is `{"type":"enabled","keep":"all"}`. Temperature is
    -- fixed at 1.0. Hence "forced", not "optional" — see the adapter for the wire form.
    ["kimi-k2.7-code"] = {
      pricing = { input = 0.95, output = 4.00, cache_read = 0.19 },
      max_input_tokens = 262144,
      max_output_tokens = 65536,
      min_output_tokens = 16000,
      meta = { thinking_mode = "forced" },
    },

    -- Kimi K2.7 Code HighSpeed — the same model as kimi-k2.7-code with identical
    -- parameter constraints, differing only in output speed and price.
    ["kimi-k2.7-code-highspeed"] = {
      pricing = { input = 1.90, output = 8.00, cache_read = 0.38 },
      max_input_tokens = 262144,
      max_output_tokens = 65536,
      min_output_tokens = 16000,
      meta = { thinking_mode = "forced" },
    },

    -- Kimi K2.6 (256K context, thinking toggle)
    ["kimi-k2.6"] = {
      pricing = { input = 0.95, output = 4.00, cache_read = 0.16 },
      max_input_tokens = 262144,
      max_output_tokens = 65536,
      min_output_tokens = 16000,
      meta = { thinking_mode = "optional" },
    },

    -- Kimi K2.5 (256K context) — closed to newly registered accounts since the K3
    -- launch and covered by the same August 31, 2026 platform sunset as moonshot-v1.
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
