local cwd = vim.fn.getcwd()
vim.opt.runtimepath:prepend(cwd)
vim.opt.runtimepath:prepend(cwd .. "/.vapor/catppuccin-nvim")

vim.opt.termguicolors = true
vim.cmd.colorscheme("catppuccin_frappe")

vim.opt.updatetime = 100
vim.opt.timeoutlen = 100
vim.opt.ttimeoutlen = 10
vim.opt.lazyredraw = false

vim.opt.scrolloff = 999

vim.opt.swapfile = false

vim.cmd("lcd .vapor/")

vim.api.nvim_set_hl(0, "Folded", { fg = "#8f8f8f" })

local parser_install_dir = vim.fn.stdpath("cache") .. "/treesitters"

vim.fn.mkdir(parser_install_dir, "p")

vim.opt.runtimepath:prepend(parser_install_dir)

require("nvim-treesitter.configs").setup({
  parser_install_dir = parser_install_dir,
  ensure_installed = {
    "markdown",
    "markdown_inline",
    "lua",
    "json",
  },
  highlight = {
    enable = true,
    additional_vim_regex_highlighting = false,
  },
  install = {
    notify_compile_progress = false,
  },
})

require("treesitter-context").setup({
  enable = false,
})

require("flemma").setup({
  provider = "anthropic",
  model = "claude-haiku-4-5",
  parameters = {
    thinking = "medium",
  },
  highlights = {
    system = "Comment+fg:#101010",
    assistant = "Normal+bg:#102020",
    thinking_block = "Normal+bg:#102020-fg:#606060",
  },
  ruler = {
    hl = "Normal-fg:#808080",
  },
  line_highlights = {
    user = "Normal",
    system = "Comment+bg:#101010",
    assistant = "Normal+bg:#102020",
  },
  notify = {
    enabled = false,
  },
  editing = {
    auto_write = true,
  },
})

require("lualine").setup({
  sections = {
    lualine_a = {},
    lualine_b = {
      { "filename", path = 1, symbols = { modified = "∗" } },
    },
    lualine_c = {},
    lualine_x = {
      { "flemma", icon = "🧠" },
    },
    lualine_y = {},
    lualine_z = {},
  },
})
