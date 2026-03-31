---
"@flemma-dev/flemma.nvim": minor
---

Expose `os.date`, `os.time`, `os.clock`, and `os.difftime` in the template sandbox, enabling date/time formatting in expressions (e.g., `{{ os.date("%B %d, %Y") }}`). Dangerous `os.*` functions (`execute`, `exit`, `getenv`, `remove`, etc.) remain excluded.
