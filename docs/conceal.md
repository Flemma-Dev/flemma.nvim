# Conceal Behaviour

Flemma ships with Markdown syntax hidden by default so assistant responses read more like rendered prose and less like raw markup. This is an opt-out: set `editing.conceal = false` (or `nil`, `0`, `"0"`) to restore standard Neovim behaviour.

## The `editing.conceal` option

Accepts a compact `{conceallevel}{concealcursor}` spec that is applied to every chat window:

| Value           | `conceallevel` | `concealcursor` | Effect                                                                       |
| --------------- | -------------- | --------------- | ---------------------------------------------------------------------------- |
| `"2nv"`         | `2`            | `"nv"`          | Default. Hide Markdown in Normal and Visual modes; reveal in Insert/Command. |
| `"2n"`          | `2`            | `"n"`           | Hide Markdown in Normal mode; reveal in Insert/Visual/Command.               |
| `"1nvic"`       | `1`            | `"nvic"`        | Replace concealed markup with a placeholder; keep concealed in all modes.    |
| `"0"` / `0`     | `0`            | `""`            | Show everything raw.                                                         |
| `"3"` / `3`     | `3`            | `""`            | Hide concealed text entirely, even its placeholder.                          |
| `false` / `nil` | —              | —               | Opt out — Flemma leaves your window options untouched.                       |

The leading digit is parsed as `conceallevel` (`0`–`3`). Any characters that follow populate `concealcursor` — `n`, `v`, `i`, `c` per `:h 'concealcursor'`. Malformed values are silently ignored so a typo doesn't break your buffer.

The override applies on `BufRead`/`BufNewFile` (the first time a `.chat` buffer is loaded) and on `FileType chat`, so newly opened chat buffers always pick up the configured value. A separate `BufWinEnter` autocmd runs in the **other** direction: when a non-chat buffer lands in a window that was previously displaying a chat buffer (and therefore still carries the chat conceal fingerprint), Flemma restores the global conceal defaults so your other windows aren't left with chat's settings.

## Why Markdown is concealed by default

Flemma's chat buffer already carries a lot of signal — role markers, tool-use blocks, thinking blocks, folding indicators, rulers, usage bars. Adding visible `**`, `_`, ` ``` `, and similar markup on top makes assistant prose noisier than it needs to be. The `2nv` default hides the markup while reading and while selecting, and reveals it whenever you move the cursor onto the line in Insert or Command mode so you can still edit precisely.

If you prefer raw Markdown always, `editing.conceal = false` restores the pre-v0.11 behaviour.

## Fence overlay system

Code fences inside `.chat` buffers are drawn as styled overlays — the language label sits on the top fence, a delimiter bar on the bottom — instead of being hidden completely by Neovim's default conceal. You get a clean visual marker without losing the fence as a structural row in the buffer (which matters for folding; see [Limitations](#limitations)). The system is controlled by `experimental.patch_markdown_conceal` (default `true`).

When enabled:

- Fence delimiters render as overlay labels only when `conceallevel >= 2`; toggle conceal off and the raw delimiters return.
- Style the label and the bar via `highlights.fence_label` and `highlights.fence_bar`.
- Overlays stay readable when your cursor is on the fence line (contrast-adjusted against `CursorLine`).

Set `experimental.patch_markdown_conceal = false` to restore Neovim's standard fence concealing.

<details>
<summary>Why this exists (performance)</summary>

Neovim's bundled markdown treesitter queries use `conceal_lines` to hide fenced-delimiter lines. At `conceallevel >= 2` this interacts poorly with treesitter highlighting, adding ~36ms of per-keystroke overhead on large buffers. Replacing it with overlay extmarks at the decoration-provider layer brings typing latency down to ~4ms per keystroke. Markdown buffers in the same session keep their native fence concealing via automatic highlighter restoration — only `.chat` buffers route through the overlay system.

</details>

## Toggling conceal at runtime

The default keymaps follow Neovim's `yo`/`[o`/`]o` option-toggle convention:

| Key   | Action                                           | Config key                      |
| ----- | ------------------------------------------------ | ------------------------------- |
| `yoe` | Toggle `conceallevel` between configured and `0` | `keymaps.normal.conceal_toggle` |
| `]oe` | Enable conceal (set to configured level)         | `keymaps.normal.conceal_on`     |
| `[oe` | Disable conceal (set to `0`)                     | `keymaps.normal.conceal_off`    |

You can remap any of them or disable with `false`. They are only registered when `editing.conceal` is active.

If you manage your own keymaps (`keymaps.enabled = false`), a one-liner does the same thing:

```vim
:nnoremap yoe :setlocal conceallevel=<C-R>=&conceallevel == 0 ? '2' : '0'<CR><CR>
```

Note that this hard-codes level `2` — if your `editing.conceal` uses a different level, adjust accordingly.

## Limitations

A couple of edge cases where `conceallevel` interacts with other Neovim subsystems in ways Flemma can't paper over. Each one has a sensible default that avoids the issue — these notes are for when you deviate from defaults.

### `line_highlights` at `conceallevel = 1`

At `conceallevel = 1`, Neovim replaces concealed markup with a placeholder character whose background comes from Neovim's `Conceal` highlight group — **not** from the per-role `line_hl_group` Flemma paints onto chat lines. The concealed cells therefore render with a distinct band against the role-coloured line.

**Workaround:** the default of `conceallevel = 2` sidesteps this entirely. If you explicitly set `editing.conceal = "1n"`, expect the band around concealed placeholders.

<details>
<summary>Why this can't be fixed in Flemma</summary>

This is a design decision in Neovim's drawing code (`src/nvim/drawline.c`): concealed cells are unconditionally assigned the `Conceal` attribute, discarding the line-background attribute stack. The code comment acknowledges the tradeoff explicitly (`no concealing past the end of the line, it interferes with line highlighting`).

We investigated every realistic mitigation:

- `bg = "NONE"` on `Conceal` (or a remapped `FlemmaConceal` via `winhighlight`) falls through to `Normal`, not to `line_hl_group`.
- Higher-priority extmark `hl_group` overrides (priorities 50, 200, 4096, with and without `hl_eol = true`) — Conceal still wins for concealed cells.
- Emitting our own `conceal + hl_group` override extmarks at every conceal position works mechanically, but requires walking treesitter queries on every visible line per redraw to discover where concealment happens. Cost: ~5–20 ms per redraw on warm caches, scaling with viewport size. More complexity than the visual benefit justifies.

</details>

### Folds inside concealed fence lines

Neovim's bundled markdown treesitter queries hide entire fenced-delimiter lines (` ```lua `, ` ``` `) at `conceallevel >= 1`. Because Flemma registers `chat` as a markdown variant, this applies to every fenced block inside `.chat` buffers — frontmatter fences and tool-use/tool-result code blocks alike. Inside a message body that's fine: the fence vanishes and the content keeps rendering. The awkward case is folding the frontmatter region: Neovim draws the fold placeholder on the fold's first line, which would now be a zero-height concealed fence, so the whole folded region would vanish from the screen.

**What we ship:** with `experimental.patch_markdown_conceal = true` (default), Flemma replaces this mechanism with overlay extmarks at redraw time. The fence lines stay as real, non-zero-height rows, so folds — including the frontmatter fold — collapse to a proper one-line placeholder regardless of `conceallevel`. Setting `experimental.patch_markdown_conceal = false` opts back into Neovim's native behaviour, including the fold-vanish issue.

<details>
<summary>Implementation details</summary>

The overlay is drawn by an `nvim_set_decoration_provider` callback that emits `FlemmaFenceLabel` (language label) and `FlemmaFenceBar` (delimiter bar) extmarks when `conceallevel >= 2`. These are **decoration-time extmarks**, not persistent extmarks in any namespace — debugging tools that enumerate `vim.api.nvim_buf_get_extmarks` won't see them. Markdown buffers in the same session keep their native fence concealing via automatic highlighter restoration; only `.chat` buffers route through the overlay system.

Upstream, the underlying issue is an unfortunate layering between `conceal_lines` and fold placeholders — not special-cased because `conceal_lines` was added for the "hide a blank JSX attribute line" shape of problem, not for rows that were structurally load-bearing. A `neovim/neovim` feature request ("fold placeholder should fall back to the first non-`conceal_lines` row in range") would be the durable fix.

</details>

<details>
<summary>References (Neovim source)</summary>

- `:h 'conceallevel'`, `:h 'concealcursor'` — Neovim docs.
- `src/nvim/drawline.c` — the assignment that makes `Conceal` terminal for concealed cells; the `conceal_lines` zero-height branch that wins over fold placeholders.
- `runtime/lua/vim/treesitter/highlighter.lua` — where the ephemeral `conceal + hl_group` extmark is emitted per capture.
- `runtime/queries/markdown/highlights.scm:50-59` — the `(#set! conceal_lines "")` directive on fenced-code-block delimiters.

</details>
