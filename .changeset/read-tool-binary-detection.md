---
"@flemma-dev/flemma.nvim": minor
---

The read tool now detects binary files (images, PDFs, and other non-text formats) and emits an `@./path;type=mime` file reference instead of attempting to read raw bytes. The reference is handled by the `template_tool_result` pipeline, routing binary content to providers as structured file attachments.
