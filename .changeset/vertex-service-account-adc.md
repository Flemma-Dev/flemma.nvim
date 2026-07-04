---
"@flemma-dev/flemma.nvim": patch
---

Fixed Vertex AI service-account authentication. The gcloud secrets resolver handed the service-account key to `gcloud auth print-access-token` via `GOOGLE_APPLICATION_CREDENTIALS`, but that subcommand ignores the variable and silently uses the active `gcloud auth login` account — so the service account was never actually used, and Vertex broke whenever the user login required reauthentication. Service-account keys are now minted through `gcloud auth application-default print-access-token` (with the cloud-platform scope), which reads the key and is immune to user reauth.
