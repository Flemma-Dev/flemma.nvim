---
"@flemma-dev/flemma.nvim": minor
---

Aligned all registry modules to a consistent API contract: every registry now exposes register(), unregister(), get(), get_all(), has(), clear(), and count(). Extracted shared name validation into a new flemma.registry utility module. Renamed tools registry define() to register() (define() kept as deprecated alias).
