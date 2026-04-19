---
"@flemma-dev/flemma.nvim": major
---

Extract reusable Bar UI utility and reorganise ui config namespace.

**Breaking changes (default behaviour is unchanged for users who did not customise these keys):**

- Config namespace moves under `ui`. Rename `notifications.*` → `ui.usage.*` and `progress.*` → `ui.progress.*`.
- Removed config keys: `notifications.limit`, `notifications.border`, `notifications.zindex`, `notifications.position`, `progress.zindex`. Stacking, the underline border, and the z-index overrides are gone by design.
- Highlight groups `FlemmaNotificationsBar`, `FlemmaNotificationsSecondary`, `FlemmaNotificationsMuted`, `FlemmaNotificationsCacheGood`, `FlemmaNotificationsCacheBad` rename to `FlemmaUsageBar{,Secondary,Muted,CacheGood,CacheBad}`. `FlemmaNotificationsBottom` is removed with the border feature. Fallback chains and computed colours preserved exactly.
- User command `:Flemma notification:recall` renames to `:Flemma usage:recall`.

**New capabilities:**

- Usage bar and progress bar each gain a `position` option; choose from `top`, `bottom`, `top left`, `top right`, `bottom left`, `bottom right`. Defaults unchanged (`top` for usage, `bottom left` for progress).

**Internal structure (informational):**

- `lua/flemma/bar.lua` moves to `lua/flemma/ui/bar/layout.lua` and gains an `apply_rendered_highlights` helper.
- New module `lua/flemma/ui/bar/init.lua` provides a handle-based `Bar.new(opts)` with `set_icon` / `set_segments` / `set_highlight` / `update` / `dismiss` / `is_dismissed` methods, six positions, mutual exclusion, and lifecycle autocmds.
- `lua/flemma/notifications.lua` is deleted; its driver logic lives in `lua/flemma/usage.lua`.
- Progress float in `lua/flemma/ui/init.lua` rewires to `Bar`; the inline "Waiting"/"Thinking" virt_text path and the off-screen fallback are preserved unchanged.
