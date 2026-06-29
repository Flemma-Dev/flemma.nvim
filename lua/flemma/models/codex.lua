--- Codex model definitions (ChatGPT subscription).
--- Models available through the chatgpt.com/backend-api/codex/responses endpoint.
--- Pricing reflects OpenAI Platform API rates for usage display; actual cost is
--- covered by the user's ChatGPT subscription.
--- @see flemma.models.Types for type annotations

---@type flemma.models.ProviderModels
return {
  default = "gpt-5.5",
  models = {
    ["gpt-5.5"] = {
      pricing = {
        input = 5.0,
        output = 30.0,
        cache_read = 0.50,
      },
      max_input_tokens = 272000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "xhigh" },
    },
    ["gpt-5.4"] = {
      pricing = {
        input = 2.50,
        output = 15.0,
        cache_read = 0.25,
      },
      max_input_tokens = 272000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "xhigh" },
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
    ["gpt-5.3-codex-spark"] = {
      pricing = {
        input = 1.75,
        output = 14.0,
        cache_read = 0.175,
      },
      max_input_tokens = 128000,
      max_output_tokens = 128000,
      meta = { reasoning_effort = true },
      thinking_effort_map = { minimal = "low", low = "low", medium = "medium", high = "high", max = "xhigh" },
    },
  },
}
