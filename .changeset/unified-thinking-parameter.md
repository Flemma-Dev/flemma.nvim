---
"@flemma-dev/flemma.nvim": minor
---

Add unified `thinking` parameter that works across all providers — set `thinking = "high"` once instead of provider-specific `thinking_budget` or `reasoning`. The default is `"high"` so all providers use maximum thinking out of the box. Provider-specific parameters still take priority when set. Also promotes `cache_retention` to a general parameter, consolidates `output_has_thoughts` into the capabilities registry, clamps sub-minimum thinking budgets instead of disabling, and supports `flemma.opt.thinking` in frontmatter for provider-agnostic overrides.
