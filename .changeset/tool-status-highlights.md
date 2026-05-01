---
"@flemma-dev/flemma.nvim": minor
---

Added distinct syntax highlight groups for every concise status suffix on `**Tool Result:**` headers, mirroring the long-standing `(error)` treatment:

- `(pending)` → `FlemmaToolResultPending` → `DiagnosticInfo`
- `(approved)` → `FlemmaToolResultApproved` → `DiagnosticOk`
- `(rejected)` → `FlemmaToolResultRejected` → `DiagnosticWarn`
- `(denied)` → `FlemmaToolResultDenied` → `DiagnosticError`
- `(aborted)` → `FlemmaToolResultAborted` → `DiagnosticError`
- `(error)` → `FlemmaToolResultError` → `DiagnosticError` (unchanged)

Each is configurable through `highlights.tool_result_<status>` in setup, and each default is set with `default = true` so colourschemes can override without opt-out ceremony. Only the bare-word suffix is decorated — the explicit modeline form `(status=approved sandbox=false)` stays plain, keeping the visual rule "concise = coloured, explicit = metadata."
