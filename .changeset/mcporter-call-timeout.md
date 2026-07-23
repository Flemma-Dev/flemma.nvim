---
"@flemma-dev/flemma.nvim": minor
---

mcporter tool calls now honour a call timeout. Flemma passes `--timeout` (milliseconds) to `mcporter call`, derived from `tools.mcporter.timeout`, and exposes an optional per-call `timeout` (seconds) in every discovered tool's input schema — mirroring the built-in `bash` tool — so the model can extend the budget for slow tools such as deep research. Previously neither the configured timeout nor a model-supplied `timeout` reached mcporter: the value was serialized into the tool arguments and silently ignored while mcporter fell back to its own default. A grace window now lets mcporter report its own timeout before Flemma force-kills the subprocess, and a server-owned `timeout` parameter is left untouched.
