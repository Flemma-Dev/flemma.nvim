---
"@flemma-dev/flemma.nvim": minor
---

Added experimental Codex provider for ChatGPT subscription authentication. Users with a ChatGPT subscription can now use their existing `codex login` token to drive Flemma, without needing a separate OpenAI Platform API key.

Enable via `providers.modules = { "flemma.provider.adapters.experimental.codex" }` in your Flemma setup config.

Also includes:

- `providers.modules` config key for registering non-built-in provider adapters
- `provider/model` slash syntax (`codex/gpt-5.5`) for `:Flemma switch`, presets, and frontmatter
- `openai_responses.lua` intermediate base for Responses API wire format reuse
- `resolve_credential()` on provider base for metadata-rich credential resolution
