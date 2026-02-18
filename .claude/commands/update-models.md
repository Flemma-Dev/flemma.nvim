---
description: Update models and pricing in models.lua by scraping provider documentation
disable-model-invocation: true
---

# Update Models and Pricing

Update the following file (and only this file!): `lua/flemma/models.lua` — with up-to-date information about the models and pricing of Google Gemini (via Vertex AI), Anthropic Claude, and OpenAI.

## Data Sources — CLOSED SET, NO EXCEPTIONS

The URLs listed below are the **only** authoritative sources for this task. Model pricing and availability change constantly — random web pages, blogs, cached search results, and third-party aggregators are **stale and wrong**.

**You MUST NOT:**
- Use WebSearch at any point during this task — not for verification, not for "filling gaps", not for anything.
- Fetch any URL outside the domains of the listed pages (`cloud.google.com`, `docs.claude.com`, `platform.openai.com`). Following links within these domains is fine when needed to find model details.
- Use your training data or prior knowledge to add, remove, or price models — only use what the fetched pages say.

**If a model appears on these pages, it goes in. If it doesn't, it stays out.** Do not second-guess the official docs with outside information.

You will need to read and parse the following web pages:

### Google Gemini (via Vertex AI)

- https://cloud.google.com/vertex-ai/generative-ai/docs/learn/model-versions
- https://cloud.google.com/vertex-ai/generative-ai/docs/provisioned-throughput/supported-models
- https://cloud.google.com/vertex-ai/generative-ai/pricing

### Anthropic Claude

- https://docs.claude.com/en/docs/about-claude/models/overview
- https://docs.claude.com/en/docs/about-claude/pricing
- https://docs.claude.com/en/docs/about-claude/model-deprecations

### OpenAI

- https://platform.openai.com/docs/pricing?latest-pricing=standard
- https://platform.openai.com/docs/deprecations
- https://platform.openai.com/docs/models — this page requires you to scan the "Frontier models" section then recursively follow links to get the full list of OpenAI models and aliases.

## Rules

Today's date is !`date +%Y-%m-%d`. You will need this when assessing model retirement dates and deprecation notices — note a model that is deprecated but also still not retired is not to be removed. You should, however, leave a comment about its future retirement date, e.g., `-- Provider Model 1.2.3 (deprecated, retiring Jan 2030)`.

When parsing these pages, pay attention to model names as well as model aliases (usually include version numbers or dates).
If any model names imply non-text capabilities (e.g., "vision", "image", "video", "audio", etc.), ignore those models and do not include them in the local file.

**IMPORTANT!** Some providers (notably OpenAI) block AI-agent web fetchers. If WebFetch returns a 403, a bot-detection challenge, content that doesn't match what the URL implies, or an empty/garbage page — **fall back to the `links` text-mode browser** which is available on `$PATH`:

```bash
links -dump 'https://example.com/page'
```

This bypasses JavaScript challenges and bot-detection walls. Use `links -dump` for any page that WebFetch cannot retrieve. If even `links` fails (e.g., the page is behind a login wall or truly requires JavaScript rendering), ask the user to provide the Markdown source of the failing page(s) and proceed from there.

Think hard to avoid making mistakes as you parse the web pages and update the models file. **Every addition, removal, or price change must be traceable to a specific line on one of the listed pages.** If you are unsure about a value, ask the user — do not guess or search the web.

- If a model is present in the local file, but retired or past its deprecation date according to the listed pages, drop it from the local file.
- If a new model is present on the listed pages, but not in the local file, add it with all relevant information.
- If a model is in the local file but absent from the listed pages, ask the user before removing it — the page may have failed to load completely.

## Special Handling for New Sonnet Versions

Should you discover that during the update of Anthropic Claude models there is a new Sonnet version, this will require extra attention in other places of the codebase. If, and only if, there is a newer Sonnet version, scan the codebase for references of the previous Sonnet version and update them accordingly. Do this using a search pattern that captures all possible variations, casing and punctuation of Sonnet, e.g., instead of searching for punctuation, prefer using a wildcard. Example: "Sonnet 4.0" can be searched as /sonnet.?4(.?0)?/i

## Workflow

You will work in a step-by-step manner:

1. **Fetch all data sources first.** For each URL listed above, try WebFetch first, then `links -dump` as a fallback, then ask the user for content as a last resort. **Do not proceed to step 2 until you have successfully captured content from every URL** — you need complete data from all three providers to produce an accurate `models.lua`.
2. **Parse and extract** model names, aliases, pricing, deprecation dates, and retirement dates from the captured content.
3. **Update** `lua/flemma/models.lua` with the extracted information.
4. **Run `make test`** to check for tests that MAY reference retired or deprecated models.
