if exists("b:current_syntax")
  finish
endif

" Define the role marker matches (e.g., @System:)
syntax match FlemmaRoleSystem '^@System:' contained
syntax match FlemmaRoleUser '^@You:' contained
syntax match FlemmaRoleAssistant '^@Assistant:' contained

" Define the Lua expression match for User messages
syntax match FlemmaUserLuaExpression "{{.\{-}}}" contained

" Define the File Reference match for User messages: @./path or @../path, excluding trailing punctuation
" @\v(\.\.?\/)\S*[^[:punct:]\s]
" @                  - literal @
" \v                 - very magic
" (\.\.?\/)          - group: literal dot, optional literal dot, literal slash (./ or ../)
" \S*                - zero or more non-whitespace characters
" [^[:punct:]\s]     - a character that is NOT punctuation and NOT whitespace (ensures end is not punctuation)
syntax match FlemmaUserFileReference "@\v(\.\.?\/)\S*[^[:punct:]\s]" contained

" Define Thinking Tags (for highlighting the tags themselves)
syntax match FlemmaThinkingTag "^<thinking>$" contained
syntax match FlemmaThinkingTag "^</thinking>$" contained

" Define Frontmatter Tags (for highlighting the delimiters themselves)
syntax match FlemmaFrontmatterTag "^```lua$" contained
syntax match FlemmaFrontmatterTag "^```$" contained

" Define regions
" Frontmatter Block Region (top-level)
" This region starts with ```lua on the first line of the file and ends with ```.
" It contains the tags themselves (FlemmaFrontmatterTag) and Lua syntax for the content.
syntax region FlemmaFrontmatterBlock start="\%1l^```lua$" end="^```$" keepend contains=FlemmaFrontmatterTag,@Lua

" System region
syntax region FlemmaSystem start='^@System:' end='\(^@\(You\|Assistant\):\)\@=\|\%$' contains=FlemmaRoleSystem,@Markdown
" User region
syntax region FlemmaUser start='^@You:' end='\(^@\(System\|Assistant\):\)\@=\|\%$' contains=FlemmaRoleUser,FlemmaUserLuaExpression,FlemmaUserFileReference,@Markdown

" Thinking Block Region (nested inside Assistant)
" This region starts with <thinking> and ends with </thinking>.
" It contains the tags themselves (FlemmaThinkingTag) and markdown for the content.
syntax region FlemmaThinkingBlock start="^<thinking>$" end="^</thinking>$" keepend contains=FlemmaThinkingTag,@Markdown

" Assistant region contains role markers, markdown, and thinking blocks
syntax region FlemmaAssistant start='^@Assistant:' end='\(^@\(System\|You\):\)\@=\|\%$' contains=FlemmaRoleAssistant,FlemmaThinkingBlock,@Markdown

let b:current_syntax = "chat"
