---
"@flemma-dev/flemma.nvim": patch
---

Fixed two conceal-related bugs. (1) Opening a `.chat` buffer was mutating the user's **global** `conceallevel` / `concealcursor` because `nvim_set_option_value` with only a `win` key behaves like `:set`, not `:setlocal`; Flemma now passes `scope = "local"` so chat settings stay window-scoped. (2) Splitting or `:tabedit`-ing from a chat window copied chat's `conceallevel` into the new (non-chat) window because Neovim duplicates window-local options on window creation. Flemma now restores the global conceal on the new window when a non-chat buffer lands there with chat's conceal fingerprint still applied.
