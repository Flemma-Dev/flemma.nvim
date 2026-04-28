---
"@flemma-dev/flemma.nvim": minor
---

First `.chat` buffer open and first `:Flemma send` no longer freeze the editor while resolving credentials (e.g. `gcloud auth print-access-token`). Subprocess resolvers now run async; the send pipeline raises a readiness suspense on cache miss, subscribes to the async work, and retries automatically on completion with a "Resolving …" notification.
