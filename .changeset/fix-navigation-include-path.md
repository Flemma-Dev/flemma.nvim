---
"@flemma-dev/flemma.nvim": patch
---

Fixed gf and LSP goto-definition on {{ include() }} expressions — navigation now uses a path-only include that resolves file paths without compiling target content, fixing failures on files containing literal {{ }} documentation
