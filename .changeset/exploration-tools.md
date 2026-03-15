---
"@flemma-dev/flemma.nvim": minor
---

Added three exploration tools for LLM-powered codebase navigation: `grep` (content search with rg/grep fallback, --json match counting, per-line truncation), `find` (file discovery with fd/git-ls-files/find fallback, recursive patterns, configurable excludes), and `ls` (directory listing with depth control). All tools use existing truncation, sink, and sandbox infrastructure. Executor cwd resolution generalized from bash-specific to per-tool.
