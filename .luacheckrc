-- Neovim runtime globals (vim, utf8, table.unpack are injected by Neovim)
stds.nvim = {
  globals = {
    "vim",
  },
  read_globals = {
    "utf8",
    table = { fields = { "unpack" } },
  },
}

-- Plenary/busted test globals
stds.busted = {
  read_globals = {
    "describe",
    "before_each",
    "after_each",
    "it",
    "assert",
    "pending",
    "spy",
    "stub",
    "mock",
  },
}

std = "luajit+nvim"
cache = true
max_line_length = false

-- 212 = unused argument.
-- Allow unused `self` everywhere — Lua OOP convention for base class and
-- interface methods that define the signature but don't use `self`.
ignore = {
  "212/self",
}

files["tests/**/*.lua"] = {
  std = "+busted",
}
