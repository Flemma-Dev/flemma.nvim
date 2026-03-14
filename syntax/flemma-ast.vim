if exists("b:current_syntax")
  finish
endif

" Full header line region — contains all inline elements
syntax match FlemmaAstHeaderLine "^\s*\(document\|message\|text\|expression\|thinking\|tool_use\|tool_result\|aborted\|frontmatter\)\s*.*$" contains=FlemmaAstNodeKind,FlemmaAstPosition,FlemmaAstFieldName,FlemmaAstFieldValue,FlemmaAstBoolean

" Node kind keywords (leading word on header lines)
syntax match FlemmaAstNodeKind "\(document\|message\|text\|expression\|thinking\|tool_use\|tool_result\|aborted\|frontmatter\)" contained

" Position ranges: [5 - 20] or [5:3 - 20:45]
syntax match FlemmaAstPosition "\[.\{-}\]" contained

" Inline field names: key= or key.subkey=
syntax match FlemmaAstFieldName "\s\zs\w\+\(\.\w\+\)*\ze=" contained

" Inline field values: ="string"
syntax match FlemmaAstFieldValue '="[^"]*"' contained

" Boolean values in inline fields
syntax match FlemmaAstBoolean "=\zs\(true\|false\)\ze\(\s\|$\)" contained

" Multiline key labels (key:)
syntax match FlemmaAstMultilineKey "^\s\+\zs\(value\|content\|code\|input\)\ze:$"

" Child summary at depth=1
syntax match FlemmaAstChildSummary "^\s\+\zs\(segments\|messages\|frontmatter\): \d\+ child\(ren\)\?"

" Whitespace and newline markers — resolved at runtime from the user's listchars setting
execute 'syntax match FlemmaAstNewline "' . luaeval("require('flemma.utilities.display').get_newline_char()") . '"'
execute 'syntax match FlemmaAstWhitespace "' . luaeval("require('flemma.utilities.display').get_lead_char()") . '"'
execute 'syntax match FlemmaAstWhitespace "' . luaeval("require('flemma.utilities.display').get_trail_char()") . '"'
execute 'syntax match FlemmaAstWhitespace "' . luaeval("require('flemma.utilities.display').get_tab_char()") . '"'

" Highlight links (FlemmaAstHeaderLine is transparent — it only contains)
highlight default link FlemmaAstNodeKind Keyword
highlight default link FlemmaAstPosition Comment
highlight default link FlemmaAstFieldName Identifier
highlight default link FlemmaAstFieldValue String
highlight default link FlemmaAstBoolean Boolean
highlight default link FlemmaAstMultilineKey Label
highlight default link FlemmaAstChildSummary Comment
highlight default link FlemmaAstNewline NonText
highlight default link FlemmaAstWhitespace Whitespace

let b:current_syntax = "flemma-ast"
