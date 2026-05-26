-- Controlled Neovim init for profiling.
-- Only loads treesitter (for markdown highlighting) and optionally Flemma.
-- No copilot, lualine, hexokinase, autopairs, etc.
--
-- Environment variables:
--   FLEMMA_PROFILE_FLEMMA=1  — load Flemma from CWD
--   FLEMMA_PROFILE_DIR       — output directory for results
--   FLEMMA_PROFILE_TS_PATH   — (auto-set by run.sh) path to nvim-treesitter plugin

local ts_path = os.getenv("FLEMMA_PROFILE_TS_PATH")
if not ts_path or ts_path == "" then
  -- Fallback: try to find nvim-treesitter in the default packpath.
  -- This handles cases where the host nvim installs treesitter via a
  -- package manager (lazy.nvim, packer, nix, etc.) and the path was
  -- not passed explicitly.
  for _, candidate in ipairs(vim.api.nvim_get_runtime_file("lua/nvim-treesitter/configs.lua", true)) do
    ts_path = vim.fn.fnamemodify(candidate, ":h:h:h")
    break
  end
end

if ts_path then
  vim.opt.runtimepath:prepend(ts_path)

  -- nvim-treesitter-context lives next to nvim-treesitter in most setups.
  local ts_ctx = ts_path:gsub("nvim%-treesitter$", "nvim-treesitter-context")
  if vim.fn.isdirectory(ts_ctx) == 1 then
    vim.opt.runtimepath:prepend(ts_ctx)
    pcall(function()
      require("treesitter-context").setup({ enable = false })
    end)
  end

  pcall(function()
    require("nvim-treesitter.configs").setup({
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
      },
    })
  end)
end

vim.opt.termguicolors = true
vim.opt.swapfile = false
vim.opt.updatetime = 300

if os.getenv("FLEMMA_PROFILE_FLEMMA") == "1" then
  local cwd = vim.uv.cwd()
  vim.opt.runtimepath:prepend(cwd)

  -- Stub lualine component so Flemma's lualine integration doesn't error
  -- when lualine itself isn't loaded.
  package.loaded["lualine.components.flemma"] = setmetatable({}, {
    __call = function(_, ...)
      local m = dofile(cwd .. "/lua/lualine/components/flemma.lua")
      package.loaded["lualine.components.flemma"] = m
      return m(...)
    end,
  })

  require("flemma").setup({
    model = "anthropic claude-sonnet-4-6",
    parameters = { thinking = "minimal" },
    logging = { enabled = false },
    editing = { auto_write = false },
  })
end
