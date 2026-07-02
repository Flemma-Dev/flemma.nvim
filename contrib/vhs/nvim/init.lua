local function get_current_script_path()
  local script = debug.getinfo(1, "S").source
  return script:sub(2) -- Removes the '@' prefix
end

local cwd = get_current_script_path():match("(.*/)") .. "../../../"

vim.opt.runtimepath:prepend(cwd)
vim.opt.runtimepath:prepend(cwd .. ".vapor/catppuccin/nvim.git")
vim.opt.runtimepath:prepend(cwd .. ".vapor/NStefan002/screenkey.nvim.git")

vim.opt.termguicolors = true
vim.cmd.colorscheme("catppuccin-mocha")

vim.opt.updatetime = 100
vim.opt.timeoutlen = 100
vim.opt.ttimeoutlen = 10
vim.opt.lazyredraw = false

vim.opt.scrolloff = 999
vim.opt.listchars = {
  eol = " ",
}

vim.opt.swapfile = false

vim.api.nvim_set_hl(0, "Folded", { fg = "#8f8f8f" })

local parser_install_dir = vim.fn.stdpath("cache") .. "/treesitters"

vim.fn.mkdir(parser_install_dir, "p")

-- nvim-treesitter's `main` branch (Neovim 0.11+) replaced the classic
-- `require("nvim-treesitter.configs").setup{}` API. Parsers are installed
-- explicitly via the Makefile's screencast pre-step; `setup{ install_dir }`
-- prepends that directory to the runtimepath so the parsers are found.
require("nvim-treesitter").setup({
  install_dir = parser_install_dir,
})

-- The classic API auto-enabled highlighting for every parser-backed filetype;
-- the new API does not, so start Treesitter per buffer. `.chat` buffers render
-- through the markdown parser (registered by flemma.setup), so include `chat`.
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "chat", "markdown", "lua", "json" },
  callback = function(ev)
    pcall(vim.treesitter.start, ev.buf)
  end,
})

-- Keep nvim-treesitter-context disabled during recording — it rides in on the dev-shell runtimepath
-- and its sticky context header is clutter on a clean screencast.
require("treesitter-context").setup({
  enable = false,
})

require("screenkey").setup({
  disable = {
    modes = { "i", "c" },
  },
  keys = {
    ["<CR>"] = "Enter",
  },
})

require("screenkey").toggle_statusline_component()

require("flemma").setup({
  provider = "moonshot",
  model = "kimi-k2.6",
  parameters = {
    -- Kimi's thinking is binary on/off (no budget knob), and "on" spends ~43s
    -- reasoning per turn — dead air on a screencast. Keep it off for Kimi
    -- (temperature drops to 0.6); Kimi still runs the tool dance and streams the
    -- status update, just without the reasoning phase. The $haiku switch restores
    -- a small thinking budget for the snappy Anthropic follow-up.
    thinking = false,
  },
  -- Named preset the tape switches to mid-conversation to demo model switching.
  -- The switch carries a `thinking=minimal` modeline arg
  -- (`:Flemma switch $haiku thinking=minimal`) so the fast Anthropic model gets a
  -- small thinking budget back for the quick "just my items" follow-up, while
  -- Kimi wrote the heavy first answer with thinking off.
  presets = {
    ["$haiku"] = {
      provider = "anthropic",
      model = "claude-haiku-4-5",
      thinking = "minimal",
    },
  },
  tools = {
    modules = {
      "demo.meetings",
    },
    auto_approve = {
      "$standard",
      "meetings.get_transcript",
    },
    auto_approve_sandboxed = false,
  },
  editing = {
    auto_write = true,
  },
  turns = {
    padding = { 1, 1 },
  },
})

require("lualine").setup({
  sections = {
    lualine_a = {},
    lualine_b = {
      { "filename", path = 1, symbols = { modified = "∗" } },
    },
    lualine_c = {
      {
        function()
          return require("screenkey").get_keys()
        end,
        icon = "⌨ ",
      },
    },
    lualine_x = {
      { "flemma", icon = "∴" },
    },
    lualine_y = {},
    lualine_z = {},
  },
})

-- Demo-only: send up an invisible, numbered beacon on each settled exchange
-- so the VHS tape can wait on a real event instead of a blind Sleep.
require("demo.beacon").setup()
