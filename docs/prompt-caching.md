# Prompt Caching

Flemma supports prompt caching across all three providers. Each provider implements caching differently, but the general `cache_retention` parameter provides a consistent interface – set it once and it applies to whichever provider you use.

## Quick Comparison

|               | Anthropic             | OpenAI                | Vertex AI       |
| ------------- | --------------------- | --------------------- | --------------- |
| Default       | `"short"` (5 min TTL) | `"short"` (in-memory) | Automatic       |
| Min. tokens   | 1,024–4,096           | 1,024                 | 1,024–2,048     |
| Read discount | 90% (0.1x)            | 50% (0.5x)            | 90% (0.1x)      |
| Write cost    | 1.25x–2.0x            | Free                  | Free            |
| Control       | `cache_retention`     | `cache_retention`     | None (implicit) |

When caching is active, usage notifications show a `Cache:` line with read and write token counts. Costs are adjusted to reflect each provider's discount on cached input.

---

## Anthropic

Flemma automatically adds cache breakpoints to Anthropic API requests, letting the provider reuse previously processed prefixes at a fraction of the cost[^anthropic-cache]. Three breakpoints are placed: the tool definitions, the system prompt, and the last user message. Tools are sorted alphabetically so the prefix stays stable across requests.

The `cache_retention` parameter controls the caching strategy[^anthropic-cache-pricing]:

| Value     | TTL    | Write cost | Read cost | Description                    |
| --------- | ------ | ---------- | --------- | ------------------------------ |
| `"short"` | 5 min  | 1.25x      | 0.1x      | Default. Good for active chat. |
| `"long"`  | 1 hour | 2.0x       | 0.1x      | Better for long-running tasks. |
| `"none"`  | —      | —          | —         | Disable caching entirely.      |

When caching is active, usage notifications show a `Cache:` line with read and write token counts. Costs are adjusted accordingly – cache reads are 90% cheaper than regular input tokens.

> [!NOTE]
> Anthropic requires a **minimum number of tokens** in the cached prefix before caching activates[^anthropic-cache-limits]. The thresholds vary by model: **4096 tokens** for Opus 4.6, Opus 4.5, and Haiku 4.5; **1024 tokens** for Sonnet 4.6, Sonnet 4.5, Opus 4.1, Opus 4, and Sonnet 4. If your conversation is below this threshold, the API returns zero cache tokens and charges the standard input rate. This is expected – caching benefits grow with longer conversations and system prompts.

---

## OpenAI

Flemma sends prompt caching hints to the OpenAI Responses API using the `cache_retention` parameter[^openai-cache]. When caching is active, Flemma sends the buffer's file path as `prompt_cache_key` and a retention policy as `prompt_cache_retention`. When a cache hit occurs, the usage notification shows a `Cache:` line with the number of read tokens. Costs are adjusted to reflect the 50% discount on cached input[^openai-cache-pricing].

The `cache_retention` parameter controls the caching strategy:

| Value     | TTL        | Write cost       | Read cost | Description                                           |
| --------- | ---------- | ---------------- | --------- | ----------------------------------------------------- |
| `"short"` | 5–10 min   | free (invisible) | 0.5x      | Default. `in_memory` retention, good for active chat. |
| `"long"`  | up to 24 h | free (invisible) | 0.5x      | Extended retention for long sessions.                 |
| `"none"`  | —          | —                | —         | No caching hints sent.                                |

> [!NOTE]
> Unlike Anthropic, OpenAI does not report cache **write** tokens in the API response. Writes happen automatically and are free, so the usage notification only shows cache reads.

> [!IMPORTANT]
> OpenAI caching is **best-effort and not guaranteed**. Even when the prompt meets all requirements, the API may return zero cached tokens. Key conditions:
>
> - **Minimum 1,024 tokens** in the prompt prefix[^openai-cache]. Shorter prompts are never cached.
> - **Prefix must be byte-identical** between requests. Any change to tools, system prompt, or earlier messages invalidates the cache from that point forward.
> - **Cache propagation takes time.** The first request populates the cache; subsequent requests can hit it. Sending requests in rapid succession (within a few seconds) may miss the cache because the entry hasn't propagated yet. Wait at least 5–10 seconds between requests for the best chance of a hit.
> - **128-token granularity.** Only the first 1,024 tokens plus whole 128-token increments are cacheable. Tokens beyond the last 128-token boundary are always processed fresh.

---

## Vertex AI

Gemini 2.5+ models support implicit context caching[^vertex-cache]. When consecutive requests share a common input prefix, the Vertex AI serving infrastructure automatically caches and reuses it – no configuration or request changes are needed. When a cache hit occurs, the usage notification shows a `Cache:` line with the number of read tokens. Costs are adjusted to reflect the 90% discount on cached input[^vertex-cache-pricing].

| Metric      | Value         | Description                                            |
| ----------- | ------------- | ------------------------------------------------------ |
| Read cost   | 0.1x (10%)    | Cached input tokens cost 10% of the normal input rate. |
| Write cost  | —             | No additional charge; caching is automatic.            |
| Min. tokens | 1,024 / 2,048 | 1,024 for Flash models, 2,048 for Pro models.          |

> [!IMPORTANT]
> Vertex AI implicit caching is **automatic and best-effort** – cache hits are not guaranteed. Key conditions:
>
> - **Minimum token thresholds** vary by model: **1,024 tokens** for Flash, **2,048 tokens** for Pro[^vertex-cache]. Shorter prompts are never cached.
> - **Prefix must be identical** between requests. Changing tools, system instructions, or earlier conversation turns invalidates the cache from that point forward.
> - **Only Gemini 2.5+ models** support implicit caching. Older Gemini models (2.0, 1.5) do not report cached tokens.
> - **Cache propagation takes time.** Like OpenAI, the first request populates the cache and immediate follow-up requests may not see a hit. Allow a few seconds between requests.
> - **No user control.** There is no TTL parameter or opt-out – caching is managed entirely by Google's infrastructure.
>
> Google also offers an **explicit Context Caching API**[^vertex-cache-explicit] that creates named cache resources with configurable TTLs via a separate endpoint. Explicit caching requires a different workflow (create cache, then reference it) and is not yet supported by Flemma.

---

[^anthropic-cache]: https://platform.claude.com/docs/en/docs/build-with-claude/prompt-caching
[^anthropic-cache-pricing]: https://platform.claude.com/docs/en/docs/build-with-claude/prompt-caching#pricing
[^anthropic-cache-limits]: https://platform.claude.com/docs/en/docs/build-with-claude/prompt-caching#cache-limitations
[^openai-cache]: https://platform.openai.com/docs/guides/prompt-caching
[^openai-cache-pricing]: https://platform.openai.com/docs/pricing
[^vertex-cache]: https://developers.googleblog.com/en/gemini-2-5-models-now-support-implicit-caching/
[^vertex-cache-pricing]: https://cloud.google.com/vertex-ai/generative-ai/pricing
[^vertex-cache-explicit]: https://docs.cloud.google.com/vertex-ai/generative-ai/docs/context-cache/context-cache-overview
