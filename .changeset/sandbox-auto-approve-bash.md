---
"@flemma-dev/flemma.nvim": minor
---

Auto-approve bash tool when sandbox is enabled and a backend is available. A new resolver at priority 50 approves bash calls when sandboxing is active, so sandboxed sessions run without manual approval prompts by default. Users can opt out via `sandbox.auto_approve = false` in config or frontmatter, or by excluding bash from auto-approval in frontmatter (`auto_approve:remove("bash")`).
