---
"@flemma-dev/flemma.nvim": minor
---

Rich fold text previews for message blocks. Folded `@Assistant` messages now show tool use previews (e.g. `bash: $ free -h | bash: $ cat /proc/meminfo (+1 tool)`), and folded `@You` messages show tool result previews with resolved tool names (e.g. `calculator_async: 4 | calculator_async: 8`). Expression segments are included in fold previews, consecutive text segments are merged, and runs of whitespace are collapsed to keep previews compact.
