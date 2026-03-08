---
"@flemma-dev/flemma.nvim": minor
---

Added personality system for dynamic system prompt generation via `{{ include('urn:flemma:personality:<name>') }}`. Includes a `coding-assistant` personality that assembles tool listings, guidelines, environment context, and project-specific files into a complete system prompt. Tool definitions can contribute personality-scoped parts (snippets, guidelines, etc.) via a new `personalities` field.
