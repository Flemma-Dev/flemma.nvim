---
"@flemma-dev/flemma.nvim": minor
---

Role markers (`@System:`, `@You:`, `@Assistant:`) now occupy their own line in `.chat` buffers. Old-format files are automatically migrated on load, and a new `:Flemma format` command is available for manual migration. Insert-mode colon auto-newline moves the cursor to a new content line after completing a role marker.
