-- Require-isolation check: load every module under lua/ in a bare Neovim to
-- prove none has a require()-time side effect that depends on global init order
-- (e.g. self-registering into config before config.init() has run). Mirrors
-- nixpkgs' nvimRequireCheck so packaging — and isolated module loaders — can
-- never regress silently. Invoked by contrib/scripts/lint-require-isolation.sh
-- inside a bare `nvim -u NONE`.

-- Modules that legitimately CANNOT be require()d in isolation because they
-- extend an external plugin's runtime, present only when that plugin is loaded.
-- The mirror of nixpkgs' `nvimSkipModules`. Keep it minimal — each entry is a
-- module with no business loading in a bare editor, paired with the reason. A
-- stale entry (one that now loads cleanly) fails the check, so this list cannot
-- rot into a silent graveyard.
local SKIP = {
  -- Lualine statusline component: `require("lualine.component"):extend()` runs
  -- at load. Needs the lualine plugin, absent under `nvim -u NONE`. Flemma ships
  -- it under lua/lualine/ purely so lualine auto-discovers it in the user's
  -- runtime — Flemma itself never require()s it.
  ["lualine.components.flemma"] = "extends lualine.component (external plugin)",
}

local root = vim.fn.getcwd() .. "/lua"
local files = vim.fn.globpath(root, "**/*.lua", true, true)
table.sort(files)

---@type { mod: string, err: string }[]
local load_failures = {}
---@type string[]
local stale_skips = {}
local skipped = 0

for _, file in ipairs(files) do
  local mod = file:sub(#root + 2):gsub("%.lua$", ""):gsub("/init$", ""):gsub("/", ".")
  local ok, err = pcall(require, mod)
  if SKIP[mod] then
    skipped = skipped + 1
    if ok then
      table.insert(stale_skips, mod)
    end
  elseif not ok then
    table.insert(load_failures, { mod = mod, err = tostring(err) })
  end
end

local problems = {}

if #load_failures > 0 then
  local lines = {}
  for _, entry in ipairs(load_failures) do
    table.insert(lines, "  - " .. entry.mod .. "\n      " .. entry.err:gsub("\n", "\n      "))
  end
  table.insert(
    problems,
    ("%d module(s) fail to require() in isolation (before setup()):\n%s\n\nA module must be require()-able standalone — register into global state\nduring setup(), never as a load-time side effect."):format(
      #load_failures,
      table.concat(lines, "\n")
    )
  )
end

if #stale_skips > 0 then
  table.insert(
    problems,
    ("%d skip-listed module(s) now load cleanly — drop them from SKIP in\ncontrib/scripts/require-isolation-check.lua:\n  - %s"):format(
      #stale_skips,
      table.concat(stale_skips, "\n  - ")
    )
  )
end

if #problems > 0 then
  io.stderr:write("lint-require-isolation: FAILED\n\n" .. table.concat(problems, "\n\n") .. "\n")
  os.exit(1)
end

print(("lint-require-isolation: OK — %d modules load cleanly (%d skipped)"):format(#files - skipped, skipped))
