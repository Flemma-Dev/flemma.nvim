--- Spinner frame definitions shared between the UI and contrib preview tools
--- Buffering and tool frames adapted from sindresorhus/cli-spinners via
--- https://github.com/spectreconsole/spectre.console/blob/main/src/Spectre.Console/Data/spinners_sindresorhus.json
---@class flemma.ui.Spinners
local M = {}

-- stylua: ignore start
--- Frame sequences for each progress phase
---@type table<string, string[]>
M.FRAMES = {
  waiting = { "⠁", "⠈", "⠐", "⠠", "⢀", "⡀", "⠄", "⠂" },
  thinking = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
  streaming = { "⣾", "⣷", "⣯", "⣟", "⡿", "⢿", "⣻", "⣽" },
  buffering = { "⢄", "⢂", "⢁", "⡁", "⡈", "⡐", "⡠" },
  tool = {
    "⠁", "⠂", "⠄", "⡀", "⡈", "⡐", "⡠", "⣀", "⣁", "⣂", "⣄", "⣌", "⣔", "⣤",
    "⣥", "⣦", "⣮", "⣶", "⣷", "⣿", "⡿", "⠿", "⢟", "⠟", "⡛", "⠛", "⠫", "⢋",
    "⠋", "⠍", "⡉", "⠉", "⠑", "⠡", "⢁",
  },
}
-- stylua: ignore end

--- Animation speed per phase — number of 100ms ticks per frame advance
---@type table<string, integer>
M.SPEED = {
  waiting = 1,
  thinking = 1,
  streaming = 1,
  buffering = 2,
  tool = 2,
}

return M
