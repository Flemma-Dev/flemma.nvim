#!/usr/bin/env bash
set -euo pipefail

# Change to the script's directory to ensure paths are correct
cd "$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Set PROJECT_ROOT to the current directory if it's not already set, and export it.
export PROJECT_ROOT=${PROJECT_ROOT:-$(pwd)}

# Ensure PLENARY_PATH is set and not empty.
if [ -z "${PLENARY_PATH:-}" ]; then
  echo "Error: PLENARY_PATH must be set."
  echo "Please run this script from within the 'nix develop' shell."
  exit 1
fi

# Run tests in a clean Neovim instance
nvim --headless \
  -c "PlenaryBustedDirectory 'tests/' { minimal_init = 'tests/minimal_init.vim' }"
