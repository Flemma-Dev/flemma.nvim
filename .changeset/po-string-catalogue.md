---
"@flemma-dev/flemma.nvim": patch
---

Externalized conversation messages and tool definition strings into gettext PO catalogues, split by audience: `po/flemma-harness.po` holds model-facing strings (conversation text, tool descriptions — English-only prompt surface), `po/flemma.po` holds user-facing UI strings (the translatable surface, all keys namespaced `ui.*`). Covers the full notify surface: usage, rejection popup, tool actions, :Flemma commands, send-pipeline guards, provider switch/initialize, diagnostics, build-prompt failures, autopilot, presets, hooks, secrets, config validation, sandbox, migration, response truncation, and max-tokens clamping. Rendered strings are unchanged; keys stay unique across the files, enforced when the catalogue loads.
