.PHONY: default changeset test lint check

default:
	@echo "Usage: make [$(shell cat ${MAKEFILE_LIST} | grep -E '^[a-zA-Z_-]+:' | sed 's/:.*//g' | grep -v '^default' | tr '\n' '|' | sed 's/|$$//')]"
	@cat ${MAKEFILE_LIST} | grep -B1 -E '^[a-zA-Z_-]+:' | sed 's/:.*//' | sed 's/^# *//' | tac | grep -v '^--' | sed 'N;s/\n/ - /' | grep -v '^default' | tac | sed 's/^/  /'

# Create a new changeset
changeset:
	pnpm changeset

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

.PHONY: update-models
# Update models and pricing using Amp (AI agent)
update-models:
	cat contrib/amp/prompt-update-models-and-pricing.txt | sed 's@{{date}}@'"$(shell date +%Y-%m-%d)"'@g' | flemma-amp

.PHONY: develop
# Launch Flemma.nvim from local directory
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

.PHONY: screencast
# Create a VHS screencast demonstrating Flemma's capabilities
screencast: .vapor/dracula-vim
	@-rm -R .vapor/cache/ .vapor/state/ .vapor/scratch.chat .vapor/math.png assets/flemma_cast.mp4
	@mkdir -p .vapor/cache/ .vapor/state/
	@echo -e "\`\`\`lua\nname = \"Flemma\"\n\nflemma.opt.anthropic.thinking_budget = 2000\n\nflemma.opt.tools = { \"bash\", \"calculator_async\" }\n\`\`\`\n@System: If asked by the user to do calculations, never do those yourself. Use tools that are available to you, such as a calculator or a code execution environment. To preserve resources, add a 1s delay to each computation.\n\n" > .vapor/scratch.chat
	magick \
		-size 400x200 \
		xc:white \
		-font DejaVu-Sans \
		-pointsize 48 \
		-fill black \
		-gravity center \
		-annotate +0+0 '(20+30)/2' \
		-bordercolor white \
		-border 20 \
		.vapor/math.png
	env \
		PS1='$$ ' \
		XDG_CONFIG_HOME=`pwd`/contrib/vhs \
		XDG_CACHE_HOME=`pwd`/.vapor/cache \
		XDG_STATE_HOME=`pwd`/.vapor/state \
	vhs contrib/vhs/flemma_cast.tape

.vapor/dracula-vim:
	@mkdir -p .vapor
	git clone --depth 1 https://github.com/dracula/vim.git .vapor/dracula-vim


# vim: set ts=4 sts=4 sw=4 noet:
