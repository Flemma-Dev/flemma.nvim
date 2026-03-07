if exists("b:current_syntax")
  finish
endif

" Include Lua syntax for the verbose config dump region
syntax include @FlemmaStatusLua syntax/lua.vim
unlet! b:current_syntax

" Title
syntax match FlemmaStatusTitle "^Flemma Status$"

" Separator lines
syntax match FlemmaStatusTitleSeparator "^[═]\+$"
syntax match FlemmaStatusSeparator "^[─]\+$"
syntax match FlemmaStatusConfigSeparator "^[─]\+$" contained

" Section headers (unindented text that starts a section)
syntax match FlemmaStatusSection "^Provider$"
syntax match FlemmaStatusSection "^Parameters (merged)$"
syntax match FlemmaStatusSection "^Autopilot$"
syntax match FlemmaStatusSection "^Sandbox$"
syntax match FlemmaStatusSection "^Tools .*$"
syntax match FlemmaStatusSection "^Approval\( .*\)\?$"
syntax match FlemmaStatusConfigTitle "^Config (full)$" contained
syntax match FlemmaStatusConfigTitle "^Model Info$" contained

" Key labels (indented key: value pairs)
syntax match FlemmaStatusKey "^\s\+\zs[^:]\+\ze:" contained
syntax match FlemmaStatusKeyLine "^\s\+[^:]\+:.*$" contains=FlemmaStatusKey,FlemmaStatusEnabled,FlemmaStatusDisabled,FlemmaStatusNumber,FlemmaStatusParen,FlemmaStatusStrikethrough,FlemmaStatusModelValue

" Model value (version suffix highlighted separately from regular numbers)
" Captures from the first digit to end: claude-sonnet-›4-6‹, gemini-›2.5-pro‹, gpt-›5.4-pro‹
syntax match FlemmaStatusModelValue "\(model: \)\@<=\S\+$" contained contains=FlemmaStatusVersion
syntax match FlemmaStatusVersion "\d\S*" contained

" Boolean-like values
syntax keyword FlemmaStatusEnabled enabled true yes contained
syntax keyword FlemmaStatusDisabled disabled false no contained

" Numbers, dollar amounts, and token counts (200K, 1M)
syntax match FlemmaStatusNumber "\<\d\+\(\.\d\+\)\?\>" contained
syntax match FlemmaStatusNumber "\$\d\+\(\.\d\+\)\?" contained
syntax match FlemmaStatusNumber "\<\d\+[KM]\>" contained
syntax match FlemmaStatusNumber "\<\d\+%" contained

" Parenthesized annotations
syntax match FlemmaStatusParen "([^)]*)" contained

" Strikethrough for overridden values (~~value~~)
syntax region FlemmaStatusStrikethrough matchgroup=Conceal start=/\~\~/ end=/\~\~/ concealends contained

" Legend
syntax match FlemmaStatusLegend "^✲.*$"

" Config dump region with embedded Lua highlighting
syntax region FlemmaStatusConfigBlock start="^\(Model Info\|Config (full)\)$" end="\%$" keepend contains=FlemmaStatusConfigTitle,FlemmaStatusConfigSeparator,@FlemmaStatusLua

" Tool and approval markers
syntax match FlemmaStatusToolEnabled "^\s\+✓ .*$"
syntax match FlemmaStatusToolDisabled "^\s\+✗ .*$"
syntax match FlemmaStatusToolPending "^\s\+⋯ .*$"

" Highlight groups
highlight default link FlemmaStatusTitle Title
highlight default link FlemmaStatusTitleSeparator Title
highlight default link FlemmaStatusSeparator NonText
highlight default link FlemmaStatusConfigTitle Title
highlight default link FlemmaStatusConfigSeparator Title
highlight default link FlemmaStatusSection Type
highlight default link FlemmaStatusKey Keyword
highlight default link FlemmaStatusEnabled DiagnosticOk
highlight default link FlemmaStatusDisabled DiagnosticWarn
highlight default link FlemmaStatusNumber Number
highlight default link FlemmaStatusVersion Special
highlight default link FlemmaStatusParen Comment
highlight default FlemmaStatusStrikethrough gui=strikethrough
highlight default link FlemmaStatusLegend Comment
highlight default link FlemmaStatusToolEnabled DiagnosticOk
highlight default link FlemmaStatusToolDisabled DiagnosticWarn
highlight default link FlemmaStatusToolPending DiagnosticInfo

let b:current_syntax = "flemma_status"
