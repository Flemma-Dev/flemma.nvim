---
"@flemma-dev/flemma.nvim": patch
---

Reordered the pending tool approval prompt so the tool label leads: `— <label>  ⏸ N/M · <hints>`. The label now occupies the same fixed position it has after approval (`— <label>`), so approving a tool no longer shifts the label from the middle of the prompt to the front. Pure field reorder — highlight groups and approval logic are unchanged.
