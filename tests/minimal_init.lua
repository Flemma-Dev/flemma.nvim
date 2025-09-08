-- Add the project root to the runtime path to find the 'lua' directory
vim.opt.rtp:append(os.getenv("PROJECT_ROOT"))

-- Turn off swapfile during tests
vim.opt.swapfile = false

-- Initialize the plugin with default settings
require("flemma").setup({})
