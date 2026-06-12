---
"@flemma-dev/flemma.nvim": patch
---

Background job results are now delivered on every send — autopilot cycles included — instead of waiting for the conversation to reach full idle. Previously a completed job's result could arrive several turns late while the model polled `flemma.jobs.status`, with each poll itself postponing delivery. The status tool also no longer reports finished jobs as a bare "queued": completed-but-undelivered jobs report `completed (delivery pending)` with `elapsed_seconds` frozen at the job's actual runtime.
