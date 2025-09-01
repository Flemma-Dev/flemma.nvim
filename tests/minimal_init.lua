-- Add the project root to the runtime path to find the 'lua' directory
vim.opt.rtp:append(os.getenv("PROJECT_ROOT"))

-- Initialize the plugin with default settings
require("claudius").setup({})
