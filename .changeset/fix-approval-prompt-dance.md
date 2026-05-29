---
"@flemma-dev/flemma.nvim": patch
---

Fixed the approval prompt "dancing" up and down when approving or rejecting a tool. The interactive prompt line and the settled `— <label>` preview footer now swap within a single redraw frame, instead of the prompt disappearing immediately and the footer reappearing on the next `CursorHold`-driven UI pass (~`updatetime` ms later). `approve`/`reject` now refresh the preview synchronously; `approve_all_pending` refreshes once after the batch.
