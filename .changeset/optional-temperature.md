---
"@flemma-dev/flemma.nvim": minor
---

Temperature is now optional with no default. Previously Flemma always sent `temperature: 0.7` to provider APIs, which caused reasoning-native models (gpt-5-mini, o-series) to reject requests entirely. Temperature is now omitted unless explicitly set by the user, letting each API use its own default (typically 1.0).

If you previously relied on the implicit 0.7 default for less random responses, add `temperature = 0.7` to your setup config or chat frontmatter.

Note: temperature is no longer silently stripped when set alongside reasoning/thinking. If you explicitly set both, the API will reject the request — correct this by removing the temperature setting.
