# Flemma with LazyVim

[LazyVim](https://www.lazyvim.org/) manages plugins through spec files in `lua/plugins/`. Flemma needs exactly one, and this page covers the details that are specific to running Flemma inside the distro.

## The spec

Create `~/.config/nvim/lua/plugins/flemma.lua`:

```lua
return {
  "Flemma-Dev/flemma.nvim",
  opts = {},
}
```

That is the whole install. lazy.nvim calls `require("flemma").setup(opts)` for you, which registers the `chat` filetype, the `:Flemma` command and the buffer-local keymaps. Set up a credential (an environment variable such as `ANTHROPIC_API_KEY`, or your platform keyring: see the [README Quick Start](../README.md#quick-start)), open any file ending in `.chat`, type your message after `@You:` and press `Ctrl-]`.

`opts` takes the same table as `setup()`. A practical starting point, borrowed from the [configuration reference](configuration.md):

```lua
return {
  "Flemma-Dev/flemma.nvim",
  opts = {
    provider = "anthropic",
    thinking = "high",
    editing = { auto_write = true },
  },
}
```

## Do not lazy-load it

Flemma registers everything in `setup()`: the `.chat` filetype detection, the `:Flemma` command, highlighting and keymaps. There is no `plugin/` or `ftdetect/` shim for lazy.nvim to source ahead of time, so the usual lazy-loading triggers backfire:

- `ft = "chat"` never fires, because the mapping from `.chat` files to the `chat` filetype is itself created by `setup()`.
- `cmd = "Flemma"` and `keys = { ... }` leave `.chat` files opening as plain text until the first invocation.

The LazyVim starter passes `defaults = { lazy = false }` to lazy.nvim, so the plain spec above already loads at startup. If you flipped that default to `true`, add an explicit `lazy = false` to Flemma's spec. Note that a `keys` entry implies lazy-loading on its own, so pair it with `lazy = false` as shown below.

## Keymaps

Flemma ships no global keymaps. Everything it binds is buffer-local to `chat` buffers (`Ctrl-]` to send, `Ctrl-C` to cancel, the full table is in the [README](../README.md#commands-and-keymaps)), so nothing collides with LazyVim's own keys or its extras.

If you want a global entry point, LazyVim's AI extras group their keymaps under `<leader>a` ("+ai") and Flemma can park next to them:

```lua
return {
  "Flemma-Dev/flemma.nvim",
  lazy = false, -- keys below would otherwise defer loading
  opts = {},
  keys = {
    { "<leader>ac", "<cmd>edit scratch.chat<cr>", desc = "Flemma scrachpad (cwd)" },
  },
}
```

With the Copilot Chat extra enabled, `<leader>ac` is unclaimed; other AI extras may differ, so check `:map <leader>a` and adjust to taste. Opening the `.chat` file in the project root keeps the conversation next to the work it produced, ready to `git add` when it earns it.

## Statusline

LazyVim's statusline is [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim), and Flemma ships a lualine component that shows the active model, thinking level, projected context usage and session cost while you are in a `chat` buffer (it renders nothing elsewhere). LazyVim builds its lualine sections in its own spec, so extend them rather than replace them:

```lua
return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    table.insert(opts.sections.lualine_x, 1, { "flemma", icon = "∴" })
  end,
}
```

The component and its format string are documented in [integrations.md](integrations.md).

## File icon

LazyVim does not use nvim-web-devicons. It ships [mini.icons](https://github.com/nvim-mini/mini.icons) and preloads a compatibility mock, so plugins that require `nvim-web-devicons` get the mock instead. The mock's registration functions are deliberate no-ops, which means Flemma's automatic `.chat` icon registration lands nowhere on LazyVim. Give mini.icons the icon directly:

```lua
return {
  "nvim-mini/mini.icons",
  opts = {
    extension = {
      chat = { glyph = "∴", hl = "MiniIconsAzure" },
    },
  },
}
```

All of these snippets can live in one file: `lua/plugins/flemma.lua` may return a list of specs.

## Per-project configuration with `.lazy.lua`

lazy.nvim loads a project-local spec file called `.lazy.lua` from your working directory by default (`local_spec = true`). Specs for the same plugin merge, `opts` included, so you can keep your global defaults in `lua/plugins/flemma.lua` and override per repository:

```lua
-- .lazy.lua at the project root
return {
  {
    "Flemma-Dev/flemma.nvim",
    opts = {
      provider = "anthropic",
      model = "claude-opus-4-8",
    },
  },
}
```

Individual `.chat` files can override settings too, which is often the better tool for one-off tweaks: see [templates.md](templates.md).

## Alongside the AI extras

Flemma does not overlap with LazyVim's `ai` extras. Copilot and friends complete code as you type; sidekick, avante and claudecode drive coding agents inside the editor. Flemma is a workbench for the documents around the work: status updates, specs, research and transcripts, kept as `.chat` files you can grep and commit. Enable both sides freely; they share nothing but the `<leader>a` prefix if you chose it above.

## Requirements LazyVim already covers

Flemma needs the Markdown Tree-sitter grammars, and LazyVim's `nvim-treesitter` spec installs `markdown` and `markdown_inline` out of the box, so there is nothing to add. That leaves Neovim 0.11+ and `curl`, plus optional [`bwrap`](https://github.com/containers/bubblewrap) for tool sandboxing on Linux: see the [README requirements](../README.md#quick-start).
