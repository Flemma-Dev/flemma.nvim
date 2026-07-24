--- Vertex AI (Google Gemini) model definitions.
--- @see flemma.models.Types for type annotations

---@type flemma.models.ProviderModels
return {
  default = "gemini-3.1-pro-preview",
  models = {
    -- Gemini 3.6 Flash (released Jul 21, 2026; no retirement date announced)
    ["gemini-3.6-flash"] = {
      pricing = {
        input = 1.50,
        output = 7.50,
        cache_read = 0.15,
      },
      max_input_tokens = 1048576,
      max_output_tokens = 65536,
      thinking_effort_map = { minimal = "MINIMAL", low = "LOW", medium = "MEDIUM", high = "HIGH", max = "HIGH" },
    },

    -- Gemini 3.5 Flash
    ["gemini-3.5-flash"] = {
      pricing = {
        input = 1.50,
        output = 9.0,
        cache_read = 0.15,
      },
      max_input_tokens = 1048576,
      max_output_tokens = 65536,
      thinking_effort_map = { minimal = "MINIMAL", low = "LOW", medium = "MEDIUM", high = "HIGH", max = "HIGH" },
    },

    -- Gemini 3.1 Pro Preview — thinkingLevel only (no MINIMAL, hence minimal → LOW)
    ["gemini-3.1-pro-preview"] = {
      pricing = {
        input = 2.0,
        output = 12.0,
        cache_read = 0.20,
      },
      max_input_tokens = 1048576,
      max_output_tokens = 65536,
      thinking_effort_map = { minimal = "LOW", low = "LOW", medium = "MEDIUM", high = "HIGH", max = "HIGH" },
    },

    -- Gemini 3.5 Flash Lite (released Jul 21, 2026; retires no earlier than Jul 21, 2027)
    ["gemini-3.5-flash-lite"] = {
      pricing = {
        input = 0.30,
        output = 2.50,
        cache_read = 0.03,
      },
      max_input_tokens = 1048576,
      max_output_tokens = 65536,
      thinking_effort_map = { minimal = "MINIMAL", low = "LOW", medium = "MEDIUM", high = "HIGH", max = "HIGH" },
    },

    -- Gemini 3.1 Flash Lite
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
    ["gemini-3.1-flash-lite"] = {
      pricing = {
        input = 0.25,
        output = 1.50,
        cache_read = 0.025,
      },
      max_input_tokens = 1048576,
      max_output_tokens = 65536,
      thinking_effort_map = { minimal = "MINIMAL", low = "LOW", medium = "MEDIUM", high = "HIGH", max = "HIGH" },
    },

    -- Gemini 3 Pro Preview — no longer listed on the Vertex pricing page, the
    -- Provisioned Throughput model table, or the thinking supported-models list;
    -- still published by models.dev. Kept until Google announces a retirement.
    ["gemini-3-pro-preview"] = {
      pricing = {
        input = 2.0,
        output = 12.0,
        cache_read = 0.20,
      },
      max_input_tokens = 1048576,
      max_output_tokens = 65536,
      thinking_effort_map = { minimal = "LOW", low = "LOW", medium = "MEDIUM", high = "HIGH", max = "HIGH" },
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
      thinking_effort_map = { minimal = "MINIMAL", low = "LOW", medium = "MEDIUM", high = "HIGH", max = "HIGH" },
    },

    -- Gemini 2.5 models (retiring October 16, 2026) — thinkingBudget only;
    -- passing thinkingLevel to a pre-Gemini-3 model returns an error. These are
    -- the only entries that carry budgets: Google publishes a thinkingBudget
    -- range for 2.5 alone, and a Gemini 3 request carrying both parameters errors.
    ["gemini-2.5-pro"] = {
      pricing = {
        input = 1.25,
        output = 10.0,
        cache_read = 0.125,
      },
      max_input_tokens = 1048576,
      max_output_tokens = 65536,
      thinking_budgets = { minimal = 128, low = 2048, medium = 8192, high = 32768 },
      -- 2.5 Pro's floor is 128, not 1 — unlike 2.5 Flash. Thinking cannot be
      -- turned off on this model, which is why the floor is above zero.
      min_thinking_budget = 128,
      max_thinking_budget = 32768,
    },

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

    -- Gemini 2.0 Flash and 2.0 Flash Lite were retired June 1, 2026.
  },
}
