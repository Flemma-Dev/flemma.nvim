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

.PHONY: develop
# Launch Flemma.nvim from local directory
develop:
	@-rm ~/.cache/nvim/flemma.log
	@nvim --cmd "set runtimepath^=`pwd`"												\
		-c "																			\
		lua require(\"flemma\").setup({													\
			model = \"\$$haiku\",														\
			parameters = { thinking = \"minimal\" },									\
			presets = {																	\
				[\"\$$haiku\"] = \"anthropic claude-haiku-4-5\",						\
				[\"\$$gpt\"] = \"openai gpt-5.2\",										\
			},																			\
			logging = { enabled = true },												\
			editing = { auto_write = true },											\
			tools = { modules = { \"extras.flemma.tools.calculator\" } },				\
		})																				\
																						\
		dofile(\"$(CURDIR)/contrib/extras/sink_viewer.lua\").setup({					\
			pattern = {																	\
				\"^anthropic/thinking\",												\
				\"^openai/reasoning\",													\
				\"^vertex/thinking\",													\
			}																			\
		})																				\
		"																				\
		-c ":edit $$HOME/.cache/nvim/flemma.log"										\
		-c ":tabedit example.chat"

.PHONY: screencast
# Create a VHS screencast demonstrating Flemma's capabilities, with a poster frame prepended
screencast: .vapor/catppuccin/nvim.git .vapor/NStefan002/screenkey.nvim.git
	@-rm -R \
		.vapor/cache/ .vapor/state/ .vapor/scratch.chat .vapor/math.png \
		.vapor/poster.jpg .vapor/poster.mp4 .vapor/concat_list.txt \
		.vapor/flemma_cast_with_poster.mp4 assets/flemma_cast.mp4
	@mkdir -p .vapor/cache/ .vapor/state/
	@echo -e "\`\`\`lua\nname = \"Flemma\"\n\nflemma.opt.thinking = \"medium\"\nflemma.opt.tools.auto_approve = { \"bash\" }\n\`\`\`\n@System: When deleting files use \`trash\` && \`sleep 2\`, never \`rm\`.\n" > .vapor/scratch.chat
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
		XDG_DATA_HOME=`pwd`/.vapor \
		XDG_CONFIG_HOME=`pwd`/contrib/vhs \
		XDG_CACHE_HOME=`pwd`/.vapor/cache \
		XDG_STATE_HOME=`pwd`/.vapor/state \
	vhs contrib/vhs/flemma_cast.tape
	ffmpeg -hide_banner -y \
		-ss 00:00:13 \
		-i assets/flemma_cast.mp4 \
		-vframes 1 -q:v 2 \
		.vapor/poster.jpg
	ffmpeg -hide_banner -y \
		-loop 1 \
		-i .vapor/poster.jpg \
		-vframes 1 -r 25 \
		-c:v libx264 -pix_fmt yuv420p \
		.vapor/poster.mp4
	printf 'file $(CURDIR)/.vapor/poster.mp4\nfile $(CURDIR)/assets/flemma_cast.mp4\n' \
		> .vapor/concat_list.txt
	ffmpeg -hide_banner -y \
		-f concat -safe 0 \
		-i .vapor/concat_list.txt \
		-c copy \
		.vapor/flemma_cast_with_poster.mp4
	mv .vapor/flemma_cast_with_poster.mp4 assets/flemma_cast.mp4

.vapor/catppuccin/nvim.git .vapor/NStefan002/screenkey.nvim.git:
	@mkdir -p $(dir $@)
	git clone --depth 1 https://github.com/$(patsubst .vapor/%.git,%,$@) $@


# vim: set ts=4 sts=4 sw=4 noet:
