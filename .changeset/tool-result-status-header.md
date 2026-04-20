---
"@flemma-dev/flemma.nvim": minor
---

Unified tool result status into a parenthesized header suffix. The pending / approved / denied / rejected / aborted lifecycle states and the previously-separate `(error)` marker now all live in the `**Tool Result:**` header via a modeline-parseable suffix — e.g. ``**Tool Result:** `toolu_01` (pending)``.

The old `flemma:tool status=<status>` fenced-block format has been retired. The fence below a tool_result is now always a plain code block. On the AST, `is_error` is gone; `status = "error"` replaces it, and any non-status tokens in the header suffix (e.g. `(status=pending sandbox=false)`) round-trip through a new `meta` field for future metadata support.

No migration is provided. In-flight conversations with old `flemma:tool` placeholders must be upgraded manually — the `(error)` suffix continues to parse correctly, so completed conversations with errored tool results are unaffected. The header suffix also survives `conceallevel = 2` (the default since 0.11), so pending tools remain visibly approvable without disabling markdown conceal.

Also adds `:Flemma tool:approve` and `:Flemma tool:reject [message]` commands mirroring the existing `:Flemma tool:execute` entry point, so the header status can be toggled programmatically or by keymap without hand-editing. `tool:reject` accepts an optional message that is written into the fence body as the rejection reason visible to the model.

Classified as `minor` rather than `major` because the format change is bounded: completed conversations (the `(error)` case and all plain tool results) round-trip unchanged, and the only affected buffers are ones paused mid-approval — a transient state, not persisted work.
