---
"@flemma-dev/flemma.nvim": minor
---

Bash tool now executes commands in a Neovim terminal buffer instead of a raw job pipe. Output behavior is unchanged but programs that detect TTY on stdout may produce different formatting (e.g., colored output, columnar layout). stdin is redirected from /dev/null to prevent interactive programs from blocking.
