-- Add the project root to the runtime path to find the 'lua' directory
vim.opt.rtp:append(vim.fn.getcwd())

-- Add plenary to the runtime path
local plenary_path = os.getenv("PLENARY_PATH")
if not plenary_path or plenary_path == "" then
  print("Error: PLENARY_PATH must be set.")
  print("Please run this from within the 'nix develop' shell.")
  vim.cmd("cquit")
end
vim.opt.rtp:append(plenary_path)
