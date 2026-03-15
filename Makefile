.PHONY: default changeset qa develop screencast

SHELL := $(shell which bash)
VIMRUNTIME_PATH = $(shell dirname $(shell dirname $(shell readlink -f $(shell which nvim))))/share/nvim/runtime

default:
	@echo "Usage: make [$(shell cat ${MAKEFILE_LIST} | grep -E '^[a-zA-Z_-]+:' | sed 's/:.*//g' | grep -v '^default' | tr '\n' '|' | sed 's/|$$//')]"
	@cat ${MAKEFILE_LIST} | grep -B1 -E '^[a-zA-Z_-]+:' | sed 's/:.*//' | sed 's/^# *//' | tac | grep -v '^--' | sed 'N;s/\n/ - /' | grep -v '^default' | tac | sed 's/^/  /'

# Create a new changeset
changeset:
	pnpm changeset

# Run all quality gates — parallel, bail on first failure
qa:
	@d=$$(mktemp -d); trap 'rm -rf "$$d"' EXIT; \
	declare -A gate; \
	luacheck lua/ tests/ \
		>"$$d/luacheck" 2>&1 & gate[$$!]=luacheck; \
	VIMRUNTIME=$(VIMRUNTIME_PATH) \
		lua-language-server --check lua/ --configpath ../.luarc-check.lua \
		>"$$d/types" 2>&1 & gate[$$!]=types; \
	bash scripts/lint-inline-requires.sh \
		>"$$d/imports" 2>&1 & gate[$$!]=imports; \
	nvim --headless --noplugin -u tests/minimal.vim \
		-c "PlenaryBustedDirectory tests/flemma/ {minimal_init = 'tests/minimal_init.lua'}" \
		>"$$d/test" 2>&1 & gate[$$!]=test; \
	while (( $${#gate[@]} )); do \
		pid=0; wait -n -p pid $${!gate[@]}; rc=$$?; \
		name=$${gate[$$pid]}; unset "gate[$$pid]"; \
		if (( rc )); then \
			kill $${!gate[@]} 2>/dev/null; wait 2>/dev/null; \
			echo "qa: FAILED — $$name"; echo ""; \
			echo "--- $$name ---"; \
			if [ "$$name" = test ]; then \
				grep -vE '^.....(Success|Failed|Errors)' "$$d/$$name" \
					| grep -v '^Scheduling' \
					| grep -v '^Flemma: Switched to' \
					| grep -v '^===='; \
			else cat "$$d/$$name"; fi; \
			echo ""; exit 1; \
		fi; \
	done; \
	echo "qa: OK"

# Launch Flemma.nvim from local directory
develop:
	@-rm ~/.cache/nvim/flemma.log
	@nvim --cmd "lua																	\
			local cwd = vim.uv.cwd();													\
			vim.opt.rtp:prepend(cwd);													\
			package.loaded['lualine.components.flemma'] = setmetatable({}, {			\
				__call = function(_, ...)												\
					local m = dofile(cwd .. '/lua/lualine/components/flemma.lua');		\
					package.loaded['lualine.components.flemma'] = m;					\
					return m(...)														\
				end,																	\
			})																			\
		"																				\
		-c "lua																			\
		require(\"flemma\").setup({														\
			model = \"\$$haiku\",														\
			parameters = { thinking = \"minimal\" },									\
			presets = {																	\
				[\"\$$haiku\"] = \"anthropic claude-haiku-4-5\",						\
				[\"\$$gpt\"] = \"openai gpt-5.4\",										\
			},																			\
			diagnostics = { enabled = true },											\
			logging = { enabled = true, level = \"TRACE\" },							\
			editing = { auto_write = true },											\
			tools = { modules = { \"extras.flemma.tools.calculator\" } },				\
			experimental = { tools = true },											\
		})																				\
		pcall(function()																\
			require(\"bufferline.config\").options.get_element_icon =					\
				require(\"flemma.integrations.bufferline\").get_element_icon			\
		end)																			\
		"																				\
		-c ":edit $$HOME/.cache/nvim/flemma.log"										\
		-c ":tabedit example.chat"

.PHONY: screencast
# Create a VHS screencast demonstrating Flemma's capabilities, with a poster frame prepended
screencast: .vapor/catppuccin/nvim.git .vapor/NStefan002/screenkey.nvim.git
	@-rm -R \
		.vapor/cache/ .vapor/state/ .vapor/scratch.chat .vapor/templates/example .vapor/math.png \
		.vapor/poster.jpg .vapor/poster.mp4 .vapor/concat_list.txt \
		.vapor/flemma_cast_with_poster.mp4 assets/flemma_cast.mp4
	@mkdir -p .vapor/cache/ .vapor/state/ .vapor/templates/
	@echo -en "* Delete files via \`trash\` avoid \`rm\`\n* PC memory can be checked via \`free -h\`\n* When passing OCR content to tools use the exact syntax from the image without modifications\n* Never break down calculations to the user, only display the calculator result" > .vapor/templates/example
	@echo -en "\`\`\`lua\nname = \"Flemma Jr.\"\n\nflemma.opt.thinking = \"medium\"\n\`\`\`\n@System:\n{{ include('templates/example') }}\n\n" > .vapor/scratch.chat
	magick \
		-size 1500x200 \
		xc:white \
		-font DejaVu-Sans \
		-pointsize 48 \
		-fill black \
		-gravity center \
		-annotate +0+0 '1000000 - (456 * 789 - (456 * 789 %% 123)) / 123 + 4567' \
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
		-ss 00:00:17 \
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
