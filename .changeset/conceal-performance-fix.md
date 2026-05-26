---
"@flemma-dev/flemma.nvim": minor
---

Eliminated 88% per-keystroke overhead in .chat buffers caused by Neovim's treesitter `conceal_lines` interaction with `conceallevel>=2`. Typing latency drops from ~36ms to ~4ms per keystroke on large buffers. Fenced code block delimiters are now styled with configurable overlay extmarks instead of being hidden via conceal. Adds `experimental.patch_markdown_conceal` config flag and `highlights.fence_label`/`highlights.fence_bar` highlight groups. Frontmatter folds now work at any conceallevel.
