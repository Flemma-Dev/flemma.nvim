---
"@flemma-dev/flemma.nvim": patch
---

Corrected three model limits that were wrong against provider documentation:

- `gpt-5-pro` reserves 272K of its 400K context window for output, leaving 128K for input — the inverse of every other GPT-5 model. Its `max_input_tokens` had been set to 272000 (the output figure), so the context indicator showed a request as half-full when it was already over the limit.
- `gemini-2.5-pro`'s thinking budget floor is 128, not 1. Only 2.5 Flash accepts a budget of 1; thinking cannot be turned off on 2.5 Pro at all.
- `gpt-5.3-codex-spark`'s input limit is 96000 (its 128K context window minus the 32K output reservation), not 100000. Its entry now records that it is a research preview with restricted API access and that its pricing mirrors `gpt-5.3-codex` rather than a published rate.

Also dropped `thinking_budgets` from the Gemini 3 entries that still carried them. Google publishes a `thinkingBudget` range for Gemini 2.5 only, Gemini 3 uses `thinkingLevel`, and a request carrying both parameters returns an error. The budgets were never sent — but they clamped numeric budgets before mapping them to a level, so the same configured budget resolved to a different `thinkingLevel` on `gemini-3-flash-preview` than on `gemini-3.5-flash`.
