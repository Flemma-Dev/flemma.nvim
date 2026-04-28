---
"@flemma-dev/flemma.nvim": minor
---

:Flemma send no longer freezes the editor while waiting for first-time
credential resolution (e.g. gcloud auth print-access-token). The send
loop now subscribes to async work and resends automatically on
completion, with a "Resolving …" notification while waiting.
