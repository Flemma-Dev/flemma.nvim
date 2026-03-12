---
"@flemma-dev/flemma.nvim": minor
---

Added persistent progress indicator showing character count, elapsed time, and phase-specific animation throughout the full request lifecycle including tool use buffering. The indicator appears as a floating window at the bottom of the chat window when the progress line is off-screen, with spinner icon placed in the gutter to match notification bar layout. Configurable via `progress.highlight` and `progress.zindex`.
