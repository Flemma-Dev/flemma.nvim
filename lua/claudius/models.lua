--- Claudius model definitions - DATA ONLY
--- Centralized configuration for all supported models across providers
--- Contains model lists, defaults, and pricing information
--- This file is data-only and contains no functions

return {
  providers = {
    claude = {
      default = "claude-3-7-sonnet-20250219",
      models = {
        -- Claude 3.5 models
        ["claude-3-5-sonnet"] = {
          pricing = {
            input = 3.0, -- $3 per million input tokens
            output = 15.0, -- $15 per million output tokens
          },
        },
        ["claude-3-7-sonnet"] = {
          pricing = {
            input = 3.0, -- $3 per million input tokens
            output = 15.0, -- $15 per million output tokens
          },
        },
        -- Legacy Claude models (no pricing available in current data)
        ["claude-3-opus-20240229"] = {},
        ["claude-3-sonnet-20240229"] = {},
        ["claude-3-haiku-20240307"] = {},
        ["claude-2.1"] = {},
        ["claude-2.0"] = {},
        ["claude-instant-1.2"] = {},
      },
    },

    vertex = {
      default = "gemini-2.5-pro",
      models = {
        -- Gemini 2.5 models
        ["gemini-2.5-pro"] = {
          pricing = {
            input = 1.25, -- $1.25 per million input tokens
            output = 10.0, -- $10.00 per million output tokens
          },
        },
        ["gemini-2.5-pro-preview-06-05"] = {
          pricing = {
            input = 1.25, -- $1.25 per million input tokens
            output = 10.0, -- $10.00 per million output tokens
          },
        },
        ["gemini-2.5-pro-preview-05-06"] = {
          pricing = {
            input = 1.25, -- $1.25 per million input tokens
            output = 10.0, -- $10.00 per million output tokens
          },
        },
        ["gemini-2.5-flash-preview-04-17"] = {
          pricing = {
            input = 0.15, -- $0.15 per million input tokens (text/image/video)
            output = 0.60, -- $0.60 per million output tokens (no thinking)
          },
        },
        -- Gemini 2.0 models
        ["gemini-2.0-flash-001"] = {
          pricing = {
            input = 0.10, -- $0.10 per million input tokens (text/image/video)
            output = 0.40, -- $0.40 per million output tokens
          },
        },
        ["gemini-2.0-flash-lite-001"] = {
          pricing = {
            input = 0.075, -- $0.075 per million input tokens
            output = 0.30, -- $0.30 per million output tokens
          },
        },
        -- Gemini 1.5 models
        ["gemini-1.5-pro-001"] = {
          pricing = {
            input = 1.25, -- $1.25 per million input tokens (standard context <= 128k)
            output = 5.00, -- $5.00 per million output tokens (standard context <= 128k)
          },
        },
        ["gemini-1.5-flash-001"] = {
          pricing = {
            input = 0.075, -- $0.075 per million input tokens (standard context <= 128k)
            output = 0.30, -- $0.30 per million output tokens (standard context <= 128k)
          },
        },
        ["gemini-1.5-flash-8b-001"] = {
          pricing = {
            input = 0.0375, -- $0.0375 per million input tokens (standard context <= 128k)
            output = 0.15, -- $0.15 per million output tokens (standard context <= 128k)
          },
        },
        -- Gemini 1.0 models
        ["gemini-1.0-pro-001"] = {
          pricing = {
            input = 0.00125, -- $0.00125 per million input tokens
            output = 0.00375, -- $0.00375 per million output tokens
          },
        },
        ["gemini-1.0-pro-vision-001"] = {
          pricing = {
            input = 0.00125, -- $0.00125 per million input tokens
            output = 0.00375, -- $0.00375 per million output tokens
          },
        },
        ["gemini-1.0-ultra-001"] = {
          pricing = {
            input = 0.01875, -- $0.01875 per million input tokens
            output = 0.0563, -- $0.0563 per million output tokens
          },
        },
        ["gemini-1.0-ultra-vision-001"] = {
          pricing = {
            input = 0.01875, -- $0.01875 per million input tokens
            output = 0.0563, -- $0.0563 per million output tokens
          },
        },
        -- Additional models without pricing (legacy or experimental)
        ["gemini-2.5-pro-preview-03-25"] = {},
        ["gemini-2.5-pro-exp-03-25"] = {},
        ["gemini-1.5-pro-002"] = {},
        ["gemini-1.5-flash-002"] = {},
        ["gemini-1.0-pro-002"] = {},
        ["text-bison"] = {},
        ["chat-bison"] = {},
        ["codechat-bison"] = {},
      },
    },

    openai = {
      default = "gpt-4o",
      models = {
        -- GPT-4.5 models
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
        },
        ["o1-2024-12-17"] = {
          pricing = {
            input = 15.0, -- $15 per million input tokens
            output = 60.0, -- $60 per million output tokens
          },
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
        },
        ["o3-2025-04-16"] = {
          pricing = {
            input = 2.0, -- $2.00 per million input tokens
            output = 8.0, -- $8.00 per million output tokens
          },
        },
        ["o3-mini"] = {
          pricing = {
            input = 1.10, -- $1.10 per million input tokens
            output = 4.40, -- $4.40 per million output tokens
          },
        },
        ["o3-mini-2025-01-31"] = {
          pricing = {
            input = 1.10, -- $1.10 per million input tokens
            output = 4.40, -- $4.40 per million output tokens
          },
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
        ["chatgpt-4o-latest"] = {
          pricing = {
            input = 5.0, -- $5 per million input tokens
            output = 15.0, -- $15 per million output tokens
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
        -- GPT-3.5 models
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
