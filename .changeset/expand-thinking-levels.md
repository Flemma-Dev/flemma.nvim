---
"@flemma-dev/flemma.nvim": minor
---

Added `minimal` and `max` thinking levels, expanding from 3 to 5 gradations (`minimal | low | medium | high | max`). Budget values for `low` (1024 → 2048) and `high` (32768 → 16384) were adjusted to align with upstream defaults and make room for the new levels. Each provider maps the canonical levels to its API: Anthropic maps `minimal` → `low` and passes `max` on Opus 4.6; OpenAI maps `max` → `xhigh` for GPT-5.2+; Vertex maps `minimal` → `MINIMAL` (Flash) or `LOW` (Pro) and clamps `max` to `HIGH`.
