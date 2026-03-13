---
"@flemma-dev/flemma.nvim": patch
---

Fixed frontmatter `auto_approve = {}` (and other table assignments) not blocking sandbox auto-approval of bash. Table policies in frontmatter are now authoritative — tools not explicitly listed require approval, preventing lower-priority resolvers from granting additional approvals.
