---
"@flemma-dev/flemma.nvim": patch
---

The unified `thinking` parameter now controls reasoning depth on Kimi K3. K3 configures thinking through the top-level `reasoning_effort` field rather than the K2 family's `thinking` object, so setting `thinking` had no effect and every request reasoned at the server default of `max` — the most expensive setting, with no way to make K3 cheaper or faster. Flemma's canonical levels now map onto the three values the API accepts: `minimal` and `low` send `low`, `medium` and `high` send `high`, and `max` sends `max`. K3 cannot stop reasoning, so thinking turned off sends `low` — the floor — rather than omitting the field and silently inheriting `max`. Temperature is locked to 1.0, which Moonshot fixes on K3 as it does across the K2.x line.
