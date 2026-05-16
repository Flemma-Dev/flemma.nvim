---
"@flemma-dev/flemma.nvim": patch
---

Fixed job ID collisions when reopening `.chat` files from a previous session — duplicate IDs caused job completions to be injected adjacent to the wrong tool_result, corrupting conversation history
