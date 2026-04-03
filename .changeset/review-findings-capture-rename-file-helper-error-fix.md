---
"@flemma-dev/flemma.nvim": patch
---

Rename __capture_open/__capture_close to __capture_start/__capture_end for clarity, extract duplicated MIME-based file conversion logic into shared convert_file_part() helper, and fix crash in OpenAI Responses provider when tool result has both is_error and non-text parts.
