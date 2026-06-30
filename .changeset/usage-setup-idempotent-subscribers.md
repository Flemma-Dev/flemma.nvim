---
"@flemma-dev/flemma.nvim": patch
---

Repeated `setup()` calls no longer stack duplicate usage-bar hook subscribers — each `usage.setup()` now disposes its previous `request:finished`/`buffer:destroyed` subscriptions before re-registering.
