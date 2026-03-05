---
"@flemma-dev/flemma.nvim": minor
---

Line highlights now use per-message range extmarks instead of per-line extmarks, reducing API calls from ~500 to ~20 per update. New lines created by pressing Return in insert mode are highlighted immediately via Neovim's gravity system instead of waiting for CursorHoldI.
