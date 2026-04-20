---
"@flemma-dev/flemma.nvim": patch
---

Fixed a ghost progress-bar icon that could linger in the gutter after a request completed. Bar's `WinClosed` handler released both float handles (`_float_winid` and `_gutter_winid`) whenever either float was closed externally, but did not close the twin float — leaving it orphaned beyond the reach of any subsequent `_render` or `dismiss()` call. The handler now closes the still-open twin before scheduling the re-render, so the progress bar fully clears when the agent finishes.
