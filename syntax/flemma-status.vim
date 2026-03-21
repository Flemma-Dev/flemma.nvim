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
syntax match FlemmaStatusSection "^Tools .*$" contains=FlemmaStatusLayerSource
syntax match FlemmaStatusSection "^Approval\( .*\)\?$"

" Verbose section headers
syntax match FlemmaStatusSection "^Layer Ops$"
syntax match FlemmaStatusSection "^Resolved Config Tree$"
syntax match FlemmaStatusConfigTitle "^Config (full)$" contained
syntax match FlemmaStatusConfigTitle "^Model Info$"

" Layer source indicators (D, S, R, F, or combinations like S+F, D+S+R+F)
" Right-aligned at end of lines — matches after 2+ spaces
syntax match FlemmaStatusLayerSource "\s\{2,\}\zs[DSRF]\(+[DSRF]\)*\s*$" contained

" Key labels (indented key: value pairs)
syntax match FlemmaStatusKey "^\s\+\zs[^:]\+\ze:" contained
syntax match FlemmaStatusKeyLine "^\s\+[^:]\+:.*$" contains=FlemmaStatusKey,FlemmaStatusEnabled,FlemmaStatusDisabled,FlemmaStatusNumber,FlemmaStatusParen,FlemmaStatusStrikethrough,FlemmaStatusModelValue,FlemmaStatusLayerSource

" Model value (version suffix highlighted separately from regular numbers)
" Captures from the first digit to end: claude-sonnet-›4-6‹, gemini-›2.5-pro‹, gpt-›5.4-pro‹
syntax match FlemmaStatusModelValue "\(model: \)\@<=\S\+\(\s\+[DSRF]\(+[DSRF]\)*\)\?" contained contains=FlemmaStatusVersion,FlemmaStatusLayerSource
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
syntax match FlemmaStatusLegend "^⊡.*$"

" Verbose: Layer ops section
syntax match FlemmaStatusLayerHeader "^\[.\].*$" contains=FlemmaStatusLayerLabel,FlemmaStatusParen
syntax match FlemmaStatusLayerLabel "\[\zs[DSRF]\ze\]" contained
syntax match FlemmaStatusOpEntry "^\s\+\(set\|append\|remove\|prepend\)\s\+.*$" contains=FlemmaStatusOpName,FlemmaStatusOpArrow,FlemmaStatusOpPath
syntax match FlemmaStatusOpName "^\s\+\zs\(set\|append\|remove\|prepend\)\ze\s" contained
syntax match FlemmaStatusOpPath "\(set\|append\|remove\|prepend\)\s\+\zs\S\+\ze\s" contained
syntax match FlemmaStatusOpArrow "->" contained

" Verbose: Resolved config tree entries (indented name + value + source)
syntax match FlemmaStatusResolvedLine "^\s\+\S.*[DSRF]\(+[DSRF]\)*\s*$" contains=FlemmaStatusLayerSource,FlemmaStatusNumber,FlemmaStatusEnabled,FlemmaStatusDisabled

" Model Info region with embedded Lua highlighting (vim.inspect output)
syntax region FlemmaStatusModelBlock start="^Model Info$" end="\ze\n\(Layer Ops\|Config (full)\|$\)" keepend contains=FlemmaStatusConfigTitle,FlemmaStatusConfigSeparator,@FlemmaStatusLua

" Config dump region with embedded Lua highlighting (fallback verbose mode)
syntax region FlemmaStatusConfigBlock start="^Config (full)$" end="\%$" keepend contains=FlemmaStatusConfigTitle,FlemmaStatusConfigSeparator,@FlemmaStatusLua

" Tool and approval markers
syntax match FlemmaStatusToolEnabled "^\s\+✓ .*$"
syntax match FlemmaStatusToolDisabled "^\s\+✗ .*$"
syntax match FlemmaStatusToolPending "^\s\+⋯ .*$"
syntax match FlemmaStatusBooting "^\s\+⏳ .*$"

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
highlight default link FlemmaStatusBooting WarningMsg
highlight default link FlemmaStatusLayerSource Special
highlight default link FlemmaStatusLayerHeader Type
highlight default link FlemmaStatusLayerLabel Special
highlight default link FlemmaStatusOpName Keyword
highlight default link FlemmaStatusOpPath Identifier
highlight default link FlemmaStatusOpArrow Operator
highlight default link FlemmaStatusResolvedLine Normal

let b:current_syntax = "flemma-status"
