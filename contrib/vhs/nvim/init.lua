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
  provider = "anthropic",
  model = "claude-haiku-4-5",
  parameters = {
    thinking = "medium",
  },
  tools = {
    modules = {
      "extras.flemma.tools.calculator",
    },
    auto_approve = {
      "$standard",
      "calculator",
    },
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
