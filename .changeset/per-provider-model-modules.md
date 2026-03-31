---
"@flemma-dev/flemma.nvim": minor
---

Split monolithic models.lua into per-provider data modules under lua/flemma/models/, allowing providers to declare their own model data via metadata.models. Added pricing.high_cost_threshold config option (default 30) replacing the hardcoded constant.
