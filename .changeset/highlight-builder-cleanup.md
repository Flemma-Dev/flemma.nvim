---
"@flemma-dev/flemma.nvim": patch
---

Eliminate all raw `nvim_get_hl`/`nvim_set_hl` calls from `highlight.lua`, fully delegating to `hl.lua` builder ops. Add `h.default(attr)` constructor for Normal-with-fallback resolution. Expose `highlights.tool_label` and `highlights.progress_accent` as configurable schema entries.
