---
"@flemma-dev/flemma.nvim": patch
---

Closed a remaining gap in the ghost progress-bar fix: even after the `WinClosed` twin-close patch, an orphan gutter float could survive when the close path didn't fire `WinClosed` (close inside a non-nested autocmd, `:tabclose` cascade silence) or when `pcall(nvim_win_close)` silently failed. `Bar:dismiss` now force-deletes the bar's scratch buffers, which Neovim resolves by closing every window showing them — reaching orphan floats the bar lost track of.
