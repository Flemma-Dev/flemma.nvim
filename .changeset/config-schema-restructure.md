---
"@flemma-dev/flemma.nvim": minor
---

Restructured config schema: moved orphaned top-level keys under their parent groups.

**Migration:** rename the following keys in your `setup()` call:

| Old path      | New path                |
| ------------- | ----------------------- |
| `defaults`    | `highlights.defaults`   |
| `role_style`  | `highlights.role_style` |
| `pricing`     | `ui.pricing`            |
| `statusline`  | `ui.statusline`         |
| `text_object` | `keymaps.text_object`   |
