--- Flemma model definitions - DATA ONLY
--- Centralized configuration for all supported models across providers
--- Contains model lists, defaults, and pricing information
--- This file is data-only and contains no functions

return {
  providers = {
    claude = {
      default = "claude-sonnet-4-0",
      models = {
        -- Claude Opus 4.1 (as of Sep 2025)
        ["claude-opus-4-1"] = {
          pricing = {
            input = 15.0, -- $15 per million input tokens
            output = 75.0, -- $75 per million output tokens
          },
        },
        ["claude-opus-4-1-20250805"] = {
          pricing = {
            input = 15.0, -- $15 per million input tokens
            output = 75.0, -- $75 per million output tokens
          },
        },

        ["claude-opus-4-0"] = {
          pricing = {
            input = 15.0, -- $15 per million input tokens
            output = 75.0, -- $75 per million output tokens
          },
        },
        ["claude-opus-4-20250514"] = {
          pricing = {
            input = 15.0, -- $15 per million input tokens
            output = 75.0, -- $75 per million output tokens
          },
        },

        ["claude-sonnet-4-0"] = {
          pricing = {
            input = 3.0, -- $3 per million input tokens
            output = 15.0, -- $15 per million output tokens
          },
        },
        ["claude-sonnet-4-20250514"] = {
          pricing = {
            input = 3.0, -- $3 per million input tokens
            output = 15.0, -- $15 per million output tokens
          },
        },

        -- Claude Sonnet 3.7
        ["claude-3-7-sonnet-latest"] = {
          pricing = {
            input = 3.0, -- $3 per million input tokens
            output = 15.0, -- $15 per million output tokens
          },
        },
        ["claude-3-7-sonnet-20250219"] = {
          pricing = {
            input = 3.0, -- $3 per million input tokens
            output = 15.0, -- $15 per million output tokens
          },
        },

        -- Claude Haiku 3.5
        ["claude-3-5-haiku-latest"] = {
          pricing = {
            input = 0.80, -- $0.80 per million input tokens
            output = 4.0, -- $4 per million output tokens
          },
        },
        ["claude-3-5-haiku-latest"] = {
          pricing = {
            input = 0.80, -- $0.80 per million input tokens
            output = 4.0, -- $4 per million output tokens
          },
        },
        ["claude-3-5-haiku-20241022"] = {
          pricing = {
            input = 0.80, -- $0.80 per million input tokens
            output = 4.0, -- $4 per million output tokens
          },
        },

        -- Claude Haiku 3
        ["claude-3-haiku-20240307"] = {
          pricing = {
            input = 0.25, -- $0.25 per million input tokens
            output = 1.25, -- $1.25 per million output tokens
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
            input = 1.25, -- $1.25 per million input tokens (<=200K context)
            output = 10.0, -- $10.00 per million output tokens (<=200K context)
          },
        },

        -- Gemini 2.5 Flash models
        ["gemini-2.5-flash"] = {
          pricing = {
            input = 0.30, -- $0.30 per million input tokens (text/image/video)
            output = 2.50, -- $2.50 per million output tokens
          },
        },
        ["gemini-live-2.5-flash"] = {
          pricing = {
            input = 0.50, -- $0.50 per million input tokens (text)
            output = 2.0, -- $2.00 per million output tokens
          },
        },

        ["gemini-live-2.5-flash-preview-native-audio"] = {
          pricing = {
            input = 0.50, -- $0.50 per million input tokens
            output = 2.0, -- $2.00 per million output tokens
          },
        },

        -- Gemini 2.5 Flash Lite models
        ["gemini-2.5-flash-lite"] = {
          pricing = {
            input = 0.10, -- $0.10 per million input tokens (text/image/video)
            output = 0.40, -- $0.40 per million output tokens
          },
        },

        -- Gemini 2.0 Flash models
        ["gemini-2.0-flash"] = {
          pricing = {
            input = 0.15, -- $0.15 per million input tokens (text/image/video)
            output = 0.60, -- $0.60 per million output tokens
          },
        },
        ["gemini-2.0-flash-001"] = {
          pricing = {
            input = 0.15, -- $0.15 per million input tokens (text/image/video)
            output = 0.60, -- $0.60 per million output tokens
          },
        },

        ["gemini-2.0-flash-live-preview-04-09"] = {
          pricing = {
            input = 0.50, -- $0.50 per million input tokens (text)
            output = 2.0, -- $2.00 per million output tokens
          },
        },

        -- Gemini 2.0 Flash Lite models
        ["gemini-2.0-flash-lite"] = {
          pricing = {
            input = 0.075, -- $0.075 per million input tokens
            output = 0.30, -- $0.30 per million output tokens
          },
        },
        ["gemini-2.0-flash-lite-001"] = {
          pricing = {
            input = 0.075, -- $0.075 per million input tokens
            output = 0.30, -- $0.30 per million output tokens
          },
        },
      },
    },

    openai = {
      default = "gpt-5",
      models = {
        -- GPT-5 models (as of Sep 2025)
        ["gpt-5"] = {
          pricing = {
            input = 1.25, -- $1.25 per million input tokens
            output = 10.0, -- $10 per million output tokens
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5-mini"] = {
          pricing = {
            input = 0.25, -- $0.25 per million input tokens
            output = 2.0, -- $2 per million output tokens
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5-nano"] = {
          pricing = {
            input = 0.05, -- $0.05 per million input tokens
            output = 0.40, -- $0.40 per million output tokens
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5-chat-latest"] = {
          pricing = {
            input = 1.25, -- $1.25 per million input tokens
            output = 10.0, -- $10 per million output tokens
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5-2025-08-07"] = {
          pricing = {
            input = 1.25, -- $1.25 per million input tokens
            output = 10.0, -- $10 per million output tokens
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5-mini-2025-08-07"] = {
          pricing = {
            input = 0.25, -- $0.25 per million input tokens
            output = 2.0, -- $2 per million output tokens
          },
          supports_reasoning_effort = true,
        },
        ["gpt-5-nano-2025-08-07"] = {
          pricing = {
            input = 0.05, -- $0.05 per million input tokens
            output = 0.40, -- $0.40 per million output tokens
          },
          supports_reasoning_effort = true,
        },

        -- GPT-4.5 models (Preview, to be deprecated July 2025)
        ["gpt-4.5-preview"] = {
          pricing = {
            input = 75.0, -- $75 per million input tokens
            output = 150.0, -- $150 per million output tokens
          },
        },
        ["gpt-4.5-preview-2025-02-27"] = {
          pricing = {
            input = 75.0, -- $75 per million input tokens
            output = 150.0, -- $150 per million output tokens
          },
        },

        -- GPT-4.1 models (stable as of Sep 2025)
        ["gpt-4.1"] = {
          pricing = {
            input = 2.0, -- $2.00 per million input tokens
            output = 8.0, -- $8.00 per million output tokens
          },
        },
        ["gpt-4.1-mini"] = {
          pricing = {
            input = 0.40, -- $0.40 per million input tokens
            output = 1.60, -- $1.60 per million output tokens
          },
        },
        ["gpt-4.1-nano"] = {
          pricing = {
            input = 0.10, -- $0.10 per million input tokens
            output = 0.40, -- $0.40 per million output tokens
          },
        },

        -- GPT-4o models
        ["gpt-4o"] = {
          pricing = {
            input = 2.5, -- $2.50 per million input tokens
            output = 10.0, -- $10 per million output tokens
          },
        },
        ["gpt-4o-2024-08-06"] = {
          pricing = {
            input = 2.5, -- $2.50 per million input tokens
            output = 10.0, -- $10 per million output tokens
          },
        },
        ["gpt-4o-mini"] = {
          pricing = {
            input = 0.15, -- $0.15 per million input tokens
            output = 0.60, -- $0.60 per million output tokens
          },
        },
        ["gpt-4o-mini-2024-07-18"] = {
          pricing = {
            input = 0.15, -- $0.15 per million input tokens
            output = 0.60, -- $0.60 per million output tokens
          },
        },
        ["chatgpt-4o-latest"] = {
          pricing = {
            input = 5.0, -- $5 per million input tokens
            output = 15.0, -- $15 per million output tokens
          },
        },

        -- GPT-4o Audio models
        ["gpt-4o-audio-preview"] = {
          pricing = {
            input = 2.5, -- $2.50 per million input tokens
            output = 10.0, -- $10 per million output tokens
          },
        },
        ["gpt-4o-audio-preview-2024-12-17"] = {
          pricing = {
            input = 2.5, -- $2.50 per million input tokens
            output = 10.0, -- $10 per million output tokens
          },
        },
        ["gpt-4o-mini-audio-preview"] = {
          pricing = {
            input = 0.15, -- $0.15 per million input tokens
            output = 0.60, -- $0.60 per million output tokens
          },
        },
        ["gpt-4o-mini-audio-preview-2024-12-17"] = {
          pricing = {
            input = 0.15, -- $0.15 per million input tokens
            output = 0.60, -- $0.60 per million output tokens
          },
        },

        -- GPT-4o Realtime models
        ["gpt-4o-realtime-preview"] = {
          pricing = {
            input = 5.0, -- $5 per million input tokens
            output = 20.0, -- $20 per million output tokens
          },
        },
        ["gpt-4o-realtime-preview-2024-12-17"] = {
          pricing = {
            input = 5.0, -- $5 per million input tokens
            output = 20.0, -- $20 per million output tokens
          },
        },
        ["gpt-4o-mini-realtime-preview"] = {
          pricing = {
            input = 0.60, -- $0.60 per million input tokens
            output = 2.40, -- $2.40 per million output tokens
          },
        },
        ["gpt-4o-mini-realtime-preview-2024-12-17"] = {
          pricing = {
            input = 0.60, -- $0.60 per million input tokens
            output = 2.40, -- $2.40 per million output tokens
          },
        },

        -- o-series models
        ["o1"] = {
          pricing = {
            input = 15.0, -- $15 per million input tokens
            output = 60.0, -- $60 per million output tokens
          },
          supports_reasoning_effort = true,
        },
        ["o1-2024-12-17"] = {
          pricing = {
            input = 15.0, -- $15 per million input tokens
            output = 60.0, -- $60 per million output tokens
          },
          supports_reasoning_effort = true,
        },
        ["o1-pro"] = {
          pricing = {
            input = 150.0, -- $150 per million input tokens
            output = 600.0, -- $600 per million output tokens
          },
        },
        ["o1-pro-2025-03-19"] = {
          pricing = {
            input = 150.0, -- $150 per million input tokens
            output = 600.0, -- $600 per million output tokens
          },
        },
        ["o3"] = {
          pricing = {
            input = 2.0, -- $2.00 per million input tokens
            output = 8.0, -- $8.00 per million output tokens
          },
          supports_reasoning_effort = true,
        },
        ["o3-2025-04-16"] = {
          pricing = {
            input = 2.0, -- $2.00 per million input tokens
            output = 8.0, -- $8.00 per million output tokens
          },
          supports_reasoning_effort = true,
        },
        ["o3-mini"] = {
          pricing = {
            input = 1.10, -- $1.10 per million input tokens
            output = 4.40, -- $4.40 per million output tokens
          },
          supports_reasoning_effort = true,
        },
        ["o3-mini-2025-01-31"] = {
          pricing = {
            input = 1.10, -- $1.10 per million input tokens
            output = 4.40, -- $4.40 per million output tokens
          },
          supports_reasoning_effort = true,
        },
        ["o1-mini"] = {
          pricing = {
            input = 1.10, -- $1.10 per million input tokens
            output = 4.40, -- $4.40 per million output tokens
          },
        },
        ["o1-mini-2024-09-12"] = {
          pricing = {
            input = 1.10, -- $1.10 per million input tokens
            output = 4.40, -- $4.40 per million output tokens
          },
        },
        ["o1-preview"] = {
          pricing = {
            input = 15.0, -- $15 per million input tokens
            output = 60.0, -- $60 per million output tokens
          },
        },
        ["o4-mini"] = {
          pricing = {
            input = 4.0, -- $4.00 per million input tokens
            output = 16.0, -- $16.00 per million output tokens
          },
          supports_reasoning_effort = true,
        },

        -- Search and specialized models
        ["gpt-4o-mini-search-preview"] = {
          pricing = {
            input = 0.15, -- $0.15 per million input tokens
            output = 0.60, -- $0.60 per million output tokens
          },
        },
        ["gpt-4o-mini-search-preview-2025-03-11"] = {
          pricing = {
            input = 0.15, -- $0.15 per million input tokens
            output = 0.60, -- $0.60 per million output tokens
          },
        },
        ["gpt-4o-search-preview"] = {
          pricing = {
            input = 2.50, -- $2.50 per million input tokens
            output = 10.0, -- $10 per million output tokens
          },
        },
        ["gpt-4o-search-preview-2025-03-11"] = {
          pricing = {
            input = 2.50, -- $2.50 per million input tokens
            output = 10.0, -- $10 per million output tokens
          },
        },
        ["computer-use-preview"] = {
          pricing = {
            input = 3.0, -- $3 per million input tokens
            output = 12.0, -- $12 per million output tokens
          },
        },
        ["computer-use-preview-2025-03-11"] = {
          pricing = {
            input = 3.0, -- $3 per million input tokens
            output = 12.0, -- $12 per million output tokens
          },
        },

        -- GPT-4 Turbo models
        ["gpt-4-turbo"] = {
          pricing = {
            input = 10.0, -- $10 per million input tokens
            output = 30.0, -- $30 per million output tokens
          },
        },
        ["gpt-4-turbo-2024-04-09"] = {
          pricing = {
            input = 10.0, -- $10 per million input tokens
            output = 30.0, -- $30 per million output tokens
          },
        },
        ["gpt-4-0125-preview"] = {
          pricing = {
            input = 10.0, -- $10 per million input tokens
            output = 30.0, -- $30 per million output tokens
          },
        },
        ["gpt-4-1106-preview"] = {
          pricing = {
            input = 10.0, -- $10 per million input tokens
            output = 30.0, -- $30 per million output tokens
          },
        },
        ["gpt-4-1106-vision-preview"] = {
          pricing = {
            input = 10.0, -- $10 per million input tokens
            output = 30.0, -- $30 per million output tokens
          },
        },

        -- GPT-4 models
        ["gpt-4"] = {
          pricing = {
            input = 30.0, -- $30 per million input tokens
            output = 60.0, -- $60 per million output tokens
          },
        },
        ["gpt-4-0613"] = {
          pricing = {
            input = 30.0, -- $30 per million input tokens
            output = 60.0, -- $60 per million output tokens
          },
        },
        ["gpt-4-0314"] = {
          pricing = {
            input = 30.0, -- $30 per million input tokens
            output = 60.0, -- $60 per million output tokens
          },
        },
        ["gpt-4-32k"] = {
          pricing = {
            input = 60.0, -- $60 per million input tokens
            output = 120.0, -- $120 per million output tokens
          },
        },

        -- GPT-3.5 Turbo models
        ["gpt-3.5-turbo"] = {
          pricing = {
            input = 0.50, -- $0.50 per million input tokens
            output = 1.50, -- $1.50 per million output tokens
          },
        },
        ["gpt-3.5-turbo-0125"] = {
          pricing = {
            input = 0.50, -- $0.50 per million input tokens
            output = 1.50, -- $1.50 per million output tokens
          },
        },
        ["gpt-3.5-turbo-1106"] = {
          pricing = {
            input = 1.0, -- $1 per million input tokens
            output = 2.0, -- $2 per million output tokens
          },
        },
        ["gpt-3.5-turbo-0613"] = {
          pricing = {
            input = 1.50, -- $1.50 per million input tokens
            output = 2.0, -- $2 per million output tokens
          },
        },
        ["gpt-3.5-0301"] = {
          pricing = {
            input = 1.50, -- $1.50 per million input tokens
            output = 2.0, -- $2 per million output tokens
          },
        },
        ["gpt-3.5-turbo-instruct"] = {
          pricing = {
            input = 1.50, -- $1.50 per million input tokens
            output = 2.0, -- $2 per million output tokens
          },
        },
        ["gpt-3.5-turbo-16k-0613"] = {
          pricing = {
            input = 3.0, -- $3 per million input tokens
            output = 4.0, -- $4 per million output tokens
          },
        },
      },
    },
  },
}
