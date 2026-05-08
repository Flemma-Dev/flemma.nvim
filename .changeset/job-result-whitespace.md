---
"@flemma-dev/flemma.nvim": patch
---

Fixed inconsistent whitespace when injecting job results: added blank lines between @You: and header, between consecutive results, and before the user's typing block; repeated Case 3 injections now merge into an existing job-result-only @You instead of creating extra blocks
