if exists("b:current_syntax")
  finish
endif

" Define the role marker matches (e.g., @System:)
syntax match FlemmaRoleSystem '^@System:\s*$' contained
syntax match FlemmaRoleUser '^@You:\s*$' contained
syntax match FlemmaRoleAssistant '^@Assistant:\s*$' contained

" Define the Lua expression match for User messages
syntax match FlemmaUserLuaExpression "{{.\{-}}}" contained

" Define Thinking Tags (for highlighting the tags themselves)
" Matches: <thinking>, <thinking provider:signature="...">, <thinking provider:signature="..."/>
" Pattern [^/>] excludes both / and > so the final > can match
syntax match FlemmaThinkingTag "^<thinking\(\s.*[^/>]\)\?>$" contained
syntax match FlemmaThinkingTag "^<thinking\s.*/>$" contained
syntax match FlemmaThinkingTag "^</thinking>$" contained

" Define Tool Use/Result syntax (for tool calling)
" Tool Use title: **Tool Use:**
syntax match FlemmaToolUseTitle "\*\*Tool Use:\*\*" contained
" Tool Result title: **Tool Result:**
syntax match FlemmaToolResultTitle "\*\*Tool Result:\*\*" contained
" Error marker: (error)
syntax match FlemmaToolResultError "(error)" contained

" Tool Use region (in assistant messages): **Tool Use:** `name` (`id`)
" Note: Tool names and IDs in backticks are handled by treesitter markdown_inline as inline code
syntax region FlemmaToolUse start="\*\*Tool Use:\*\*" end="$" oneline contained contains=FlemmaToolUseTitle
" Tool Result region (in user messages): **Tool Result:** `id` (optional: (error))
syntax region FlemmaToolResult start="\*\*Tool Result:\*\*" end="$" oneline contained contains=FlemmaToolResultTitle,FlemmaToolResultError

" Note: Signature concealment is now handled via extmarks in ui.lua highlight_thinking_tags()
" This avoids needing conceallevel which affects the whole buffer (including frontmatter)

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
syntax region FlemmaSystem start='^@System:\s*$' end='\(^@\(You\|Assistant\):\s*$\)\@=\|\%$' contains=FlemmaRoleSystem,@Markdown
" User region (contains tool results)
syntax region FlemmaUser start='^@You:\s*$' end='\(^@\(System\|Assistant\):\s*$\)\@=\|\%$' contains=FlemmaRoleUser,FlemmaUserLuaExpression,FlemmaToolResult,@Markdown

" Thinking Block Region (nested inside Assistant)
" This region starts with <thinking> or <thinking provider:signature="..."> and ends with </thinking>.
" Self-closing tags like <thinking provider:signature="..."/> are handled by match, not region.
" It contains the tags themselves (FlemmaThinkingTag) and markdown for the content.
syntax region FlemmaThinkingBlock start="^<thinking\(\s.*[^/>]\)\?>$" end="^</thinking>$" keepend contains=FlemmaThinkingTag,@Markdown

" Assistant region contains role markers, markdown, thinking blocks, and tool use
syntax region FlemmaAssistant start='^@Assistant:\s*$' end='\(^@\(System\|You\):\s*$\)\@=\|\%$' contains=FlemmaRoleAssistant,FlemmaThinkingBlock,FlemmaToolUse,@Markdown

let b:current_syntax = "chat"
