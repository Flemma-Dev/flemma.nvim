--- Flemma model definitions - DATA ONLY
--- Centralized configuration for all supported models across providers
--- Contains model lists, defaults, and pricing information
--- This file is data-only and contains no functions
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
---@field pricing flemma.models.Pricing
---@field max_input_tokens? integer Maximum context window size (input tokens)
---@field max_output_tokens? integer Maximum tokens the model can generate in a single response
---@field min_output_tokens? integer Minimum max_tokens the API accepts for this model
---@field supports_reasoning_effort? boolean Whether the model supports reasoning_effort parameter
---@field thinking_budgets? flemma.models.ThinkingBudgets Per-model token budgets for each thinking level
---@field min_thinking_budget? integer Minimum thinking budget the API accepts
---@field max_thinking_budget? integer Maximum thinking budget the API accepts
---@field thinking_effort_map? table<string, string> Maps Flemma canonical levels to provider API values
---@field supports_adaptive_thinking? boolean True for 4.6 models that use thinking.type="adaptive" (vs budget-based)
---@field min_cache_tokens? integer Minimum tokens for cache prefix to be accepted (informational)

---@class flemma.models.ProviderModels
---@field default string Default model name for this provider
---@field models table<string, flemma.models.ModelInfo>

---@class flemma.models.Data
---@field providers table<string, flemma.models.ProviderModels>

---@type flemma.models.Data
return {
  providers = {
    anthropic = {
      default = "claude-sonnet-4-6",
      models = {
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
          supports_adaptive_thinking = true,
          thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "max" },
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
          supports_adaptive_thinking = true,
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

        -- Claude Opus 4.1 (as of Aug 2025)
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

        -- Claude Opus 4
        ["claude-opus-4-0"] = {
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
        ["claude-opus-4-20250514"] = {
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

        -- Claude Sonnet 4
        ["claude-sonnet-4-0"] = {
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
        ["claude-sonnet-4-20250514"] = {
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

        -- Claude Haiku 3 (deprecated, retiring Apr 20, 2026)
        ["claude-3-haiku-20240307"] = {
          pricing = {
            input = 0.25,
            output = 1.25,
            cache_read = 0.03,
            cache_write = 0.30,
          },
          max_input_tokens = 200000,
          max_output_tokens = 4096,
          min_cache_tokens = 1024,
        },
      },
    },

    vertex = {
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
    },

    openai = {
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
        },
        ["gpt-5.4-mini"] = {
          pricing = {
            input = 0.75,
            output = 4.50,
            cache_read = 0.075,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
          supports_reasoning_effort = true,
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
    },

    moonshot = {
      default = "kimi-k2.5",
      -- Moonshot uses automatic caching with no separate write fee.
      -- The API reports `cached_tokens` (hit count) but never `cache_creation` tokens,
      -- so `cache_write` is intentionally omitted from pricing. Verified against live API
      -- responses (2026-03-26): usage contains `cached_tokens` + `prompt_tokens_details.cached_tokens`
      -- but no cache creation/write fields.
      models = {
        -- Kimi K2.5 (multimodal flagship, 256K context)
        ["kimi-k2.5"] = {
          pricing = { input = 0.60, output = 3.00, cache_read = 0.10 },
          max_input_tokens = 262144,
          max_output_tokens = 65536,
          min_output_tokens = 16000,
        },

        -- Kimi K2 thinking models (256K context, thinking forced on)
        ["kimi-k2-thinking"] = {
          pricing = { input = 0.60, output = 2.50, cache_read = 0.15 },
          max_input_tokens = 262144,
          max_output_tokens = 65536,
          min_output_tokens = 16000,
        },
        ["kimi-k2-thinking-turbo"] = {
          pricing = { input = 1.15, output = 8.00, cache_read = 0.15 },
          max_input_tokens = 262144,
          max_output_tokens = 65536,
          min_output_tokens = 16000,
        },

        -- Kimi K2 generation models (no thinking)
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
    },
  },
}
