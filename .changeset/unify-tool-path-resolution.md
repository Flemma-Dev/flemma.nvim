---
"@flemma-dev/flemma.nvim": minor
---

Tools now resolve relative paths against the .chat buffer's directory (`__dirname`) instead of Neovim's working directory, matching the behavior of `@./file` references and `{{ include() }}` expressions. The `tools.bash.cwd` config defaults to `"$FLEMMA_BUFFER_PATH"` (set to `nil` to restore the previous cwd behavior).
