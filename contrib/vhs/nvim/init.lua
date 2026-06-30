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
