---
"@flemma-dev/flemma.nvim": patch
---

The tool label (`FlemmaToolLabel`) — the approved tool-result footer and the label shown in folded message previews — now renders in the muted preview color with an italic accent instead of inheriting the bright `Normal` foreground. It is built by merging the `tool_label` accent onto `tool_preview` (the `progress_accent` pattern), so the approved footer no longer jars against the muted command-preview lines above it. Set a `fg` in `highlights.tool_label` to recolor the label.
