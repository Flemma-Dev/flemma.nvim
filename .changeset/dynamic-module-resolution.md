---
"@flemma-dev/flemma.nvim": minor
---

Added dynamic module resolution for third-party extensions. Lua module paths (dot-notation strings like "3rd.tools.todos") can now be used in config.provider, config.tools.modules, config.tools.auto_approve, config.sandbox.backend, and flemma.opt.tools to reference third-party modules without explicit require() calls. Modules are validated at setup time and lazily loaded on first use.
