---
"@flemma-dev/flemma.nvim": minor
---

Added hooks module for external plugin integration. Flemma now dispatches User autocmds at key lifecycle points: FlemmaRequestSending, FlemmaRequestFinished (with status: completed/cancelled/errored), FlemmaToolExecuting, and FlemmaToolFinished (with status: success/error). Existing autocmds (FlemmaBootComplete, FlemmaSinkCreated, FlemmaSinkDestroyed) migrated to the new hooks infrastructure.
