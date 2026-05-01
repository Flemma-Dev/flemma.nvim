---
"@flemma-dev/flemma.nvim": patch
---

Fixed tool preview virt_lines showing Normal bg instead of the surrounding role bg when `line_highlights` is enabled. `line_hl_group` on a range extmark does not propagate to virtual lines Neovim inserts inside that range, so the preview row rendered a visible stripe against the `@You` role's tinted background (exposed by the refreshed default palette that gave `@You` a distinct bg). The preview text chunk now combines `FlemmaToolPreview` fg with `FlemmaLineUser` bg, and a padding chunk extends that bg across the text area width to match how `line_hl_group` fills real buffer lines.
