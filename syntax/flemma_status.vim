if exists("b:current_syntax")
  finish
endif

" Title
syntax match FlemmaStatusTitle "^Flemma Status$"

" Separator lines
syntax match FlemmaStatusSeparator "^[═─]\+$"

" Section headers (unindented text that starts a section)
syntax match FlemmaStatusSection "^Provider$"
syntax match FlemmaStatusSection "^Parameters (merged)$"
syntax match FlemmaStatusSection "^Autopilot$"
syntax match FlemmaStatusSection "^Sandbox$"
syntax match FlemmaStatusSection "^Tools .*$"
syntax match FlemmaStatusSection "^Config (full)$"

" Key labels (indented key: value pairs)
syntax match FlemmaStatusKey "^\s\+\zs\S\+\ze:" contained
syntax match FlemmaStatusKeyLine "^\s\+\S\+:.*$" contains=FlemmaStatusKey,FlemmaStatusEnabled,FlemmaStatusDisabled,FlemmaStatusNumber,FlemmaStatusParen

" Boolean-like values
syntax keyword FlemmaStatusEnabled enabled true yes contained
syntax keyword FlemmaStatusDisabled disabled false no contained

" Numbers
syntax match FlemmaStatusNumber "\<\d\+\(\.\d\+\)\?\>" contained

" Parenthesized annotations
syntax match FlemmaStatusParen "([^)]*)" contained

" Frontmatter override annotations
syntax match FlemmaStatusFrontmatter "^\s\+⚑ frontmatter override:.*$"

" Tool markers
syntax match FlemmaStatusToolEnabled "^\s\+✓ .*$"
syntax match FlemmaStatusToolDisabled "^\s\+✗ .*$"

" Highlight groups
highlight default link FlemmaStatusTitle Title
highlight default link FlemmaStatusSeparator NonText
highlight default link FlemmaStatusSection Type
highlight default link FlemmaStatusKey Identifier
highlight default link FlemmaStatusEnabled DiagnosticOk
highlight default link FlemmaStatusDisabled DiagnosticWarn
highlight default link FlemmaStatusNumber Number
highlight default link FlemmaStatusParen Comment
highlight default link FlemmaStatusFrontmatter Special
highlight default link FlemmaStatusToolEnabled DiagnosticOk
highlight default link FlemmaStatusToolDisabled DiagnosticWarn

let b:current_syntax = "flemma_status"
