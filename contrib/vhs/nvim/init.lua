local cwd = vim.fn.getcwd()
vim.opt.runtimepath:prepend(cwd)
vim.opt.runtimepath:prepend(cwd .. "/.vapor/dracula-vim")

vim.opt.termguicolors = true
vim.cmd.colorscheme("dracula")

vim.opt.updatetime = 100
vim.opt.timeoutlen = 100
vim.opt.ttimeoutlen = 10
vim.opt.lazyredraw = false

vim.opt.scrolloff = 999

vim.opt.swapfile = false

require("flemma").setup({
  ruler = {
    hl = "Comment-fg:#101010",
  },
  highlights = {
    system = "Normal",
    user_lua_expression = "Added",
    user_file_reference = "Added",
    thinking_block = "Comment+bg:#000000-fg:#111111",
  },
  line_highlights = {
    frontmatter = "Normal+bg:#100310",
    system = "Normal+bg:#100300",
    user = "Normal+bg:#031010",
    assistant = "Normal",
  },
  notify = {
    enabled = false,
  },
  editing = {
    auto_write = true,
  },
})

vim.cmd("lcd .vapor/")
