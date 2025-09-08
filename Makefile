.PHONY: test
test:
	nvim --headless --noplugin -u tests/minimal.vim -c "PlenaryBustedDirectory tests/flemma/ {minimal_init = 'tests/minimal_init.lua'}"
