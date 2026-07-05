---
"@flemma-dev/flemma.nvim": patch
---

Fix the `flemma.jobs.status` tool's `job_id` parameter: its guidance text was passed as `s.string(<default>)`, so it shipped as a JSON Schema `default` (a nonsense default value) with no `description` for the model. It now renders as the parameter's `description`, so the model finally sees how to fill in `job_id`.
