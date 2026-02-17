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
syntax match FlemmaStatusConfigTitle "^Config (full)$" contained

" Key labels (indented key: value pairs)
syntax match FlemmaStatusKey "^\s\+\zs[^:]\+\ze:" contained
syntax match FlemmaStatusKeyLine "^\s\+[^:]\+:.*$" contains=FlemmaStatusKey,FlemmaStatusEnabled,FlemmaStatusDisabled,FlemmaStatusNumber,FlemmaStatusParen,FlemmaStatusStrikethrough,FlemmaStatusComment

" Boolean-like values
syntax keyword FlemmaStatusEnabled enabled true yes contained
syntax keyword FlemmaStatusDisabled disabled false no contained

" Numbers
syntax match FlemmaStatusNumber "\<\d\+\(\.\d\+\)\?\>" contained

" Parenthesized annotations
syntax match FlemmaStatusParen "([^)]*)" contained

" Strikethrough for overridden values (~~value~~)
syntax region FlemmaStatusStrikethrough matchgroup=Conceal start=/\~\~/ end=/\~\~/ concealends contained

" Frontmatter override comment (# frontmatter override)
syntax match FlemmaStatusComment "#.*$" contained

" Config dump region with embedded Lua highlighting
syntax region FlemmaStatusConfigBlock start="^Config (full)$" end="\%$" keepend contains=FlemmaStatusConfigTitle,FlemmaStatusConfigSeparator,@FlemmaStatusLua

" Tool markers
syntax match FlemmaStatusToolEnabled "^\s\+✓ .*$"
syntax match FlemmaStatusToolDisabled "^\s\+✗ .*$"

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
highlight default link FlemmaStatusParen Comment
highlight default FlemmaStatusStrikethrough gui=strikethrough
highlight default link FlemmaStatusComment Comment
highlight default link FlemmaStatusToolEnabled DiagnosticOk
highlight default link FlemmaStatusToolDisabled DiagnosticWarn

let b:current_syntax = "flemma_status"
