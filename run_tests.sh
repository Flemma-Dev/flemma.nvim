#!/bin/sh
set -e

# Ensure PROJECT_ROOT and PLENARY_PATH are set, if not, exit.
if [ -z "$PROJECT_ROOT" ] || [ -z "$PLENARY_PATH" ]; then
  echo "Error: PROJECT_ROOT and PLENARY_PATH must be set."
  echo "Please run this script from within the 'nix develop' shell."
  exit 1
fi

# Run tests in a clean Neovim instance
nvim --headless --noplugin -u tests/minimal_init.vim \
  -c "lua require('plenary.busted').run('tests/')"
