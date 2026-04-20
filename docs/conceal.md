# Conceal Behaviour

Flemma ships with Markdown syntax hidden by default so assistant responses read more like rendered prose and less like raw markup. This is an opt-out: set `editing.conceal = false` (or `nil`, `0`, `"0"`) to restore standard Neovim behaviour.

## The `editing.conceal` option

Accepts a compact `{conceallevel}{concealcursor}` spec that is applied to every chat window:

| Value           | `conceallevel` | `concealcursor` | Effect                                                                    |
| --------------- | -------------- | --------------- | ------------------------------------------------------------------------- |
| `"2n"`          | `2`            | `"n"`           | Default. Hide Markdown in Normal mode; reveal in Insert/Visual/Command.   |
| `"1nvic"`       | `1`            | `"nvic"`        | Replace concealed markup with a placeholder; keep concealed in all modes. |
| `"0"` / `0`     | `0`            | `""`            | Show everything raw.                                                      |
| `"3"` / `3`     | `3`            | `""`            | Hide concealed text entirely, even its placeholder.                       |
| `false` / `nil` | —              | —               | Opt out — Flemma leaves your window options untouched.                    |

The leading digit is parsed as `conceallevel` (`0`–`3`). Any characters that follow populate `concealcursor` — `n`, `v`, `i`, `c` per `:h 'concealcursor'`. Malformed values are silently ignored so a typo doesn't break your buffer.

The override applies on `BufWinEnter` and `FileType chat`, so splitting or re-displaying a chat buffer re-applies it. Non-chat buffers are never touched.

## Why Markdown is concealed by default

Flemma's chat buffer already carries a lot of signal — role markers, tool-use blocks, thinking blocks, folding indicators, rulers, usage bars. Adding visible `**`, `_`, ` ``` `, and similar markup on top makes assistant prose noisier than it needs to be. The `2n` default hides the markup while reading, and reveals it whenever you move the cursor onto the line in Insert or Visual mode so you can still edit precisely.

If you prefer raw Markdown always, `editing.conceal = false` restores the pre-v0.11 behaviour.

## Known interaction: `line_highlights` and concealed cells

Flemma paints per-role backgrounds on chat lines via `line_hl_group` extmarks (`FlemmaLineUser`, `FlemmaLineAssistant`, etc.). At `conceallevel = 1`, Neovim replaces concealed markup with a placeholder character whose background comes from the `Conceal` highlight group — **not** from the `line_hl_group` beneath. The concealed cells therefore render with Neovim's default `Conceal` background, which typically appears as a distinct band against the role-coloured line.

This is a design decision in Neovim's drawing code: `src/nvim/drawline.c` unconditionally assigns `wlv.char_attr = conceal_attr` for concealed cells, discarding the computed attribute stack that would otherwise carry the line background through. The code comment acknowledges the tradeoff explicitly (`no concealing past the end of the line, it interferes with line highlighting`).

We investigated every realistic mitigation:

- `bg = "NONE"` on `Conceal` (or a remapped `FlemmaConceal` via `winhighlight`) falls through to `Normal` — not to `line_hl_group`.
- Higher-priority extmark `hl_group` / `hl_group + hl_eol = true` at priorities 50, 200, 4096 — Conceal still wins for concealed cells.
- Emitting our own `conceal + hl_group` override extmarks at every conceal position — works mechanically, but requires a `nvim_set_decoration_provider` walking treesitter queries on every visible line per redraw to discover where concealment happens. Cost: ~5–20 ms per redraw on warm caches, scaling with viewport size. For a chat plugin that's more complexity than the visual benefit justifies.

**So we don't fix this.** The default of `conceallevel = 2` sidesteps the issue entirely — concealed markup is hidden completely, there is no placeholder cell, and `line_highlights` renders as expected. If you set `conceallevel = 1` yourself (`editing.conceal = "1n"`), you'll see the Neovim band around concealed placeholders; that's expected.

## References (Neovim)

- `:h 'conceallevel'`, `:h 'concealcursor'` — Neovim docs.
- `src/nvim/drawline.c` — the assignment that makes `Conceal` terminal for concealed cells.
- `runtime/lua/vim/treesitter/highlighter.lua` — where the ephemeral `conceal + hl_group` extmark is emitted per capture.
