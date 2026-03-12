---
"@flemma-dev/flemma.nvim": patch
---

Fixed `:Flemma status` showing sandbox-auto-approved tools (e.g. bash) as "require approval" even when sandbox was active. The approval section now uses the actual resolver chain, so all approval sources (config, frontmatter, sandbox, community resolvers) are reflected accurately.
