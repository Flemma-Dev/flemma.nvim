vim.opt_local.foldmethod = "expr"
vim.opt_local.foldexpr = "v:lua.require('flemma.ast.dump').foldexpr(v:lnum)"
vim.opt_local.foldtext = "v:lua.require('flemma.ast.dump').foldtext()"
vim.opt_local.foldlevel = 99
vim.opt_local.modifiable = false
vim.opt_local.bufhidden = "wipe"
