---
"@flemma-dev/flemma.nvim": patch
---

Fixed fold auto-close race condition where thinking blocks and tool blocks would remain unfolded ~10% of the time due to silent foldclose failures being permanently marked as successful. Also fixed folds not being applied when returning to a chat buffer after switching tabs during streaming.
