.PHONY: default test lint check

default:
	@echo "Usage: make [$(shell cat ${MAKEFILE_LIST} | grep -E '^[a-zA-Z_-]+:' | sed 's/:.*//g' | grep -v '^default' | tr '\n' '|' | sed 's/|$$//')]"
	@cat ${MAKEFILE_LIST} | grep -B1 -E '^[a-zA-Z_-]+:' | sed 's/:.*//' | sed 's/^# *//' | tac | grep -v '^--' | sed 'N;s/\n/ - /' | grep -v '^default' | tac | sed 's/^/  /'

# Run the test suite
test:
	nvim --headless --noplugin -u tests/minimal.vim -c "PlenaryBustedDirectory tests/flemma/ {minimal_init = 'tests/minimal_init.lua'}"

# Run luacheck on the Lua files
lint:
	luacheck lua/ tests/

# Run lua-language-server type checker on production code
check:
	@# VIMRUNTIME must be set so .luarc-check.lua can locate the Neovim runtime Lua stubs.
	@# On NixOS, `nvim` might be symlinked to a store path, so we resolve it with `readlink -f`.
	VIMRUNTIME=$(shell dirname $(shell dirname $(shell readlink -f $(shell which nvim))))/share/nvim/runtime \
		lua-language-server --check lua/ --configpath ../.luarc-check.lua

# Update models and pricing using Amp (AI agent)
.PHONY: update-models
update-models:
	cat contrib/amp/prompt-update-models-and-pricing.txt | sed 's@{{date}}@'"$(shell date +%Y-%m-%d)"'@g' | flemma-amp

# Launch Flemma.nvim from local directory
.PHONY: develop
develop:
	@-rm ~/.cache/nvim/flemma.log
	@nvim --cmd "set runtimepath^=`pwd`"												\
		-c "lua require(\"flemma\").setup({												\
			provider = \"anthropic\",													\
			model = \"claude-haiku-4-5\",												\
			parameters = { max_tokens = 8000, thinking_budget = 4000 },					\
			presets = { [\"\$$gpt\"] = \"openai gpt-5.2 reasoning=low\" },				\
			logging = { enabled = true },												\
			editing = { auto_write = true },											\
			pricing = { enabled = true },												\
		})"																				\
		-c ":edit $$HOME/.cache/nvim/flemma.log"										\
		-c ":tabedit example.chat"

# Launch Flemma.nvim in a new Ghostty terminal and screenshot
.PHONY: screenshot ghostty-screenshot-cmd
screenshot: .vapor/dracula-vim
	@ghostty																			\
		--gtk-titlebar=true																\
		--window-decoration=auto														\
		--window-width=96																\
		--window-height=40																\
		--maximize=false																\
		--font-family="Berkeley Mono"													\
		--font-family-bold="Berkeley Mono, Bold"										\
		--font-family-italic="Berkeley Mono, Regular Oblique"							\
		--font-family-bold-italic="Berkeley Mono, Bold Oblique"							\
		--font-size=14																	\
		--gtk-custom-css="`pwd`/contrib/ghostty/gtk-overlay.css"						\
		-e sh -c "cd `pwd` && make ghostty-screenshot-cmd"

.vapor/dracula-vim:
	@mkdir -p .vapor
	git clone --depth 1 https://github.com/dracula/vim.git .vapor/dracula-vim

ghostty-screenshot-cmd:
	@-rm ~/.cache/nvim/flemma.log
	@nvim																				\
		--cmd "set runtimepath^=`pwd`,`pwd`/.vapor/dracula-vim"							\
		-c ":colorscheme dracula"														\
		-c "lua require(\"flemma\").setup({												\
			ruler = {																	\
				hl = \"Comment-fg:#101010\",											\
			},																			\
			highlights = {																\
				system = \"Normal\",													\
				user_lua_expression = \"Added\",										\
				user_file_reference = \"Added\",										\
				thinking_block = \"Comment+bg:#102020-fg:#111111\",						\
			},																			\
			line_highlights = {															\
				frontmatter = \"Normal+bg:#100310\",									\
				system = \"Normal+bg:#100300\",											\
				user = \"Normal\",														\
				assistant = \"Normal+bg:#031010\",										\
			},																			\
		})"																				\
		-c ":tabedit example.chat"														\
		-c ':set nornu nospell nocursorline' -c ':set showtabline=0' -c ':set cmdheight=0' -c ':set guicursor=n-v-c-sm:ver25' -c ':normal! ggzaza'


# vim: set ts=4 sts=4 sw=4 et:
