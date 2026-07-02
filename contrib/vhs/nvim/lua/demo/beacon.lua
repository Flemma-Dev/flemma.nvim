--- Demo-only completion beacons for the VHS hero screencast.
---
--- A screencast needs a deterministic "the assistant is done" signal so the tape
--- can wait on a real event instead of a blind Sleep. Flemma fires
--- `conversation:idle` exactly once per exchange — it is suppressed while an
--- auto-continue is pending, so it never fires mid tool-cycle, only when the
--- final answer has streamed and everything has settled.
---
--- On each idle we send up a numbered beacon (`FlemmaBeacon1`, `FlemmaBeacon2`,
--- …) onto the message line, painted in the message-area background colour so it
--- never shows to a viewer but still lands in the terminal's character grid for
--- VHS to match with `Wait+Screen`. Numbering makes each exchange's wait
--- unambiguous — no stale-marker races, no clearing dance.
---
--- Loaded only by the demo config (contrib/vhs/nvim/init.lua); nothing here ships
--- with the plugin.
---@class demo.beacon
local M = {}

local hooks = require("flemma.hooks")

--- Highlight used to render the beacon invisibly (fg == message-area bg).
---@type string
local HL_GROUP = "FlemmaDemoBeacon"

--- Beacon prefix VHS greps for; the exchange number is appended.
---@type string
local MARKER_PREFIX = "FlemmaBeacon"

--- Catppuccin Mocha base — fallback when the theme reports no background.
---@type integer
local FALLBACK_BG = 0x1E1E2E

--- Count of settled exchanges so far; drives the beacon's numeric suffix.
---@type integer
local beacon_count = 0

--- Point HL_GROUP's foreground at the message-area background so the beacon
--- blends in. Recomputed on ColorScheme since the base colour can change.
local function refresh_highlight()
  local bg = vim.api.nvim_get_hl(0, { name = "MsgArea", link = false }).bg
  if not bg then
    bg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
  end
  vim.api.nvim_set_hl(0, HL_GROUP, { fg = bg or FALLBACK_BG })
end

--- Register the demo hooks. Call once from the demo config.
function M.setup()
  refresh_highlight()
  vim.api.nvim_create_autocmd("ColorScheme", { callback = refresh_highlight })

  hooks.on("conversation:idle", function()
    beacon_count = beacon_count + 1
    vim.api.nvim_echo({ { MARKER_PREFIX .. beacon_count, HL_GROUP } }, false, {})
  end)
end

return M
