---
"@flemma-dev/flemma.nvim": minor
---

Added filesystem sandboxing for tool execution. Shell commands now run inside a read-only rootfs with write access limited to configurable paths (project directory, .chat file directory, /tmp by default). Enabled by default with auto-detection of available backends; silently degrades on platforms without one. Includes Bubblewrap backend (Linux), pluggable backend registry for custom/future backends, per-buffer overrides via frontmatter, runtime toggle via :Flemma sandbox:enable/disable/status, and comprehensive documentation.
