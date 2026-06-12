---
"@flemma-dev/flemma.nvim": minor
---

Tool capabilities now gate harness parameter injection — `disables_background` prevents `flemma.background` and `disables_save_to` prevents `flemma.save_to` from appearing in a tool's schema. Harness tools declare both, fixing duplicate store files when the LLM copied `flemma.save_to` onto status checks. Existing capabilities renamed to verb_target convention: `emits_template`, `auto_approves_if_sandboxed`.
