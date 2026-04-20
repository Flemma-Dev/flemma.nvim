---
"@flemma-dev/flemma.nvim": patch
---

Fixed frontmatter block vanishing at `conceallevel >= 1`. Neovim's bundled `markdown/highlights.scm` sets `conceal_lines = ""` on fenced-code-block delimiters — at `conceallevel >= 1` the fence rows render as zero-height. Because the frontmatter fold placeholder was anchored on the now-concealed opening fence, the whole collapsed fold disappeared with it. Flemma now skips the frontmatter fold when `vim.wo.conceallevel >= 1`: the delimiter lines stay concealed, the body renders inline with its language highlighting, and there is no collapsed placeholder to lose. The behaviour is driven by the live window option, so toggling `editing.conceal` at runtime switches modes without a buffer reload. See `docs/conceal.md` "Folds and `conceal_lines`" for the drawline layering that forces this.
