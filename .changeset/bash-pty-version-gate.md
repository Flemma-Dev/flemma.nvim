---
"@flemma-dev/flemma.nvim": patch
---

Fixed silent data loss in bash tool output on Neovim 0.11.x under load (libuv#4992). The terminal backend is now gated to 0.12+ where the PTY flush bug is fixed; 0.11.x uses a jobstart+sink backend that collects output reliably via callbacks.
