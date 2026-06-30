---
"@flemma-dev/flemma.nvim": minor
---

Updated model definitions and pricing:

- **Anthropic** — added Claude Opus 4.8 (`claude-opus-4-8`): adaptive-thinking-only, $5/$25 per MTok, 1M context, 128K max output (mirrors Opus 4.7's request surface). Removed Claude Opus 4 (`claude-opus-4-0` / `claude-opus-4-20250514`) and Claude Sonnet 4 (`claude-sonnet-4-0` / `claude-sonnet-4-20250514`), which retired on June 15, 2026 and now return errors. Noted Claude Opus 4.1's deprecation (retiring August 5, 2026).
- **Moonshot** — added Kimi K2.7 Code (`kimi-k2.7-code`, $0.95/$4.00) and its faster `kimi-k2.7-code-highspeed` tier ($1.90/$8.00), both with toggleable thinking. Added explicit cache-read pricing to the legacy Moonshot V1 models (uniform, no cache discount).
