---
"@flemma-dev/flemma.nvim": minor
---

Credential resolution no longer blocks the main thread. Subprocess
resolvers (gcloud, secret_tool, keychain) now run async via vim.system's
on_exit form. Code paths that need credentials raise a readiness suspense
on cache miss and resume when the credential becomes available.
