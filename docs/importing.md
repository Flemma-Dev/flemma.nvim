# Importing from Claude Workbench

Flemma can turn Claude Workbench exports into ready-to-send `.chat` buffers.

**Quick steps:** Export the TypeScript snippet in Claude Workbench, paste it into Neovim, then run `:Flemma import`.

---

## Before you start

- `:Flemma import` delegates to the current provider. Keep Anthropic active (`:Flemma switch anthropic`) so the importer knows how to interpret the snippet.
- Use an empty scratch buffer – `Flemma import` overwrites the entire buffer with the converted chat.

## Export from Claude Workbench

1. Navigate to <https://console.anthropic.com/workbench> and open the saved prompt you want to migrate.
2. Click **Get code** in the top-right corner, then switch the language dropdown to **TypeScript**. The importer expects the `anthropic.messages.create({ ... })` call produced by that export.
3. Press **Copy code**; Claude Workbench copies the whole TypeScript example (including the `import Anthropic from "@anthropic-ai/sdk"` header).

## Convert inside Neovim

1. In Neovim, paste the snippet into a new buffer (or delete any existing text first).
2. Run `:Flemma import`. The command:
   - Scans the buffer for `anthropic.messages.create(...)`.
   - Normalises the JavaScript object syntax and decodes it as JSON.
   - Emits a system message (if present) and rewrites every Workbench message as `@You:` / `@Assistant:` lines.
   - Switches the buffer's filetype to `chat` so folds, highlights, and keymaps activate immediately.

## Troubleshooting

- If the snippet does not contain an `anthropic.messages.create` call, the importer aborts with "No Anthropic API call found".
- JSON decoding errors write both the original snippet and the cleaned JSON to `flemma_import_debug.log` in your temporary directory (e.g. `/tmp/flemma_import_debug.log`). Open that file to spot mismatched brackets or truncated copies.
- Nothing happens? Confirm Anthropic is the active provider – other providers currently do not ship an importer.
