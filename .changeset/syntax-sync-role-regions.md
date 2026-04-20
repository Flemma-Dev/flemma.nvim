---
"@flemma-dev/flemma.nvim": patch
---

Fixed inconsistent `FlemmaToolUseTitle` / `FlemmaToolResultTitle` highlighting where only the first `**Tool Use:**` / `**Tool Result:**` header in a role block received the dedicated highlight while subsequent ones were rendered as plain text. Vim's default syntax sync (`maxlines=60`) could leave the outer `FlemmaSystem` / `FlemmaUser` / `FlemmaAssistant` region unmatched after a fenced code block between headers, so the contained `FlemmaToolUse` / `FlemmaToolResult` regions had nowhere to anchor. Added `syntax sync match … grouphere` directives on the three role markers so every header now picks up its title highlight regardless of position. The issue became visually obvious once `editing.conceal = "2nv"` hid the `**` markers, but was latent in all prior versions.
