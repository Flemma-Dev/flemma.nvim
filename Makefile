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

# Run lua-language-server on the Lua files
check:
	@# Set the VIMRUNTIME environment variable to point to the Neovim runtime directory
	@# We do this by resolving the path to the `nvim` binary and navigating up from "[..]/bin" to the runtime directory "[..]/share/nvim/runtime".
	@# On NixOS, `nvim` might be symlinked to a store path, so we use `readlink -f` to get the actual path.
	VIMRUNTIME=$(shell dirname $(shell dirname $(shell readlink -f $(shell which nvim))))/share/nvim/runtime \
		lua-language-server --check lua/

# Update models and pricing using Amp (AI agent)
.PHONY: update-models
update-models:
	cat contrib/amp/prompt-update-models-and-pricing.txt | sed 's@{{date}}@'"$(shell date +%Y-%m-%d)"'@g' | flemma-amp

# Launch Flemma.nvim from local directory
.PHONY: develop
develop:
	@-rm ~/.cache/nvim/flemma.log
	@nvim --cmd "set runtimepath+=`pwd`"												\
		-c "lua require(\"flemma\").setup({												\
			provider = \"anthropic\",													\
			model = \"claude-haiku-4-5\",												\
			presets = { [\"\$$gpt\"] = \"openai gpt-5.2 reasoning=low\" },				\
			logging = { enabled = true },												\
			editing = { auto_write = true },											\
			pricing = { enabled = true },												\
			signs = {																	\
				enabled = true,															\
				assistant = { hl = \"#8f9fdf\" },										\
				user = { hl = \"#6f6f6f\" }												\
			},																			\
			highlights = {																\
				assistant = \"#8f9faf\",												\
				user_lua_expression = \"#ff00ff\",										\
				user_file_reference = \"#ff00ff\",										\
				thinking_tag = { fg = \"#6f7f8f\", bold = true, underline = true },		\
				thinking_block = { fg = \"#6f7f8f\" }									\
			},																			\
		})"																				\
		-c ":edit $$HOME/.cache/nvim/flemma.log"										\
		-c ":tabedit example.chat"


# vim: set ts=4 sts=4 sw=4 et:
