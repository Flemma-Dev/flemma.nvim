---
"@flemma-dev/flemma.nvim": patch
---

Fixed truncation splitting multi-byte UTF-8 characters, which produced invalid JSON request bodies rejected by the API with "surrogates not allowed"
