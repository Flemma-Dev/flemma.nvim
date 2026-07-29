---
"@flemma-dev/flemma.nvim": patch
---

Fixed the request Flemma sends to `kimi-k2.7-code` and `kimi-k2.7-code-highspeed`. Both were declared as thinking-toggle models, so turning thinking off sent `thinking = {"type": "disabled"}` with `temperature = 0.6` — a combination the API rejects outright, since thinking on the K2.7 Code family is always on and cannot be disabled. They are now declared `forced`: no `thinking` object is sent at all (Moonshot documents it as omittable, and the only form it accepts when set explicitly is `{"type":"enabled","keep":"all"}`), and temperature is locked to the 1.0 the API fixes it at. Parameter validation now warns about fixed sampling parameters on every K2.x/K3 model rather than only the toggleable ones.
