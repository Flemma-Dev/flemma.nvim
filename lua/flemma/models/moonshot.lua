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

    -- Kimi K2 thinking models (256K context, thinking forced on)
    -- K2 series retiring May 25, 2026.
    ["kimi-k2-thinking"] = {
      pricing = { input = 0.60, output = 2.50, cache_read = 0.15 },
      max_input_tokens = 262144,
      max_output_tokens = 65536,
      min_output_tokens = 16000,
      meta = { thinking_mode = "forced" },
    },
    ["kimi-k2-thinking-turbo"] = {
      pricing = { input = 1.15, output = 8.00, cache_read = 0.15 },
      max_input_tokens = 262144,
      max_output_tokens = 65536,
      min_output_tokens = 16000,
      meta = { thinking_mode = "forced" },
    },

    -- Kimi K2 generation models (no thinking)
    -- K2 series retiring May 25, 2026.
    ["kimi-k2-0905-preview"] = {
      pricing = { input = 0.60, output = 2.50, cache_read = 0.15 },
      max_input_tokens = 262144,
      max_output_tokens = 65536,
    },
    ["kimi-k2-0711-preview"] = {
      pricing = { input = 0.60, output = 2.50, cache_read = 0.15 },
      max_input_tokens = 131072,
      max_output_tokens = 65536,
    },
    ["kimi-k2-turbo-preview"] = {
      pricing = { input = 1.15, output = 8.00, cache_read = 0.15 },
      max_input_tokens = 262144,
      max_output_tokens = 65536,
    },

    -- Moonshot V1 text models (legacy, shared context window)
    ["moonshot-v1-8k"] = {
      pricing = { input = 0.20, output = 2.00 },
      max_input_tokens = 8192,
      max_output_tokens = 8192,
    },
    ["moonshot-v1-32k"] = {
      pricing = { input = 1.00, output = 3.00 },
      max_input_tokens = 32768,
      max_output_tokens = 32768,
    },
    ["moonshot-v1-128k"] = {
      pricing = { input = 2.00, output = 5.00 },
      max_input_tokens = 131072,
      max_output_tokens = 131072,
    },

    -- Moonshot V1 vision models (legacy)
    ["moonshot-v1-8k-vision-preview"] = {
      pricing = { input = 0.20, output = 2.00 },
      max_input_tokens = 8192,
      max_output_tokens = 8192,
    },
    ["moonshot-v1-32k-vision-preview"] = {
      pricing = { input = 1.00, output = 3.00 },
      max_input_tokens = 32768,
      max_output_tokens = 32768,
    },
    ["moonshot-v1-128k-vision-preview"] = {
      pricing = { input = 2.00, output = 5.00 },
      max_input_tokens = 131072,
      max_output_tokens = 131072,
    },
  },
}
