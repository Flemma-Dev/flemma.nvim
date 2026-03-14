---
"@flemma-dev/flemma.nvim": minor
---

Added optional bufferline.nvim integration that shows a busy icon on `.chat` tabs while a request is in-flight. Configure with `get_element_icon = require("flemma.integrations.bufferline").get_element_icon` in your bufferline setup. Custom icons supported via `get_element_icon({ icon = "+" })`.
