--- Standard library populator for the Flemma template environment.
--- Provides access to string, table, math, utf8, vim, and essential Lua globals.
---@class flemma.templating.builtins.Stdlib : flemma.templating.Populator
local M = {}

local symbols = require("flemma.symbols")

M.name = "stdlib"
M.priority = 100

---Populate the environment with standard library functions and globals.
---@param env table
function M.populate(env)
  -- String manipulation
  env.string = {
    byte = string.byte,
    char = string.char,
    find = string.find,
    format = string.format,
    gmatch = string.gmatch,
    gsub = string.gsub,
    len = string.len,
    lower = string.lower,
    match = string.match,
    rep = string.rep,
    reverse = string.reverse,
    sub = string.sub,
    upper = string.upper,
  }

  -- Table operations for data structuring
  env.table = {
    concat = table.concat,
    insert = table.insert,
    remove = table.remove,
    sort = table.sort,
    unpack = table.unpack,
  }

  -- Math for calculations in templates
  env.math = {
    abs = math.abs,
    ceil = math.ceil,
    floor = math.floor,
    max = math.max,
    min = math.min,
    random = math.random,
    randomseed = math.randomseed,
    round = math.floor, -- common alias
    pi = math.pi,
  }

  -- UTF-8 support for unicode string handling (available in Lua 5.3+, nil in LuaJIT)
  env.utf8 = utf8 ---@diagnostic disable-line: undefined-global

  -- Neovim API functions required by include() and path resolution
  env.vim = {
    fn = {
      fnamemodify = vim.fn.fnamemodify,
      getcwd = vim.fn.getcwd,
      filereadable = vim.fn.filereadable,
      simplify = vim.fn.simplify,
    },
    fs = {
      normalize = vim.fs.normalize,
      abspath = vim.fs.abspath,
    },
  }

  -- Essential functions for template operation
  env.assert = assert
  env.error = error
  env.ipairs = ipairs
  env.pairs = pairs
  env.pcall = pcall
  env.select = select
  env.tonumber = tonumber
  env.tostring = tostring
  env.type = type
  env.print = print

  -- Useful constants
  env._VERSION = _VERSION

  -- Symbols table: opaque table keys for include() mode flags.
  -- Mirrors flemma.symbols -- user code writes { [symbols.BINARY] = true }.
  -- "symbols" is a reserved key and must not be overwritten by frontmatter variables.
  env.symbols = {
    BINARY = symbols.INCLUDE_BINARY,
    MIME = symbols.INCLUDE_MIME,
  }
end

return M
