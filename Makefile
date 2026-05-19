.PHONY: default format qa develop screencast types

SHELL := $(shell which bash)
override PROJECT_ROOT := $(CURDIR)

default:
	@echo "Usage: make [$(shell cat ${MAKEFILE_LIST} | grep -E '^[a-zA-Z_-]+:' | sed 's/:.*//g' | grep -v '^default' | tr '\n' '|' | sed 's/|$$//')]"
	@cat ${MAKEFILE_LIST} | grep -B1 -E '^[a-zA-Z_-]+:' | sed 's/:.*//' | sed 's/^# *//' | tac | grep -v '^--' | sed 'N;s/\n/ - /' | grep -v '^default' | tac | sed 's/^/  /'

# Format the entire codebase
format:
	treefmt

# Run all quality gates — parallel, bail on first failure
qa:
	@if [ -z "$$NVIM_VERSIONS" ]; then \
		echo "qa: NVIM_VERSIONS is not set. Run from within the 'nix develop' shell."; exit 1; \
	fi; \
	d=$$(mktemp -d); trap 'rm -rf "$$d"' EXIT; \
	declare -A gate; \
	declare -A pgid; \
	luacheck lua/ tests/ \
		>"$$d/luacheck" 2>&1 & gate[$$!]=luacheck; \
	actionlint \
		>"$$d/actionlint" 2>&1 & gate[$$!]=actionlint; \
	VIMRUNTIME=$$(dirname $$(dirname $$(readlink -f $$(which nvim))))/share/nvim/runtime \
		lua-language-server --check lua/ --configpath ../.luarc-check.lua --checklevel=Warning --num_threads=4 \
		>"$$d/types" 2>&1 & gate[$$!]=types; \
	bash contrib/scripts/lint-inline-requires.sh \
		>"$$d/imports" 2>&1 & gate[$$!]=imports; \
	bash contrib/scripts/lint-no-vim-notify.sh \
		>"$$d/notify" 2>&1 & gate[$$!]=notify; \
	bash contrib/scripts/lint-pcall-rethrow.sh \
		>"$$d/pcall-rethrow" 2>&1 & gate[$$!]=pcall-rethrow; \
	for entry in $$NVIM_VERSIONS; do \
		IFS=: read -r label nvim_bin vimruntime plenary_path <<< "$$entry"; \
		setsid env PROJECT_ROOT=$(PROJECT_ROOT) PLENARY_PATH="$$plenary_path" VIMRUNTIME="$$vimruntime" \
			"$$nvim_bin" --headless --noplugin -u tests/minimal.vim \
			-c "PlenaryBustedDirectory tests/flemma/ {minimal_init = 'tests/minimal_init.lua'}" \
			>"$$d/test-$$label" 2>&1 & gate[$$!]="test-$$label"; pgid[$$!]=1; \
	done; \
	cleanup() { \
		for p in "$${!gate[@]}"; do \
			if [[ -n "$${pgid[$$p]}" ]]; then \
				kill -- -$$p 2>/dev/null; \
			else \
				kill $$p 2>/dev/null; \
			fi; \
		done; \
		for _ in $$(seq 1 60); do \
			alive=0; \
			for p in "$${!gate[@]}"; do \
				kill -0 $$p 2>/dev/null && alive=1 && break; \
			done; \
			(( alive )) || break; \
			sleep 0.05; \
		done; \
		for p in "$${!gate[@]}"; do \
			if [[ -n "$${pgid[$$p]}" ]]; then \
				kill -9 -- -$$p 2>/dev/null; \
			else \
				kill -9 $$p 2>/dev/null; \
			fi; \
		done; \
		wait 2>/dev/null; \
	}; \
	failed_tests=(); \
	while (( $${#gate[@]} )); do \
		pid=0; wait -n -p pid $${!gate[@]}; rc=$$?; \
		name=$${gate[$$pid]}; unset "gate[$$pid]"; unset "pgid[$$pid]"; \
		if (( rc )); then \
			if [[ "$$name" == test-* ]]; then \
				failed_tests+=("$$name"); \
			else \
				cleanup; \
				echo "qa: FAILED — $$name"; echo ""; \
				echo "--- $$name ---"; \
				cat "$$d/$$name"; \
				echo ""; exit 1; \
			fi; \
		fi; \
	done; \
	if (( $${#failed_tests[@]} )); then \
		echo "qa: FAILED — $${failed_tests[*]}"; echo ""; \
		for name in "$${failed_tests[@]}"; do \
			echo "--- $$name ---"; \
			grep -v '^Scheduling' "$$d/$$name" \
				| grep -v '^Starting\.\.\.'; \
			echo ""; \
		done; \
		exit 1; \
	fi; \
	sed 's/\x1b\[[0-9;]*m//g' "$$d/types" \
		| grep -Ev '^\s*$$|^Starting|Diagnosis completed' \
		> "$$d/types-filtered"; \
	if [ -s "$$d/types-filtered" ]; then \
		echo "qa: OK (with warnings)"; echo ""; \
		echo "--- types (warnings) ---"; \
		cat "$$d/types-filtered"; \
	else echo "qa: OK"; fi

# Generate EmmyLua config types from the schema DSL
types:
	nvim --headless --noplugin -u NONE --cmd 'set rtp^=.' -l contrib/scripts/generate-config-types.lua

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
				[\"\$$gpt\"] = \"openai gpt-5.4-mini\",									\
				[\"\$$haiku\"] = \"anthropic claude-haiku-4-5\",						\
				[\"\$$kimi\"] = \"moonshot kimi-k2.6\",									\
			},																			\
			diagnostics = { enabled = true },											\
			logging = { enabled = true, level = \"TRACE\" },							\
			editing = { auto_write = true },											\
			tools = {																	\
				modules = { \"extras.flemma.tools.calculator\" },						\
				mcporter = { enabled = true },											\
			},																			\
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
	@rm -Rf \
		.vapor/cache/ .vapor/state/ .vapor/release.chat \
		.vapor/poster.jpg .vapor/poster.mp4 .vapor/concat_list.txt \
		.vapor/flemma_cast_with_poster.mp4 assets/flemma_cast.mp4
	@mkdir -p .vapor/ .vapor/cache/ .vapor/state/
	@contrib/vhs/setup-aurora.sh
	@export PS1='$$ ' ;\
	 export XDG_CONFIG_HOME=`pwd`/contrib/vhs ;\
	 export XDG_DATA_HOME=`pwd`/.vapor ;\
	 export XDG_CACHE_HOME=`pwd`/.vapor/cache ;\
	 export XDG_STATE_HOME=`pwd`/.vapor/state ;\
	 nvim --headless +"TSInstallSync markdown markdown_inline lua json" +qa && \
	 vhs contrib/vhs/flemma_cast.tape
	@contrib/scripts/screencast-poster.sh assets/flemma_cast.mp4

.vapor/catppuccin/nvim.git .vapor/NStefan002/screenkey.nvim.git:
	@mkdir -p $(dir $@)
	git clone --depth 1 https://github.com/$(patsubst .vapor/%.git,%,$@) $@


# vim: set ts=4 sts=4 sw=4 noet:
