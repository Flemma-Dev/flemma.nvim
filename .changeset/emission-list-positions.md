---
"@flemma-dev/flemma.nvim": patch
---

Fixed emission list position overlap where trailing text after file references (e.g., the dot in `@./math.png.`) shared the expression's position range instead of getting its own correct offset
