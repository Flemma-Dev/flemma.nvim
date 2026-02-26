---
"@flemma-dev/flemma.nvim": minor
---

Auto-approve bash tool when sandbox is enabled and a backend is available. A new resolver at priority 25 approves bash calls when sandboxing is active, so sandboxed sessions run without manual approval prompts by default. Users can opt out via `tools.auto_approve_sandboxed = false` in config, or by excluding bash from auto-approval in frontmatter (`auto_approve:remove("bash")`).
