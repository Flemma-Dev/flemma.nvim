--- OpenAI model definitions.
--- @see flemma.models.Types for type annotations

---@type flemma.models.ProviderModels
return {
  default = "gpt-5.4",
  models = {
    -- GPT-5.4 models
    ["gpt-5.4"] = {
      pricing = {
        input = 2.50,
        output = 15.0,
        cache_read = 0.25,
      },
      max_input_tokens = 922000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "xhigh" },
    },
    ["gpt-5.4-2026-03-05"] = {
      pricing = {
        input = 2.50,
        output = 15.0,
        cache_read = 0.25,
      },
      max_input_tokens = 922000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "xhigh" },
    },
    ["gpt-5.4-pro"] = {
      pricing = {
        input = 30.0,
        output = 180.0,
        cache_read = 30.0,
      },
      max_input_tokens = 922000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "medium", low = "medium", medium = "medium", high = "high", max = "xhigh" },
    },
    ["gpt-5.4-mini"] = {
      pricing = {
        input = 0.75,
        output = 4.50,
        cache_read = 0.075,
      },
      max_input_tokens = 272000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "xhigh" },
    },
    ["gpt-5.4-nano"] = {
      pricing = {
        input = 0.20,
        output = 1.25,
        cache_read = 0.02,
      },
      max_input_tokens = 272000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "xhigh" },
    },

    -- GPT-5.3 models
    ["gpt-5.3-chat-latest"] = {
      pricing = {
        input = 1.75,
        output = 14.0,
        cache_read = 0.175,
      },
      max_input_tokens = 272000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "xhigh" },
    },
    ["gpt-5.3-codex"] = {
      pricing = {
        input = 1.75,
        output = 14.0,
        cache_read = 0.175,
      },
      max_input_tokens = 272000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "xhigh" },
    },
    ["gpt-5.3-codex-spark"] = {
      pricing = {
        input = 1.75,
        output = 14.0,
        cache_read = 0.175,
      },
      max_input_tokens = 100000,
      max_output_tokens = 32000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "xhigh" },
    },

    -- GPT-5.2 models
    ["gpt-5.2"] = {
      pricing = {
        input = 1.75,
        output = 14.0,
        cache_read = 0.175,
      },
      max_input_tokens = 272000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "xhigh" },
    },
    ["gpt-5.2-chat-latest"] = {
      pricing = {
        input = 1.75,
        output = 14.0,
        cache_read = 0.175,
      },
      max_input_tokens = 128000,
      max_output_tokens = 16384,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "xhigh" },
    },
    ["gpt-5.2-codex"] = {
      pricing = {
        input = 1.75,
        output = 14.0,
        cache_read = 0.175,
      },
      max_input_tokens = 272000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "xhigh" },
    },
    ["gpt-5.2-pro"] = {
      pricing = {
        input = 21.0,
        output = 168.0,
        cache_read = 21.0,
      },
      max_input_tokens = 272000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "medium", low = "medium", medium = "medium", high = "high", max = "xhigh" },
    },

    -- GPT-5.1 models
    ["gpt-5.1"] = {
      pricing = {
        input = 1.25,
        output = 10.0,
        cache_read = 0.125,
      },
      max_input_tokens = 272000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "high" },
    },
    ["gpt-5.1-chat-latest"] = {
      pricing = {
        input = 1.25,
        output = 10.0,
        cache_read = 0.125,
      },
      max_input_tokens = 128000,
      max_output_tokens = 16384,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "high" },
    },
    ["gpt-5.1-codex"] = {
      pricing = {
        input = 1.25,
        output = 10.0,
        cache_read = 0.125,
      },
      max_input_tokens = 272000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "high" },
    },
    ["gpt-5.1-codex-max"] = {
      pricing = {
        input = 1.25,
        output = 10.0,
        cache_read = 0.125,
      },
      max_input_tokens = 272000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "high" },
    },
    ["gpt-5.1-codex-mini"] = {
      pricing = {
        input = 0.25,
        output = 2.0,
        cache_read = 0.025,
      },
      max_input_tokens = 272000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "high" },
    },

    -- GPT-5 models
    ["gpt-5"] = {
      pricing = {
        input = 1.25,
        output = 10.0,
        cache_read = 0.125,
      },
      max_input_tokens = 272000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "minimal", low = "low", medium = "medium", high = "high", max = "high" },
    },
    ["gpt-5-chat-latest"] = {
      pricing = {
        input = 1.25,
        output = 10.0,
        cache_read = 0.125,
      },
      max_input_tokens = 272000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "minimal", low = "low", medium = "medium", high = "high", max = "high" },
    },
    ["gpt-5-codex"] = {
      pricing = {
        input = 1.25,
        output = 10.0,
        cache_read = 0.125,
      },
      max_input_tokens = 272000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "minimal", low = "low", medium = "medium", high = "high", max = "high" },
    },
    ["gpt-5-mini"] = {
      pricing = {
        input = 0.25,
        output = 2.0,
        cache_read = 0.025,
      },
      max_input_tokens = 272000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "minimal", low = "low", medium = "medium", high = "high", max = "high" },
    },
    ["gpt-5-nano"] = {
      pricing = {
        input = 0.05,
        output = 0.40,
        cache_read = 0.005,
      },
      max_input_tokens = 272000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "minimal", low = "low", medium = "medium", high = "high", max = "high" },
    },
    ["gpt-5-pro"] = {
      pricing = {
        input = 15.0,
        output = 120.0,
        cache_read = 15.0,
      },
      max_input_tokens = 272000,
      max_output_tokens = 272000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "high", low = "high", medium = "high", high = "high", max = "high" },
    },
    ["gpt-5-search-api"] = {
      pricing = {
        input = 1.25,
        output = 10.0,
        cache_read = 0.125,
      },
      max_input_tokens = 272000,
      max_output_tokens = 128000,
    },

    -- GPT-4.1 models
    ["gpt-4.1"] = {
      pricing = {
        input = 2.0,
        output = 8.0,
        cache_read = 0.50,
      },
      max_input_tokens = 1047576,
      max_output_tokens = 32768,
    },
    ["gpt-4.1-2025-04-14"] = {
      pricing = {
        input = 2.0,
        output = 8.0,
        cache_read = 0.50,
      },
      max_input_tokens = 1047576,
      max_output_tokens = 32768,
    },
    ["gpt-4.1-mini"] = {
      pricing = {
        input = 0.40,
        output = 1.60,
        cache_read = 0.10,
      },
      max_input_tokens = 1047576,
      max_output_tokens = 32768,
    },
    ["gpt-4.1-mini-2025-04-14"] = {
      pricing = {
        input = 0.40,
        output = 1.60,
        cache_read = 0.10,
      },
      max_input_tokens = 1047576,
      max_output_tokens = 32768,
    },
    ["gpt-4.1-nano"] = {
      pricing = {
        input = 0.10,
        output = 0.40,
        cache_read = 0.025,
      },
      max_input_tokens = 1047576,
      max_output_tokens = 32768,
    },
    ["gpt-4.1-nano-2025-04-14"] = {
      pricing = {
        input = 0.10,
        output = 0.40,
        cache_read = 0.025,
      },
      max_input_tokens = 1047576,
      max_output_tokens = 32768,
    },

    -- GPT-4o models
    ["gpt-4o"] = {
      pricing = {
        input = 2.5,
        output = 10.0,
        cache_read = 1.25,
      },
      max_input_tokens = 128000,
      max_output_tokens = 16384,
    },
    ["gpt-4o-2024-11-20"] = {
      pricing = {
        input = 2.5,
        output = 10.0,
        cache_read = 1.25,
      },
      max_input_tokens = 128000,
      max_output_tokens = 16384,
    },
    ["gpt-4o-2024-08-06"] = {
      pricing = {
        input = 2.5,
        output = 10.0,
        cache_read = 1.25,
      },
      max_input_tokens = 128000,
      max_output_tokens = 16384,
    },
    ["gpt-4o-2024-05-13"] = {
      pricing = {
        input = 5.0,
        output = 15.0,
        cache_read = 5.0,
      },
      max_input_tokens = 128000,
      max_output_tokens = 4096,
    },
    ["gpt-4o-mini"] = {
      pricing = {
        input = 0.15,
        output = 0.60,
        cache_read = 0.075,
      },
      max_input_tokens = 128000,
      max_output_tokens = 16384,
    },
    ["gpt-4o-mini-2024-07-18"] = {
      pricing = {
        input = 0.15,
        output = 0.60,
        cache_read = 0.075,
      },
      max_input_tokens = 128000,
      max_output_tokens = 16384,
    },

    -- o-series models
    ["o1"] = {
      pricing = {
        input = 15.0,
        output = 60.0,
        cache_read = 7.50,
      },
      max_input_tokens = 200000,
      max_output_tokens = 100000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "high" },
    },
    ["o1-pro"] = {
      pricing = {
        input = 150.0,
        output = 600.0,
        cache_read = 150.0,
      },
      max_input_tokens = 200000,
      max_output_tokens = 100000,
    },
    ["o3"] = {
      pricing = {
        input = 2.0,
        output = 8.0,
        cache_read = 0.50,
      },
      max_input_tokens = 200000,
      max_output_tokens = 100000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "high" },
    },
    ["o3-pro"] = {
      pricing = {
        input = 20.0,
        output = 80.0,
        cache_read = 20.0,
      },
      max_input_tokens = 200000,
      max_output_tokens = 100000,
    },
    ["o3-deep-research"] = {
      pricing = {
        input = 10.0,
        output = 40.0,
        cache_read = 2.50,
      },
      max_input_tokens = 200000,
      max_output_tokens = 100000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "high" },
    },
    ["o3-mini"] = {
      pricing = {
        input = 1.10,
        output = 4.40,
        cache_read = 0.55,
      },
      max_input_tokens = 200000,
      max_output_tokens = 100000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "high" },
    },
    ["o4-mini"] = {
      pricing = {
        input = 1.10,
        output = 4.40,
        cache_read = 0.275,
      },
      max_input_tokens = 200000,
      max_output_tokens = 100000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "high" },
    },
    ["o4-mini-deep-research"] = {
      pricing = {
        input = 2.0,
        output = 8.0,
        cache_read = 0.50,
      },
      max_input_tokens = 200000,
      max_output_tokens = 100000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "high" },
    },

    -- Search and specialized models
    ["gpt-4o-mini-search-preview"] = {
      pricing = {
        input = 0.15,
        output = 0.60,
        cache_read = 0.15,
      },
      max_input_tokens = 128000,
      max_output_tokens = 16384,
    },
    ["gpt-4o-search-preview"] = {
      pricing = {
        input = 2.50,
        output = 10.0,
        cache_read = 2.50,
      },
      max_input_tokens = 128000,
      max_output_tokens = 16384,
    },
    ["computer-use-preview"] = {
      pricing = {
        input = 3.0,
        output = 12.0,
        cache_read = 3.0,
      },
      max_input_tokens = 128000,
      max_output_tokens = 16384,
    },

    -- GPT-4 Turbo models (legacy)
    ["gpt-4-turbo"] = {
      pricing = {
        input = 10.0,
        output = 30.0,
        cache_read = 10.0,
      },
      max_input_tokens = 128000,
      max_output_tokens = 4096,
    },
    ["gpt-4-turbo-2024-04-09"] = {
      pricing = {
        input = 10.0,
        output = 30.0,
        cache_read = 10.0,
      },
      max_input_tokens = 128000,
      max_output_tokens = 4096,
    },
    -- GPT-4 models (legacy)
    ["gpt-4"] = {
      pricing = {
        input = 30.0,
        output = 60.0,
        cache_read = 30.0,
      },
      max_input_tokens = 8192,
      max_output_tokens = 8192,
    },
    ["gpt-4-0613"] = {
      pricing = {
        input = 30.0,
        output = 60.0,
        cache_read = 30.0,
      },
      max_input_tokens = 8192,
      max_output_tokens = 8192,
    },
    -- GPT-3.5 Turbo models (legacy)
    ["gpt-3.5-turbo"] = {
      pricing = {
        input = 0.50,
        output = 1.50,
        cache_read = 0.50,
      },
      max_input_tokens = 16385,
      max_output_tokens = 4096,
    },
    ["gpt-3.5-turbo-0125"] = {
      pricing = {
        input = 0.50,
        output = 1.50,
        cache_read = 0.50,
      },
      max_input_tokens = 16385,
      max_output_tokens = 4096,
    },
    ["gpt-3.5-turbo-1106"] = { -- (deprecated, retiring Sep 28, 2026)
      pricing = {
        input = 1.0,
        output = 2.0,
        cache_read = 1.0,
      },
      max_input_tokens = 16385,
      max_output_tokens = 4096,
    },
    ["gpt-3.5-turbo-instruct"] = { -- (deprecated, retiring Sep 28, 2026)
      pricing = {
        input = 1.50,
        output = 2.0,
        cache_read = 1.50,
      },
      max_input_tokens = 4096,
      max_output_tokens = 4096,
    },
  },
}
