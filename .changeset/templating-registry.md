---
"@flemma-dev/flemma.nvim": minor
---

Template machinery consolidated under `flemma.templating/` namespace. Environment is now extensible via `templating.modules` config. Populators are functions that build the Lua table available to `{{ }}` and `{% %}` blocks. Ships two built-in populators: `stdlib` (standard library) and `iterators` (provides `values()` and `each()` for concise array iteration).
