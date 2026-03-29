---
"@flemma-dev/flemma.nvim": patch
---

Unified all monetary formatting into a single `format_money` function with smart precision: integers show no decimals, values >= $1 use 2, values in [0.01, 1) use 3, and sub-cent values use 4 (trailing zeros past the 2nd decimal are stripped)
