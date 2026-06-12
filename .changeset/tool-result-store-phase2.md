---
"@flemma-dev/flemma.nvim": minor
---

Added `flemma.save_to` and renamed the background parameter to `flemma.background`.

Every tool schema now carries an optional `flemma.save_to` parameter: the model can redirect full tool output to a file and the conversation receives a short preview plus the saved path instead. The `bash` tool exports `$FLEMMA_TOOLS_STORE_PATH` pointing at the conversation's store directory, which is sandbox-writable by default via the new `urn:flemma:store` policy variable. The background-execution parameter is now namespaced as `flemma.background`; both harness parameters are stripped from tool input before execution and respect strict-mode schema invariants.

`tools.store.materialize` now defaults to `false` — only truncation overflow and explicit `flemma.save_to` redirects write to the store unless opted in.
