--- Vertex AI (Google Gemini) model definitions.
--- @see flemma.models.Types for type annotations

---@type flemma.models.ProviderModels
return {
  default = "gemini-3.1-pro-preview",
  models = {
    -- Gemini 3.1 Pro Preview
    ["gemini-3.1-pro-preview"] = {
      pricing = {
        input = 2.0,
        output = 12.0,
        cache_read = 0.20,
      },
      max_input_tokens = 1048576,
      max_output_tokens = 65536,
      thinking_budgets = { minimal = 128, low = 2048, medium = 8192, high = 32768 },
      min_thinking_budget = 1,
      max_thinking_budget = 32768,
      thinking_effort_map = { minimal = "LOW", low = "LOW", medium = "MEDIUM", high = "HIGH", max = "HIGH" },
    },

    -- Gemini 3.1 Flash Lite Preview
    ["gemini-3.1-flash-lite-preview"] = {
      pricing = {
        input = 0.25,
        output = 1.50,
        cache_read = 0.025,
      },
      max_input_tokens = 1048576,
      max_output_tokens = 65536,
      thinking_effort_map = { minimal = "MINIMAL", low = "LOW", medium = "MEDIUM", high = "HIGH", max = "HIGH" },
    },

    -- Gemini 3 Flash Preview
    ["gemini-3-flash-preview"] = {
      pricing = {
        input = 0.50,
        output = 3.0,
        cache_read = 0.05,
      },
      max_input_tokens = 1048576,
      max_output_tokens = 65536,
      thinking_budgets = { minimal = 128, low = 2048, medium = 8192, high = 24576 },
      min_thinking_budget = 1,
      max_thinking_budget = 24576,
      thinking_effort_map = { minimal = "MINIMAL", low = "LOW", medium = "MEDIUM", high = "HIGH", max = "HIGH" },
    },

    -- Gemini 2.5 Pro models
    ["gemini-2.5-pro"] = {
      pricing = {
        input = 1.25,
        output = 10.0,
        cache_read = 0.125,
      },
      max_input_tokens = 1048576,
      max_output_tokens = 65536,
      thinking_budgets = { minimal = 128, low = 2048, medium = 8192, high = 32768 },
      min_thinking_budget = 1,
      max_thinking_budget = 32768,
    },

    -- Gemini 2.5 Flash models
    ["gemini-2.5-flash"] = {
      pricing = {
        input = 0.30,
        output = 2.50,
        cache_read = 0.03,
      },
      max_input_tokens = 1048576,
      max_output_tokens = 65536,
      thinking_budgets = { minimal = 128, low = 2048, medium = 8192, high = 24576 },
      min_thinking_budget = 1,
      max_thinking_budget = 24576,
    },

    -- Gemini 2.5 Flash Lite models
    ["gemini-2.5-flash-lite"] = {
      pricing = {
        input = 0.10,
        output = 0.40,
        cache_read = 0.01,
      },
      max_input_tokens = 1048576,
      max_output_tokens = 65536,
      thinking_budgets = { minimal = 512, low = 2048, medium = 8192, high = 24576 },
      min_thinking_budget = 512,
      max_thinking_budget = 24576,
    },

    -- Gemini 2.0 Flash models (retiring Jun 2026, no context caching on Vertex)
    ["gemini-2.0-flash"] = {
      pricing = {
        input = 0.15,
        output = 0.60,
        cache_read = 0.15,
      },
      max_input_tokens = 1048576,
      max_output_tokens = 8192,
    },
    ["gemini-2.0-flash-001"] = {
      pricing = {
        input = 0.15,
        output = 0.60,
        cache_read = 0.15,
      },
      max_input_tokens = 1048576,
      max_output_tokens = 8192,
    },

    -- Gemini 2.0 Flash Lite models (retiring Jun 2026, no context caching on Vertex)
    ["gemini-2.0-flash-lite"] = {
      pricing = {
        input = 0.075,
        output = 0.30,
        cache_read = 0.075,
      },
      max_input_tokens = 1048576,
      max_output_tokens = 8192,
    },
    ["gemini-2.0-flash-lite-001"] = {
      pricing = {
        input = 0.075,
        output = 0.30,
        cache_read = 0.075,
      },
      max_input_tokens = 1048576,
      max_output_tokens = 8192,
    },
  },
}
