if exists("b:current_syntax")
  finish
endif

" Keywords
syntax keyword FlemmaNotifyKeyword Request Session

" Numbers including decimals (with optional $ prefix)
syntax match FlemmaNotifyNumber "\$\?\<\d\+\(\.\d\+\)\?\>"

" Model names (between backticks)
syntax region FlemmaNotifyModel matchgroup=Conceal start=/`/ end=/`/ concealends

" Highlight groups
highlight default link FlemmaNotifyKeyword Type
highlight default FlemmaNotifyNumber gui=bold
highlight default link FlemmaNotifyModel Special

let b:current_syntax = "flemma_notify"
