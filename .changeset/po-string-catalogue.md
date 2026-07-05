---
"@flemma-dev/flemma.nvim": patch
---

Externalized conversation messages and tool definition strings into gettext PO catalogues, split by audience: `po/flemma-harness.po` holds model-facing strings (conversation text, tool descriptions — English-only prompt surface), `po/flemma.po` holds user-facing UI strings (the translatable surface, all keys namespaced `ui.*`, covering the usage, rejection-popup, tool-action, :Flemma command, send-pipeline guard, provider switch/initialize, and diagnostics notifications). Rendered strings are unchanged; keys stay unique across the files, enforced when the catalogue loads.
