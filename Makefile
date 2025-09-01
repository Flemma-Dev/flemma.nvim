.PHONY: test
test:
	nvim --headless --noplugin -u tests/minimal.vim -c "PlenaryBustedDirectory tests/plenary/ {minimal_init = 'tests/minimal_init.lua'}"
