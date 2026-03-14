setlocal foldmethod=expr
setlocal foldexpr=v:lua.require('flemma.ast.dump').foldexpr(v:lnum)
setlocal foldtext=v:lua.require('flemma.ast.dump').foldtext()
setlocal foldlevel=99
setlocal nomodifiable
setlocal bufhidden=wipe
