---
"@flemma-dev/flemma.nvim": minor
---

Secrets resolvers now own their config schema (`metadata.config_schema`), composed into the `secrets` config namespace via DISCOVER — the same pattern provider adapters and sandbox backends use. Defaults materialize when a resolver registers, and custom resolvers can declare their own `secrets.<name>` options. `secrets.chatgpt.auth_file` is now a configurable `setup()` key (effective when the experimental Codex adapter is loaded, which self-registers the ChatGPT resolver).
