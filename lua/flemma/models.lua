--- Flemma model definitions - DATA ONLY
--- Centralized configuration for all supported models across providers
--- Contains model lists, defaults, and pricing information
--- This file is data-only and contains no functions

return {
  providers = {
    claude = {
      default = "claude-sonnet-4-5",
      models = {
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

        -- Claude Sonnet 3.7
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

        -- Claude Haiku 3.5
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
      models = {
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

        -- Gemini 2.5 Flash Lite models
        ["gemini-2.5-flash-lite"] = {
          pricing = {
            input = 0.10,
            output = 0.40,
          },
        },

        -- Gemini 2.0 Flash models
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

        -- Gemini 2.0 Flash Lite models
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
      models = {
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
        ["chatgpt-4o-latest"] = {
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
        ["o1-mini"] = {
          pricing = {
            input = 1.10,
            output = 4.40,
          },
        },
        ["o1-mini-2024-09-12"] = {
          pricing = {
            input = 1.10,
            output = 4.40,
          },
        },
        ["o3"] = {
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
        ["o4-mini"] = {
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
        ["codex-mini-latest"] = {
          pricing = {
            input = 1.50,
            output = 6.0,
          },
        },

        -- GPT-4 Turbo models (legacy)
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
        ["gpt-4-0125-preview"] = {
          pricing = {
            input = 10.0,
            output = 30.0,
          },
        },
        ["gpt-4-1106-preview"] = {
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
        ["gpt-4-0314"] = {
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
        ["gpt-3.5-turbo-1106"] = {
          pricing = {
            input = 1.0,
            output = 2.0,
          },
        },
        ["gpt-3.5-turbo-0613"] = {
          pricing = {
            input = 1.50,
            output = 2.0,
          },
        },
        ["gpt-3.5-0301"] = {
          pricing = {
            input = 1.50,
            output = 2.0,
          },
        },
        ["gpt-3.5-turbo-instruct"] = {
          pricing = {
            input = 1.50,
            output = 2.0,
          },
        },
        ["gpt-3.5-turbo-16k-0613"] = {
          pricing = {
            input = 3.0,
            output = 4.0,
          },
        },
      },
    },
  },
}
