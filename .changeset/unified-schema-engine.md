---
"@flemma-dev/flemma.nvim": minor
---

Unified schema engine: schema DSL nodes can now define tool input schemas via `to_json_schema()` serialization, as an alternative to raw JSON Schema tables. Added `s.nullable()` for required-but-nullable fields, chainable `:optional()` and `:nullable()` modifiers, and converted all built-in tools to use the DSL.
