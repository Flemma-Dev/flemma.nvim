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

-- Allow unused `self` everywhere — Lua OOP convention for base class and
-- interface methods that define the signature but don't use `self`.
-- Allow `_`-prefixed variables to be unused (standard Lua convention for
-- intentionally ignored return values and parameters).
ignore = {
  "212/self",
  "211/_.*", -- unused variable
  "212/_.*", -- unused argument
  "231/_.*", -- variable is set but never accessed
}

-- Base provider defines interface methods with intentionally unused arguments
files["lua/flemma/provider/base.lua"] = {
  ignore = { "212" }, -- unused arguments (interface stubs)
}

-- Provider implementations have intentional empty branches for skipping `thinking` nodes
files["lua/flemma/provider/providers/*.lua"] = {
  ignore = { "542" }, -- empty if branches (intentional skip patterns)
}

files["tests/**/*.lua"] = {
  std = "+busted",
}
