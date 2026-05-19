---
"@flemma-dev/flemma.nvim": patch
---

Fixed MCPorter tool calls failing when input is empty (e.g., `trello:list_workspaces`) — `json.encode({})` produces `[]` which mcporter rejects as not a JSON object
