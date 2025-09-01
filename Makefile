.PHONY: test
test:
	nvim --headless --noplugin -u tests/minimal_runner.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
