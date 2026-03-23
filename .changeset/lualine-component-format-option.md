---
"@flemma-dev/flemma.nvim": minor
---

The lualine component now accepts a `format` option directly in the section config, which takes precedence over `statusline.format` in the Flemma config:

```lua
{ "flemma", format = "#{provider}:#{model}" }
```
