--- Anthropic Claude model definitions.
--- @see flemma.models.Types for type annotations

---@type flemma.models.ProviderModels
return {
  default = "claude-sonnet-4-6",
  models = {
    -- Claude Opus 4.8 — adaptive thinking only (manual budget_tokens is rejected with 400)
    ["claude-opus-4-8"] = {
      pricing = {
        input = 5.0,
        output = 25.0,
        cache_read = 0.50,
        cache_write = 6.25,
      },
      max_input_tokens = 1000000,
      max_output_tokens = 128000,
      thinking_budgets = { minimal = 1024, low = 2048, medium = 8192, high = 16384 },
      min_thinking_budget = 1024,
      min_cache_tokens = 2048,
      meta = { adaptive_thinking = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "max" },
    },

    -- Claude Opus 4.7 — adaptive thinking only (manual budget_tokens is rejected with 400)
    ["claude-opus-4-7"] = {
      pricing = {
        input = 5.0,
        output = 25.0,
        cache_read = 0.50,
        cache_write = 6.25,
      },
      max_input_tokens = 1000000,
      max_output_tokens = 128000,
      thinking_budgets = { minimal = 1024, low = 2048, medium = 8192, high = 16384 },
      min_thinking_budget = 1024,
      min_cache_tokens = 2048,
      meta = { adaptive_thinking = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "max" },
    },

    -- Claude Opus 4.6
    ["claude-opus-4-6"] = {
      pricing = {
        input = 5.0,
        output = 25.0,
        cache_read = 0.50,
        cache_write = 6.25,
      },
      max_input_tokens = 1000000,
      max_output_tokens = 128000,
      thinking_budgets = { minimal = 1024, low = 2048, medium = 8192, high = 16384 },
      min_thinking_budget = 1024,
      min_cache_tokens = 2048,
      meta = { adaptive_thinking = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "max" },
    },

    -- Claude Sonnet 5 — adaptive thinking; standard $3/$15 per MTok (intro $2/$10 through 2026-08-31)
    ["claude-sonnet-5"] = {
      pricing = {
        input = 3.0,
        output = 15.0,
        cache_read = 0.30,
        cache_write = 3.75,
      },
      max_input_tokens = 1000000,
      max_output_tokens = 128000,
      thinking_budgets = { minimal = 1024, low = 2048, medium = 8192, high = 16384 },
      min_thinking_budget = 1024,
      min_cache_tokens = 2048,
      meta = { adaptive_thinking = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "high" },
    },

    -- Claude Sonnet 4.6
    ["claude-sonnet-4-6"] = {
      pricing = {
        input = 3.0,
        output = 15.0,
        cache_read = 0.30,
        cache_write = 3.75,
      },
      max_input_tokens = 1000000,
      max_output_tokens = 64000,
      thinking_budgets = { minimal = 1024, low = 2048, medium = 8192, high = 16384 },
      min_thinking_budget = 1024,
      min_cache_tokens = 2048,
      meta = { adaptive_thinking = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "high" },
    },

    -- Claude Sonnet 4.5
    ["claude-sonnet-4-5"] = {
      pricing = {
        input = 3.0,
        output = 15.0,
        cache_read = 0.30,
        cache_write = 3.75,
      },
      max_input_tokens = 200000,
      max_output_tokens = 64000,
      thinking_budgets = { minimal = 1024, low = 2048, medium = 8192, high = 16384 },
      min_thinking_budget = 1024,
      min_cache_tokens = 2048,
    },
    ["claude-sonnet-4-5-20250929"] = {
      pricing = {
        input = 3.0,
        output = 15.0,
        cache_read = 0.30,
        cache_write = 3.75,
      },
      max_input_tokens = 200000,
      max_output_tokens = 64000,
      thinking_budgets = { minimal = 1024, low = 2048, medium = 8192, high = 16384 },
      min_thinking_budget = 1024,
      min_cache_tokens = 2048,
    },

    -- Claude Haiku 4.5
    ["claude-haiku-4-5"] = {
      pricing = {
        input = 1.0,
        output = 5.0,
        cache_read = 0.10,
        cache_write = 1.25,
      },
      max_input_tokens = 200000,
      max_output_tokens = 64000,
      thinking_budgets = { minimal = 1024, low = 2048, medium = 8192, high = 16384 },
      min_thinking_budget = 1024,
      min_cache_tokens = 4096,
    },
    ["claude-haiku-4-5-20251001"] = {
      pricing = {
        input = 1.0,
        output = 5.0,
        cache_read = 0.10,
        cache_write = 1.25,
      },
      max_input_tokens = 200000,
      max_output_tokens = 64000,
      thinking_budgets = { minimal = 1024, low = 2048, medium = 8192, high = 16384 },
      min_thinking_budget = 1024,
      min_cache_tokens = 4096,
    },

    -- Claude Opus 4.5
    ["claude-opus-4-5"] = {
      pricing = {
        input = 5.0,
        output = 25.0,
        cache_read = 0.50,
        cache_write = 6.25,
      },
      max_input_tokens = 200000,
      max_output_tokens = 64000,
      thinking_budgets = { minimal = 1024, low = 2048, medium = 8192, high = 16384 },
      min_thinking_budget = 1024,
      min_cache_tokens = 2048,
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "high" },
    },
    ["claude-opus-4-5-20251101"] = {
      pricing = {
        input = 5.0,
        output = 25.0,
        cache_read = 0.50,
        cache_write = 6.25,
      },
      max_input_tokens = 200000,
      max_output_tokens = 64000,
      thinking_budgets = { minimal = 1024, low = 2048, medium = 8192, high = 16384 },
      min_thinking_budget = 1024,
      min_cache_tokens = 2048,
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "high" },
    },

    -- Claude Opus 4.1 (deprecated Jun 5, 2026; retiring Aug 5, 2026)
    ["claude-opus-4-1"] = {
      pricing = {
        input = 15.0,
        output = 75.0,
        cache_read = 1.50,
        cache_write = 18.75,
      },
      max_input_tokens = 200000,
      max_output_tokens = 32000,
      thinking_budgets = { minimal = 1024, low = 2048, medium = 8192, high = 16384 },
      min_thinking_budget = 1024,
      min_cache_tokens = 2048,
    },
    ["claude-opus-4-1-20250805"] = {
      pricing = {
        input = 15.0,
        output = 75.0,
        cache_read = 1.50,
        cache_write = 18.75,
      },
      max_input_tokens = 200000,
      max_output_tokens = 32000,
      thinking_budgets = { minimal = 1024, low = 2048, medium = 8192, high = 16384 },
      min_thinking_budget = 1024,
      min_cache_tokens = 2048,
    },
  },
}
