if exists("b:current_syntax")
  finish
endif

" Section labels
syntax keyword FlemmaNotifyLabel Request Session Cache Requests

" Dotted leaders (middle dot U+00B7)
syntax match FlemmaNotifyLeader "·"

" Cost values ($N.NN)
syntax match FlemmaNotifyCost "\$\d\+\.\d\+"

" Model names (between backticks, concealed)
syntax region FlemmaNotifyModel matchgroup=Conceal start=/`/ end=/`/ concealends

" Token detail lines (lines starting with spaces then ↑ or ↓)
syntax match FlemmaNotifyDim "^\s\+[↑↓].*$"

" Highlight groups
highlight default link FlemmaNotifyLabel Type
highlight default link FlemmaNotifyLeader Comment
highlight default FlemmaNotifyCost gui=bold
highlight default link FlemmaNotifyModel Special
highlight default link FlemmaNotifyDim Comment

" Cache extmark highlight groups (applied dynamically in Lua)
highlight default link FlemmaNotifyCacheGood DiagnosticOk
highlight default link FlemmaNotifyCacheBad DiagnosticWarn

let b:current_syntax = "flemma_notify"
