# Prompt Caching

Flemma supports prompt caching across all supported providers. Each provider implements caching differently, but the general `cache_retention` parameter provides a consistent interface – set it once and it applies to whichever provider you use.

Prefix stability is a core design discipline for Flemma. Provider caches only pay off when the request prefix is byte-identical to the previous request, so Flemma actively engineers for that — sorting tools alphabetically, canonicalizing JSON key order, freezing date/time per buffer, gating async tool discovery before the first send, and placing cache breakpoints deliberately. The next section documents what Flemma keeps stable; the per-provider sections describe what each provider does with the stable prefix.

## Cache stability in Flemma

A single mutated byte in the wrong place invalidates the cache from that point forward, billing every subsequent token at the full input rate instead of the (typically 10–50%) cached rate. The cost of an accidental cache bust grows linearly with conversation length, so Flemma treats prefix stability as a hard requirement from the start of every conversation.

### What Flemma keeps stable across requests

- **Tool ordering.** Tools are sorted alphabetically by name before being added to the request, regardless of registration order, source (built-in vs MCP), or whether they're enabled per-file. Two requests with the same tool set always produce identical tool definitions. The sort lives in `flemma.tools.get_sorted_for_prompt` and every provider adapter routes through it.

- **JSON key ordering.** Request bodies are serialized with object keys sorted alphabetically, except for explicitly marked _trailing keys_ (`messages`, `contents`, `tools`) which are kept at the end. This pins the smaller static config in the cacheable prefix and pushes the mutable arrays to the tail where the conversation-tail breakpoint can pick them up. See `flemma.utilities.json.encode_ordered`, which `flemma.client` uses for every request.

- **Date and time per buffer.** When a personality renders the system prompt (e.g. `include('urn:flemma:personality:coding-assistant')`), the `date` and `time` fields are captured **once on the first request** and reused for every subsequent request in that buffer's lifetime. The buffer can stay open for hours, but the date/time line in the system prompt stays frozen. The cached values live in the buffer's `personality_environment` state and clear only when the buffer is wiped. Other environment fields — `cwd`, `current_file`, `git_branch`, `filetype` — are fetched fresh each request so renames and branch switches still flow through.

- **Tool IDs.** Tool use/result IDs are preserved exactly as they appear in the buffer; Flemma never renumbers or re-canonicalizes them between requests. Edits to earlier turns retain their original IDs in their original positions.

- **Abort markers.** When you cancel a request mid-stream, Flemma writes an abort marker (`<!--...-->`) into the assistant text and **keeps it** for subsequent requests. Removing it would change the prefix and bust the cache. The model sees the marker on every following request and continues from a stable prefix.

- **Async tool gating.** On startup, MCP servers and other async tool sources resolve concurrently. Flemma blocks the first send via a `readiness` suspense (`flemma.tools.ensure_ready`) until every source has loaded. The alternative — letting an early request go out with a partial tool list — would establish a doomed cache prefix that every subsequent request invalidates as more tools come online.

- **Three cache breakpoints on Anthropic.** Three independent `cache_control` markers are placed: one on the last tool definition, one on the system prompt, and a top-level marker that Anthropic auto-advances to the conversation tail. Tools and system prompt cache independently of the conversation, so they survive even as the conversation grows. The conversation-tail marker tracks the most recent user or `tool_result` turn automatically.

### What still breaks the cache

Some changes always bust the cache, no matter what Flemma does. Watch for them in long conversations where the savings matter most:

- **Adding or removing tools mid-conversation.** Tools sit at the very start of the prefix, before the system prompt. Appending a tool via frontmatter (`flemma.opt.tools:append({"server.tool"})`) or toggling a tool's `enabled` flag between requests changes the alphabetically-sorted tool array, and everything from the new tool's position onward — the rest of the tools, the system prompt, and all conversation turns — has to be reprocessed at full input rate. A 100,000-token conversation that suddenly needs a new tool pays for the entire conversation again on the next send. **Workaround:** lock the buffer's tool set from the first request. Either fix the set in `setup()` and don't change tool enablement during the conversation, or pin a comprehensive list in the buffer's frontmatter (`flemma.opt.tools = {...}`) from the start. An explicit per-buffer tools list includes even tools registered with `enabled = false` globally, so you can pre-list "might-need-this-later" tools as long as you commit to them up front — but appending to or otherwise mutating that list mid-conversation still busts the cache.

- **Template expressions that vary.** `{{ os.time() }}`, `{{ math.random() }}`, or `{{ include('...') }}` referencing a file whose content has changed will all produce different output on subsequent requests, busting the cache from that template's position forward. Capture volatile values in frontmatter once if you need them stable across the conversation.

- **Editing earlier conversation turns.** The buffer is the state — and the buffer is what gets sent. Editing any character of an earlier message, even fixing a typo in your own user turn, changes the request body at that position and invalidates the cache from there forward.

- **Changing the system prompt or personality.** Switching personalities, modifying the system message, or changing project context files (`AGENTS.md`, `CLAUDE.md`, `.cursorrules`, `.github/copilot-instructions.md`) all change the rendered system prompt.

- **File references whose content has changed.** `@./path` is resolved fresh every request — if the file changed since the previous send, the resolved content changes too.

- **Configuration changes affecting request shape.** Swapping models, switching providers, adjusting thinking levels, or modifying preset parameters all change the request shape and can change the prefix.

### Verifying cache behavior

After each request, the usage bar shows cached vs. uncached input tokens (when the provider reports them) so you can confirm hits in real time. `:Flemma usage:estimate` reports projected input tokens for the next request before you send. With `logging.level = "DEBUG"` (or `TRACE`), each request's cache totals are also written to the Flemma log.

## Quick Comparison

|               | Anthropic             | OpenAI                | Vertex AI       | Moonshot           |
| ------------- | --------------------- | --------------------- | --------------- | ------------------ |
| Default       | `"short"` (5 min TTL) | `"short"` (in-memory) | Automatic       | Automatic          |
| Min. tokens   | 2,048–4,096\*         | 1,024                 | 1,024–2,048     | —                  |
| Read discount | 90% (0.1x)            | 50% (0.5x)            | 90% (0.1x)      | 80% (0.2x)         |
| Write cost    | 1.25x–2.0x            | Free                  | Free            | Free               |
| Control       | `cache_retention`     | `cache_retention`     | None (implicit) | `prompt_cache_key` |

When caching is active, the usage bar includes cache percentage and token counts. Costs are adjusted to reflect each provider's discount on cached input.

_\*The legacy Haiku 3 model uses a 1,024-token threshold. All current 4.x Anthropic models require at least 2,048 (Opus/Sonnet) or 4,096 (Haiku 4.5) tokens before caching activates._

---

## Anthropic

Flemma automatically adds cache breakpoints to Anthropic API requests, letting the provider reuse previously processed prefixes at a fraction of the cost[^anthropic-cache]. Three breakpoints are placed: the tool definitions, the system prompt, and the conversation tail — the third one is a top-level `cache_control` that Anthropic auto-advances to the last cacheable block in the prompt (usually the most recent user turn, but a trailing `tool_result` will pick up the breakpoint instead). See [Cache stability in Flemma](#cache-stability-in-flemma) for the broader stability story.

The `cache_retention` parameter controls the caching strategy[^anthropic-cache-pricing]:

| Value     | TTL    | Write cost | Read cost | Description                    |
| --------- | ------ | ---------- | --------- | ------------------------------ |
| `"short"` | 5 min  | 1.25x      | 0.1x      | Default. Good for active chat. |
| `"long"`  | 1 hour | 2.0x       | 0.1x      | Better for long-running tasks. |
| `"none"`  | —      | —          | —         | Disable caching entirely.      |

When caching is active, the usage bar includes cache percentage and read/write token counts. Costs are adjusted accordingly – cache reads are 90% cheaper than regular input tokens.

> [!NOTE]
> Anthropic requires a **minimum number of tokens** in the cached prefix before caching activates[^anthropic-cache-limits]. The thresholds vary by model: **4,096 tokens** for Haiku 4.5; **2,048 tokens** for every current Opus and Sonnet (4.7, 4.6, 4.5, 4.1, 4, and the matching Sonnet 4.x family); **1,024 tokens** only on the legacy Haiku 3. If your conversation is below this threshold, the API returns zero cache tokens and charges the standard input rate. This is expected — caching benefits grow with longer conversations and system prompts. The authoritative per-model values live in `lua/flemma/models/anthropic.lua` (`min_cache_tokens`).

---

## OpenAI

Flemma sends prompt caching hints to the OpenAI Responses API using the `cache_retention` parameter[^openai-cache]. When caching is active, Flemma sends the buffer's file path as `prompt_cache_key` and a retention policy as `prompt_cache_retention`. When a cache hit occurs, the usage bar includes the cache percentage and read token count. Costs are adjusted to reflect the 50% discount on cached input[^openai-cache-pricing].

The `cache_retention` parameter controls the caching strategy:

| Value     | TTL        | Write cost       | Read cost | Description                                           |
| --------- | ---------- | ---------------- | --------- | ----------------------------------------------------- |
| `"short"` | 5–10 min   | free (invisible) | 0.5x      | Default. `in_memory` retention, good for active chat. |
| `"long"`  | up to 24 h | free (invisible) | 0.5x      | Extended retention for long sessions.                 |
| `"none"`  | —          | —                | —         | No caching hints sent.                                |

> [!NOTE]
> Unlike Anthropic, OpenAI does not report cache **write** tokens in the API response. Writes happen automatically and are free, so the usage bar only shows cache reads.

> [!IMPORTANT]
> OpenAI caching is **best-effort and not guaranteed**. Even when the prompt meets all requirements, the API may return zero cached tokens. Key conditions:
>
> - **Minimum 1,024 tokens** in the prompt prefix[^openai-cache]. Shorter prompts are never cached.
> - **Prefix must be byte-identical** between requests. Any change to tools, system prompt, or earlier messages invalidates the cache from that point forward.
> - **Cache propagation takes time.** The first request populates the cache; subsequent requests can hit it. Sending requests in rapid succession (within a few seconds) may miss the cache because the entry hasn't propagated yet. Wait at least 5–10 seconds between requests for the best chance of a hit.
> - **128-token granularity.** Only the first 1,024 tokens plus whole 128-token increments are cacheable. Tokens beyond the last 128-token boundary are always processed fresh.

---

## Vertex AI

Gemini 2.5+ models support implicit context caching[^vertex-cache]. When consecutive requests share a common input prefix, the Vertex AI serving infrastructure automatically caches and reuses it – no configuration or request changes are needed. When a cache hit occurs, the usage bar includes the cache percentage and read token count. Costs are adjusted to reflect the 90% discount on cached input[^vertex-cache-pricing].

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

## Moonshot AI

Moonshot uses automatic prompt caching with no separate write fee. The API reports `cached_tokens` on cache hits, and cached input is billed at a reduced rate (approximately 80% discount). There is no minimum token threshold or TTL to manage – caching is handled entirely by Moonshot's infrastructure. The general `cache_retention` parameter has no effect on Moonshot (and is similarly inert for Vertex's implicit cache) — only `prompt_cache_key` influences cache behaviour here.

To improve cache hit rates across requests, you can set a stable `prompt_cache_key` via provider parameters:

```lua
require("flemma").setup({
  parameters = {
    moonshot = {
      prompt_cache_key = "my-project-key",
    },
  },
})
```

Or per-buffer in frontmatter:

```lua
flemma.opt.moonshot = { prompt_cache_key = "my-project-key" }
```

When a cache hit occurs, the usage bar includes the cached token count. Caching is available on kimi-k2 family models; moonshot-v1-\* models do not report cached tokens.

---

[^anthropic-cache]: https://platform.claude.com/docs/en/docs/build-with-claude/prompt-caching

[^anthropic-cache-pricing]: https://platform.claude.com/docs/en/docs/build-with-claude/prompt-caching#pricing

[^anthropic-cache-limits]: https://platform.claude.com/docs/en/docs/build-with-claude/prompt-caching#cache-limitations

[^openai-cache]: https://platform.openai.com/docs/guides/prompt-caching

[^openai-cache-pricing]: https://platform.openai.com/docs/pricing

[^vertex-cache]: https://developers.googleblog.com/en/gemini-2-5-models-now-support-implicit-caching/

[^vertex-cache-pricing]: https://cloud.google.com/vertex-ai/generative-ai/pricing

[^vertex-cache-explicit]: https://docs.cloud.google.com/vertex-ai/generative-ai/docs/context-cache/context-cache-overview
