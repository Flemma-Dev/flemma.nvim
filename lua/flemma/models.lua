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

---@class flemma.models.Pricing
---@field input number USD per million input tokens
---@field output number USD per million output tokens

---@class flemma.models.ModelInfo
---@field pricing flemma.models.Pricing
---@field max_input_tokens? integer Maximum context window size (input tokens)
---@field max_output_tokens? integer Maximum tokens the model can generate in a single response
---@field supports_reasoning_effort? boolean Whether the model supports reasoning_effort parameter

---@class flemma.models.ProviderModels
---@field default string Default model name for this provider
---@field models table<string, flemma.models.ModelInfo>
---@field cache_read_multiplier? number Cache read cost as fraction of base input price (e.g. 0.1 = 10%)
---@field cache_write_multipliers? table<string, number> Cache write cost multipliers keyed by retention ("short", "long")

---@class flemma.models.Data
---@field providers table<string, flemma.models.ProviderModels>

---@type flemma.models.Data
return {
  providers = {
    anthropic = {
      default = "claude-sonnet-4-6",
      cache_read_multiplier = 0.1, -- Cache reads cost 10% of base input price
      cache_write_multipliers = {
        short = 1.25, -- 5-minute TTL: 1.25× base input price
        long = 2.0, -- 1-hour TTL: 2.0× base input price
      },
      models = {
        -- Claude Opus 4.6
        ["claude-opus-4-6"] = {
          pricing = {
            input = 5.0,
            output = 25.0,
          },
          max_input_tokens = 1000000,
          max_output_tokens = 128000,
        },

        -- Claude Sonnet 4.6
        ["claude-sonnet-4-6"] = {
          pricing = {
            input = 3.0,
            output = 15.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 64000,
        },

        -- Claude Sonnet 4.5
        ["claude-sonnet-4-5"] = {
          pricing = {
            input = 3.0,
            output = 15.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 64000,
        },
        ["claude-sonnet-4-5-20250929"] = {
          pricing = {
            input = 3.0,
            output = 15.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 64000,
        },

        -- Claude Haiku 4.5
        ["claude-haiku-4-5"] = {
          pricing = {
            input = 1.0,
            output = 5.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 64000,
        },
        ["claude-haiku-4-5-20251001"] = {
          pricing = {
            input = 1.0,
            output = 5.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 64000,
        },

        -- Claude Opus 4.5
        ["claude-opus-4-5"] = {
          pricing = {
            input = 5.0,
            output = 25.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 64000,
        },
        ["claude-opus-4-5-20251101"] = {
          pricing = {
            input = 5.0,
            output = 25.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 64000,
        },

        -- Claude Opus 4.1 (as of Aug 2025)
        ["claude-opus-4-1"] = {
          pricing = {
            input = 15.0,
            output = 75.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 32000,
        },
        ["claude-opus-4-1-20250805"] = {
          pricing = {
            input = 15.0,
            output = 75.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 32000,
        },

        -- Claude Opus 4
        ["claude-opus-4-0"] = {
          pricing = {
            input = 15.0,
            output = 75.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 32000,
        },
        ["claude-opus-4-20250514"] = {
          pricing = {
            input = 15.0,
            output = 75.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 32000,
        },

        -- Claude Sonnet 4
        ["claude-sonnet-4-0"] = {
          pricing = {
            input = 3.0,
            output = 15.0,
          },
          max_input_tokens = 1000000,
          max_output_tokens = 64000,
        },
        ["claude-sonnet-4-20250514"] = {
          pricing = {
            input = 3.0,
            output = 15.0,
          },
          max_input_tokens = 1000000,
          max_output_tokens = 64000,
        },

        -- Claude Haiku 3 (deprecated, retiring Apr 2026)
        ["claude-3-haiku-20240307"] = {
          pricing = {
            input = 0.25,
            output = 1.25,
          },
          max_input_tokens = 200000,
          max_output_tokens = 4096,
        },
      },
    },

    vertex = {
      default = "gemini-2.5-pro",
      cache_read_multiplier = 0.1, -- Implicit cache reads cost 10% of base input price (Gemini 2.5+)
      models = {
        -- Gemini 3.1 Pro Preview
        ["gemini-3.1-pro-preview"] = {
          pricing = {
            input = 2.0,
            output = 12.0,
          },
          max_input_tokens = 1048576,
          max_output_tokens = 65536,
        },

        -- Gemini 3 Flash Preview
        ["gemini-3-flash-preview"] = {
          pricing = {
            input = 0.50,
            output = 3.0,
          },
          max_input_tokens = 1048576,
          max_output_tokens = 65535,
        },

        -- Gemini 3 Pro Preview
        ["gemini-3-pro-preview"] = {
          pricing = {
            input = 2.0,
            output = 12.0,
          },
          max_input_tokens = 1048576,
          max_output_tokens = 65535,
        },

        -- Gemini 2.5 Pro models
        ["gemini-2.5-pro"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
          max_input_tokens = 1048576,
          max_output_tokens = 65535,
        },

        -- Gemini 2.5 Flash models
        ["gemini-2.5-flash"] = {
          pricing = {
            input = 0.30,
            output = 2.50,
          },
          max_input_tokens = 1048576,
          max_output_tokens = 65535,
        },

        -- Gemini 2.5 Flash Lite models
        ["gemini-2.5-flash-lite"] = {
          pricing = {
            input = 0.10,
            output = 0.40,
          },
          max_input_tokens = 1048576,
          max_output_tokens = 65535,
        },

        -- Gemini 2.0 Flash models (retiring Jun 2026)
        ["gemini-2.0-flash"] = {
          pricing = {
            input = 0.15,
            output = 0.60,
          },
          max_input_tokens = 1048576,
          max_output_tokens = 8192,
        },
        ["gemini-2.0-flash-001"] = {
          pricing = {
            input = 0.15,
            output = 0.60,
          },
          max_input_tokens = 1048576,
          max_output_tokens = 8192,
        },

        -- Gemini 2.0 Flash Lite models (retiring Jun 2026)
        ["gemini-2.0-flash-lite"] = {
          pricing = {
            input = 0.075,
            output = 0.30,
          },
          max_input_tokens = 1048576,
          max_output_tokens = 8192,
        },
        ["gemini-2.0-flash-lite-001"] = {
          pricing = {
            input = 0.075,
            output = 0.30,
          },
          max_input_tokens = 1048576,
          max_output_tokens = 8192,
        },
      },
    },

    openai = {
      default = "gpt-5",
      cache_read_multiplier = 0.5, -- Cached input tokens cost 50% of base input price
      models = {
        -- GPT-5.2 models
        ["gpt-5.2"] = {
          pricing = {
            input = 1.75,
            output = 14.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
        },
        ["gpt-5.2-2025-12-11"] = {
          pricing = {
            input = 1.75,
            output = 14.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
        },
        ["gpt-5.2-chat-latest"] = {
          pricing = {
            input = 1.75,
            output = 14.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
        },
        ["gpt-5.2-codex"] = {
          pricing = {
            input = 1.75,
            output = 14.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
        },
        ["gpt-5.2-pro"] = {
          pricing = {
            input = 21.0,
            output = 168.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
        },
        ["gpt-5.2-pro-2025-12-11"] = {
          pricing = {
            input = 21.0,
            output = 168.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
        },

        -- GPT-5.1 models
        ["gpt-5.1"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
        },
        ["gpt-5.1-2025-11-13"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
        },
        ["gpt-5.1-chat-latest"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
        },
        ["gpt-5.1-codex"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
        },
        ["gpt-5.1-codex-max"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
        },
        ["gpt-5.1-codex-mini"] = {
          pricing = {
            input = 0.25,
            output = 2.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
        },

        -- GPT-5 models
        ["gpt-5"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
        },
        ["gpt-5-2025-08-07"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
        },
        ["gpt-5-chat-latest"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
        },
        ["gpt-5-codex"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
        },
        ["gpt-5-mini"] = {
          pricing = {
            input = 0.25,
            output = 2.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
        },
        ["gpt-5-mini-2025-08-07"] = {
          pricing = {
            input = 0.25,
            output = 2.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
        },
        ["gpt-5-nano"] = {
          pricing = {
            input = 0.05,
            output = 0.40,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
        },
        ["gpt-5-nano-2025-08-07"] = {
          pricing = {
            input = 0.05,
            output = 0.40,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
          supports_reasoning_effort = true,
        },
        ["gpt-5-pro"] = {
          pricing = {
            input = 15.0,
            output = 120.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
        },
        ["gpt-5-pro-2025-10-06"] = {
          pricing = {
            input = 15.0,
            output = 120.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
        },
        ["gpt-5-search-api"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
          max_input_tokens = 272000,
          max_output_tokens = 128000,
        },

        -- GPT-4.1 models
        ["gpt-4.1"] = {
          pricing = {
            input = 2.0,
            output = 8.0,
          },
          max_input_tokens = 1047576,
          max_output_tokens = 32768,
        },
        ["gpt-4.1-2025-04-14"] = {
          pricing = {
            input = 2.0,
            output = 8.0,
          },
          max_input_tokens = 1047576,
          max_output_tokens = 32768,
        },
        ["gpt-4.1-mini"] = {
          pricing = {
            input = 0.40,
            output = 1.60,
          },
          max_input_tokens = 1047576,
          max_output_tokens = 32768,
        },
        ["gpt-4.1-mini-2025-04-14"] = {
          pricing = {
            input = 0.40,
            output = 1.60,
          },
          max_input_tokens = 1047576,
          max_output_tokens = 32768,
        },
        ["gpt-4.1-nano"] = {
          pricing = {
            input = 0.10,
            output = 0.40,
          },
          max_input_tokens = 1047576,
          max_output_tokens = 32768,
        },
        ["gpt-4.1-nano-2025-04-14"] = {
          pricing = {
            input = 0.10,
            output = 0.40,
          },
          max_input_tokens = 1047576,
          max_output_tokens = 32768,
        },

        -- GPT-4o models
        ["gpt-4o"] = {
          pricing = {
            input = 2.5,
            output = 10.0,
          },
          max_input_tokens = 128000,
          max_output_tokens = 16384,
        },
        ["gpt-4o-2024-11-20"] = {
          pricing = {
            input = 2.5,
            output = 10.0,
          },
          max_input_tokens = 128000,
          max_output_tokens = 16384,
        },
        ["gpt-4o-2024-08-06"] = {
          pricing = {
            input = 2.5,
            output = 10.0,
          },
          max_input_tokens = 128000,
          max_output_tokens = 16384,
        },
        ["gpt-4o-2024-05-13"] = {
          pricing = {
            input = 5.0,
            output = 15.0,
          },
          max_input_tokens = 128000,
          max_output_tokens = 4096,
        },
        ["gpt-4o-mini"] = {
          pricing = {
            input = 0.15,
            output = 0.60,
          },
          max_input_tokens = 128000,
          max_output_tokens = 16384,
        },
        ["gpt-4o-mini-2024-07-18"] = {
          pricing = {
            input = 0.15,
            output = 0.60,
          },
          max_input_tokens = 128000,
          max_output_tokens = 16384,
        },

        -- o-series models
        ["o1"] = {
          pricing = {
            input = 15.0,
            output = 60.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 100000,
          supports_reasoning_effort = true,
        },
        ["o1-2024-12-17"] = {
          pricing = {
            input = 15.0,
            output = 60.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 100000,
          supports_reasoning_effort = true,
        },
        ["o1-pro"] = {
          pricing = {
            input = 150.0,
            output = 600.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 100000,
        },
        ["o1-pro-2025-03-19"] = {
          pricing = {
            input = 150.0,
            output = 600.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 100000,
        },
        ["o3"] = {
          pricing = {
            input = 2.0,
            output = 8.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 100000,
          supports_reasoning_effort = true,
        },
        ["o3-2025-04-16"] = {
          pricing = {
            input = 2.0,
            output = 8.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 100000,
          supports_reasoning_effort = true,
        },
        ["o3-pro"] = {
          pricing = {
            input = 20.0,
            output = 80.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 100000,
        },
        ["o3-pro-2025-06-10"] = {
          pricing = {
            input = 20.0,
            output = 80.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 100000,
        },
        ["o3-deep-research"] = {
          pricing = {
            input = 10.0,
            output = 40.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 100000,
          supports_reasoning_effort = true,
        },
        ["o3-mini"] = {
          pricing = {
            input = 1.10,
            output = 4.40,
          },
          max_input_tokens = 200000,
          max_output_tokens = 100000,
          supports_reasoning_effort = true,
        },
        ["o3-mini-2025-01-31"] = {
          pricing = {
            input = 1.10,
            output = 4.40,
          },
          max_input_tokens = 200000,
          max_output_tokens = 100000,
          supports_reasoning_effort = true,
        },
        ["o4-mini"] = {
          pricing = {
            input = 1.10,
            output = 4.40,
          },
          max_input_tokens = 200000,
          max_output_tokens = 100000,
          supports_reasoning_effort = true,
        },
        ["o4-mini-2025-04-16"] = {
          pricing = {
            input = 1.10,
            output = 4.40,
          },
          max_input_tokens = 200000,
          max_output_tokens = 100000,
          supports_reasoning_effort = true,
        },
        ["o4-mini-deep-research"] = {
          pricing = {
            input = 2.0,
            output = 8.0,
          },
          max_input_tokens = 200000,
          max_output_tokens = 100000,
          supports_reasoning_effort = true,
        },

        -- Search and specialized models
        ["gpt-4o-mini-search-preview"] = {
          pricing = {
            input = 0.15,
            output = 0.60,
          },
          max_input_tokens = 128000,
          max_output_tokens = 16384,
        },
        ["gpt-4o-search-preview"] = {
          pricing = {
            input = 2.50,
            output = 10.0,
          },
          max_input_tokens = 128000,
          max_output_tokens = 16384,
        },
        ["computer-use-preview"] = {
          pricing = {
            input = 3.0,
            output = 12.0,
          },
          max_input_tokens = 128000,
          max_output_tokens = 16384,
        },

        -- GPT-4 Turbo models (legacy)
        ["gpt-4-turbo"] = {
          pricing = {
            input = 10.0,
            output = 30.0,
          },
          max_input_tokens = 128000,
          max_output_tokens = 4096,
        },
        ["gpt-4-turbo-2024-04-09"] = {
          pricing = {
            input = 10.0,
            output = 30.0,
          },
          max_input_tokens = 128000,
          max_output_tokens = 4096,
        },
        ["gpt-4-0125-preview"] = { -- (deprecated, retiring Mar 2026)
          pricing = {
            input = 10.0,
            output = 30.0,
          },
          max_input_tokens = 128000,
          max_output_tokens = 4096,
        },
        ["gpt-4-1106-preview"] = { -- (deprecated, retiring Mar 2026)
          pricing = {
            input = 10.0,
            output = 30.0,
          },
          max_input_tokens = 128000,
          max_output_tokens = 4096,
        },

        -- GPT-4 models (legacy)
        ["gpt-4"] = {
          pricing = {
            input = 30.0,
            output = 60.0,
          },
          max_input_tokens = 8192,
          max_output_tokens = 8192,
        },
        ["gpt-4-0613"] = {
          pricing = {
            input = 30.0,
            output = 60.0,
          },
          max_input_tokens = 8192,
          max_output_tokens = 8192,
        },
        ["gpt-4-0314"] = { -- (deprecated, retiring Mar 2026)
          pricing = {
            input = 30.0,
            output = 60.0,
          },
          max_input_tokens = 8192,
          max_output_tokens = 8192,
        },

        -- GPT-3.5 Turbo models (legacy)
        ["gpt-3.5-turbo"] = {
          pricing = {
            input = 0.50,
            output = 1.50,
          },
          max_input_tokens = 16385,
          max_output_tokens = 4096,
        },
        ["gpt-3.5-turbo-0125"] = {
          pricing = {
            input = 0.50,
            output = 1.50,
          },
          max_input_tokens = 16385,
          max_output_tokens = 4096,
        },
        ["gpt-3.5-turbo-1106"] = { -- (deprecated, retiring Sep 2026)
          pricing = {
            input = 1.0,
            output = 2.0,
          },
          max_input_tokens = 16385,
          max_output_tokens = 4096,
        },
        ["gpt-3.5-turbo-instruct"] = { -- (deprecated, retiring Sep 2026)
          pricing = {
            input = 1.50,
            output = 2.0,
          },
          max_input_tokens = 4096,
          max_output_tokens = 4096,
        },
      },
    },
  },
}
