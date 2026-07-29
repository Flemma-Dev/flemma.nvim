---
"@flemma-dev/flemma.nvim": minor
---

Survive `viewoptions+=folds`: while a chat buffer is active, `folds` is stripped from `viewoptions` so `:mkview` no longer persists stale fold state (tweakable via `editing.manage_viewoptions`), and fold settings clobbered by a `:loadview` of a pre-existing view (`foldmethod=manual`, `foldexpr=0`) are now detected and fully re-applied — previously only `foldmethod` was restored, leaving a dead foldexpr and no folds at all.
