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
" Matches: <thinking>, <thinking provider:signature="...">, <thinking provider:signature="..."/>
" Pattern [^/>] excludes both / and > so the final > can match
syntax match FlemmaThinkingTag "^<thinking\(\s.*[^/>]\)\?>$" contained
syntax match FlemmaThinkingTag "^<thinking\s.*/>$" contained
syntax match FlemmaThinkingTag "^</thinking>$" contained

" Define Frontmatter Tags (for highlighting the delimiters themselves)
" Only match supported languages: lua, json
syntax match FlemmaFrontmatterTag "^```\(lua\|json\)$" contained
syntax match FlemmaFrontmatterTag "^```$" contained

" Define regions
" Frontmatter Block Regions (top-level)
" These regions start with ```<language> on the first line of the file and end with ```.
" Each contains the tags themselves (FlemmaFrontmatterTag) and language-specific syntax.
syntax region FlemmaFrontmatterBlockLua start="\%1l^```lua$" end="^```$" keepend contains=FlemmaFrontmatterTag,@Lua
syntax region FlemmaFrontmatterBlockJson start="\%1l^```json$" end="^```$" keepend contains=FlemmaFrontmatterTag,@JSON

" System region
syntax region FlemmaSystem start='^@System:' end='\(^@\(You\|Assistant\):\)\@=\|\%$' contains=FlemmaRoleSystem,@Markdown
" User region
syntax region FlemmaUser start='^@You:' end='\(^@\(System\|Assistant\):\)\@=\|\%$' contains=FlemmaRoleUser,FlemmaUserLuaExpression,FlemmaUserFileReference,@Markdown

" Thinking Block Region (nested inside Assistant)
" This region starts with <thinking> or <thinking provider:signature="..."> and ends with </thinking>.
" Self-closing tags like <thinking provider:signature="..."/> are handled by match, not region.
" It contains the tags themselves (FlemmaThinkingTag) and markdown for the content.
syntax region FlemmaThinkingBlock start="^<thinking\(\s.*[^/>]\)\?>$" end="^</thinking>$" keepend contains=FlemmaThinkingTag,@Markdown

" Assistant region contains role markers, markdown, and thinking blocks
syntax region FlemmaAssistant start='^@Assistant:' end='\(^@\(System\|You\):\)\@=\|\%$' contains=FlemmaRoleAssistant,FlemmaThinkingBlock,@Markdown

let b:current_syntax = "chat"
