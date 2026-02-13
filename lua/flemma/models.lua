--- Flemma model definitions - DATA ONLY
--- Centralized configuration for all supported models across providers
--- Contains model lists, defaults, and pricing information
--- This file is data-only and contains no functions

---@class flemma.models.Pricing
---@field input number USD per million input tokens
---@field output number USD per million output tokens

---@class flemma.models.ModelInfo
---@field pricing flemma.models.Pricing
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
    -- Note: "claude" is a deprecated alias for "anthropic" (see provider/providers.lua)
    anthropic = {
      default = "claude-sonnet-4-5",
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
        },

        -- Claude Sonnet 4.5 (as of Sep 2025)
        ["claude-sonnet-4-5"] = {
          pricing = {
            input = 3.0,
            output = 15.0,
          },
        },
        ["claude-sonnet-4-5-20250929"] = {
          pricing = {
            input = 3.0,
            output = 15.0,
          },
        },

        -- Claude Haiku 4.5
        ["claude-haiku-4-5"] = {
          pricing = {
            input = 1.0,
            output = 5.0,
          },
        },
        ["claude-haiku-4-5-20251001"] = {
          pricing = {
            input = 1.0,
            output = 5.0,
          },
        },

        -- Claude Opus 4.5
        ["claude-opus-4-5"] = {
          pricing = {
            input = 5.0,
            output = 25.0,
          },
        },
        ["claude-opus-4-5-20251101"] = {
          pricing = {
            input = 5.0,
            output = 25.0,
          },
        },

        -- Claude Opus 4.1 (as of Aug 2025)
        ["claude-opus-4-1"] = {
          pricing = {
            input = 15.0,
            output = 75.0,
          },
        },
        ["claude-opus-4-1-20250805"] = {
          pricing = {
            input = 15.0,
            output = 75.0,
          },
        },

        -- Claude Opus 4
        ["claude-opus-4-0"] = {
          pricing = {
            input = 15.0,
            output = 75.0,
          },
        },
        ["claude-opus-4-20250514"] = {
          pricing = {
            input = 15.0,
            output = 75.0,
          },
        },

        -- Claude Sonnet 4
        ["claude-sonnet-4-0"] = {
          pricing = {
            input = 3.0,
            output = 15.0,
          },
        },
        ["claude-sonnet-4-20250514"] = {
          pricing = {
            input = 3.0,
            output = 15.0,
          },
        },

        -- Claude Sonnet 3.7 (deprecated, retiring Feb 2026)
        ["claude-3-7-sonnet-latest"] = {
          pricing = {
            input = 3.0,
            output = 15.0,
          },
        },
        ["claude-3-7-sonnet-20250219"] = {
          pricing = {
            input = 3.0,
            output = 15.0,
          },
        },

        -- Claude Haiku 3.5 (deprecated, retiring Feb 2026)
        ["claude-3-5-haiku-latest"] = {
          pricing = {
            input = 0.80,
            output = 4.0,
          },
        },
        ["claude-3-5-haiku-20241022"] = {
          pricing = {
            input = 0.80,
            output = 4.0,
          },
        },

        -- Claude Haiku 3
        ["claude-3-haiku-20240307"] = {
          pricing = {
            input = 0.25,
            output = 1.25,
          },
        },
      },
    },

    vertex = {
      default = "gemini-2.5-pro",
      cache_read_multiplier = 0.1, -- Implicit cache reads cost 10% of base input price (Gemini 2.5+)
      models = {
        -- Gemini 3 Flash Preview
        ["gemini-3-flash-preview"] = {
          pricing = {
            input = 0.50,
            output = 3.0,
          },
        },

        -- Gemini 3 Pro Preview
        ["gemini-3-pro-preview"] = {
          pricing = {
            input = 2.0,
            output = 12.0,
          },
        },

        -- Gemini 2.5 Pro models
        ["gemini-2.5-pro"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
        },

        -- Gemini 2.5 Flash models
        ["gemini-2.5-flash"] = {
          pricing = {
            input = 0.30,
            output = 2.50,
          },
        },
        ["gemini-2.5-flash-preview-09-2025"] = {
          pricing = {
            input = 0.30,
            output = 2.50,
          },
        },

        -- Gemini 2.5 Flash Lite models
        ["gemini-2.5-flash-lite"] = {
          pricing = {
            input = 0.10,
            output = 0.40,
          },
        },
        ["gemini-2.5-flash-lite-preview-09-2025"] = {
          pricing = {
            input = 0.10,
            output = 0.40,
          },
        },

        -- Gemini 2.0 Flash models (retiring Mar 2026)
        ["gemini-2.0-flash"] = {
          pricing = {
            input = 0.15,
            output = 0.60,
          },
        },
        ["gemini-2.0-flash-001"] = {
          pricing = {
            input = 0.15,
            output = 0.60,
          },
        },

        -- Gemini 2.0 Flash Lite models (retiring Mar 2026)
        ["gemini-2.0-flash-lite"] = {
          pricing = {
            input = 0.075,
            output = 0.30,
          },
        },
        ["gemini-2.0-flash-lite-001"] = {
          pricing = {
            input = 0.075,
            output = 0.30,
          },
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
          supports_reasoning_effort = true,
        },
        ["gpt-5.2-2025-12-11"] = {
          pricing = {
            input = 1.75,
            output = 14.0,
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5.2-chat-latest"] = {
          pricing = {
            input = 1.75,
            output = 14.0,
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5.2-codex"] = {
          pricing = {
            input = 1.75,
            output = 14.0,
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5.2-pro"] = {
          pricing = {
            input = 21.0,
            output = 168.0,
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5.2-pro-2025-12-11"] = {
          pricing = {
            input = 21.0,
            output = 168.0,
          },
          supports_reasoning_effort = true,
        },

        -- GPT-5.1 models
        ["gpt-5.1"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5.1-2025-11-13"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5.1-chat-latest"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5.1-codex"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5.1-codex-max"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5.1-codex-mini"] = {
          pricing = {
            input = 0.25,
            output = 2.0,
          },
          supports_reasoning_effort = true,
        },

        -- GPT-5 models
        ["gpt-5"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5-2025-08-07"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5-chat-latest"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5-codex"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5-mini"] = {
          pricing = {
            input = 0.25,
            output = 2.0,
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5-mini-2025-08-07"] = {
          pricing = {
            input = 0.25,
            output = 2.0,
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5-nano"] = {
          pricing = {
            input = 0.05,
            output = 0.40,
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5-nano-2025-08-07"] = {
          pricing = {
            input = 0.05,
            output = 0.40,
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5-pro"] = {
          pricing = {
            input = 15.0,
            output = 120.0,
          },
        },
        ["gpt-5-pro-2025-10-06"] = {
          pricing = {
            input = 15.0,
            output = 120.0,
          },
        },
        ["gpt-5-search-api"] = {
          pricing = {
            input = 1.25,
            output = 10.0,
          },
        },

        -- GPT-4.1 models
        ["gpt-4.1"] = {
          pricing = {
            input = 2.0,
            output = 8.0,
          },
        },
        ["gpt-4.1-2025-04-14"] = {
          pricing = {
            input = 2.0,
            output = 8.0,
          },
        },
        ["gpt-4.1-mini"] = {
          pricing = {
            input = 0.40,
            output = 1.60,
          },
        },
        ["gpt-4.1-mini-2025-04-14"] = {
          pricing = {
            input = 0.40,
            output = 1.60,
          },
        },
        ["gpt-4.1-nano"] = {
          pricing = {
            input = 0.10,
            output = 0.40,
          },
        },
        ["gpt-4.1-nano-2025-04-14"] = {
          pricing = {
            input = 0.10,
            output = 0.40,
          },
        },

        -- GPT-4o models
        ["gpt-4o"] = {
          pricing = {
            input = 2.5,
            output = 10.0,
          },
        },
        ["gpt-4o-2024-11-20"] = {
          pricing = {
            input = 2.5,
            output = 10.0,
          },
        },
        ["gpt-4o-2024-08-06"] = {
          pricing = {
            input = 2.5,
            output = 10.0,
          },
        },
        ["gpt-4o-2024-05-13"] = {
          pricing = {
            input = 5.0,
            output = 15.0,
          },
        },
        ["gpt-4o-mini"] = {
          pricing = {
            input = 0.15,
            output = 0.60,
          },
        },
        ["gpt-4o-mini-2024-07-18"] = {
          pricing = {
            input = 0.15,
            output = 0.60,
          },
        },
        ["chatgpt-4o-latest"] = { -- (deprecated, retiring Feb 2026)
          pricing = {
            input = 5.0,
            output = 15.0,
          },
        },

        -- o-series models
        ["o1"] = {
          pricing = {
            input = 15.0,
            output = 60.0,
          },
          supports_reasoning_effort = true,
        },
        ["o1-2024-12-17"] = {
          pricing = {
            input = 15.0,
            output = 60.0,
          },
          supports_reasoning_effort = true,
        },
        ["o1-pro"] = {
          pricing = {
            input = 150.0,
            output = 600.0,
          },
        },
        ["o1-pro-2025-03-19"] = {
          pricing = {
            input = 150.0,
            output = 600.0,
          },
        },
        ["o3"] = {
          pricing = {
            input = 2.0,
            output = 8.0,
          },
          supports_reasoning_effort = true,
        },
        ["o3-2025-04-16"] = {
          pricing = {
            input = 2.0,
            output = 8.0,
          },
          supports_reasoning_effort = true,
        },
        ["o3-pro"] = {
          pricing = {
            input = 20.0,
            output = 80.0,
          },
        },
        ["o3-deep-research"] = {
          pricing = {
            input = 10.0,
            output = 40.0,
          },
          supports_reasoning_effort = true,
        },
        ["o3-mini"] = {
          pricing = {
            input = 1.10,
            output = 4.40,
          },
          supports_reasoning_effort = true,
        },
        ["o3-mini-2025-01-31"] = {
          pricing = {
            input = 1.10,
            output = 4.40,
          },
          supports_reasoning_effort = true,
        },
        ["o4-mini"] = {
          pricing = {
            input = 1.10,
            output = 4.40,
          },
          supports_reasoning_effort = true,
        },
        ["o4-mini-2025-04-16"] = {
          pricing = {
            input = 1.10,
            output = 4.40,
          },
          supports_reasoning_effort = true,
        },
        ["o4-mini-deep-research"] = {
          pricing = {
            input = 2.0,
            output = 8.0,
          },
          supports_reasoning_effort = true,
        },

        -- Search and specialized models
        ["gpt-4o-mini-search-preview"] = {
          pricing = {
            input = 0.15,
            output = 0.60,
          },
        },
        ["gpt-4o-search-preview"] = {
          pricing = {
            input = 2.50,
            output = 10.0,
          },
        },
        ["computer-use-preview"] = {
          pricing = {
            input = 3.0,
            output = 12.0,
          },
        },

        -- GPT-4 Turbo models (deprecated, retiring Mar 2026)
        ["gpt-4-turbo"] = {
          pricing = {
            input = 10.0,
            output = 30.0,
          },
        },
        ["gpt-4-turbo-2024-04-09"] = {
          pricing = {
            input = 10.0,
            output = 30.0,
          },
        },
        ["gpt-4-0125-preview"] = { -- (deprecated, retiring Mar 2026)
          pricing = {
            input = 10.0,
            output = 30.0,
          },
        },
        ["gpt-4-1106-preview"] = { -- (deprecated, retiring Mar 2026)
          pricing = {
            input = 10.0,
            output = 30.0,
          },
        },

        -- GPT-4 models (legacy)
        ["gpt-4"] = {
          pricing = {
            input = 30.0,
            output = 60.0,
          },
        },
        ["gpt-4-0613"] = {
          pricing = {
            input = 30.0,
            output = 60.0,
          },
        },
        ["gpt-4-0314"] = { -- (deprecated, retiring Mar 2026)
          pricing = {
            input = 30.0,
            output = 60.0,
          },
        },

        -- GPT-3.5 Turbo models (legacy)
        ["gpt-3.5-turbo"] = {
          pricing = {
            input = 0.50,
            output = 1.50,
          },
        },
        ["gpt-3.5-turbo-0125"] = {
          pricing = {
            input = 0.50,
            output = 1.50,
          },
        },
        ["gpt-3.5-turbo-1106"] = { -- (deprecated, retiring Sep 2026)
          pricing = {
            input = 1.0,
            output = 2.0,
          },
        },
        ["gpt-3.5-turbo-instruct"] = { -- (deprecated, retiring Sep 2026)
          pricing = {
            input = 1.50,
            output = 2.0,
          },
        },
      },
    },
  },
}
