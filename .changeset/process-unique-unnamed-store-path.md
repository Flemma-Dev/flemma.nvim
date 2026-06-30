---
"@flemma-dev/flemma.nvim": patch
---

Unnamed-buffer store paths are now process-unique. The default `tools.store.unnamed_path_format` is `${TMPDIR:-/tmp}/flemma/unnamed/{{ flemma.pid }}/{{ bufnr }}/{{ source }}_{{ name }}_{{ id }}.txt` (previously `…/flemma/unnamed-{{ bufnr }}/…`). Buffer numbers restart in every Neovim instance, so concurrent instances sharing `$TMPDIR` could commingle results in — and delete — each other's unnamed store directories, intermittently dropping the sandbox `urn:flemma:store` grant. `{{ flemma.pid }}` is also available to custom store path formats, and the per-process subtree keeps `$TMPDIR/flemma` to a single `unnamed/` directory.
