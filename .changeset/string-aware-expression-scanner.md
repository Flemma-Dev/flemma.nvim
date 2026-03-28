---
"@flemma-dev/flemma.nvim": minor
---

Template expressions now handle `}}` and `%}` inside Lua string literals, comments, and table constructors without breaking. Previously, `{{ "email={{ customer.email }}" }}` would crash because the parser matched the first `}}` it found regardless of context.
