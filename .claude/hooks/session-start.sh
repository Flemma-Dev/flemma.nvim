#!/bin/bash
set -euo pipefail

# Only run in Claude Code on the web
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# ------------------------------------------------------------------
# Flemma.nvim bootstrap — installs everything needed for:
#   make test   (Neovim + plenary.nvim)
#   make lint   (luacheck + Lua 5.4 + luarocks)
#   make check  (lua-language-server + Neovim runtime stubs)
#
# Idempotent: skips steps whose artefacts already exist.
# ------------------------------------------------------------------

LUA_LS_DIR="/opt/lua-language-server"
PLENARY_DIR="/opt/plenary.nvim"

# ---- Neovim >= 0.11 (prebuilt) -----------------------------------
if ! command -v nvim &>/dev/null; then
  NVIM_VER=$(curl -sI https://github.com/neovim/neovim/releases/latest | grep -i '^location:' | grep -oP 'v\K[0-9.]+')
  curl -sL "https://github.com/neovim/neovim/releases/download/v${NVIM_VER}/nvim-linux-x86_64.tar.gz" | tar xz -C /tmp
  sudo cp -r /tmp/nvim-linux-x86_64/* /usr/local/
  rm -rf /tmp/nvim-linux-x86_64
fi

# ---- Lua 5.4 (compiled from source — luacheck host) --------------
if ! command -v lua &>/dev/null; then
  LUA_VER="5.4.7"
  curl -sL "https://www.lua.org/ftp/lua-${LUA_VER}.tar.gz" | tar xz -C /tmp
  make -C "/tmp/lua-${LUA_VER}" linux -j"$(nproc)" >/dev/null 2>&1
  sudo make -C "/tmp/lua-${LUA_VER}" install >/dev/null 2>&1
  rm -rf "/tmp/lua-${LUA_VER}"
fi

# ---- luarocks (compiled from source) -----------------------------
if ! command -v luarocks &>/dev/null; then
  ROCKS_VER="3.11.1"
  curl -sL "https://luarocks.org/releases/luarocks-${ROCKS_VER}.tar.gz" | tar xz -C /tmp
  (cd "/tmp/luarocks-${ROCKS_VER}" && ./configure --with-lua=/usr/local >/dev/null 2>&1 && make >/dev/null 2>&1 && sudo make install >/dev/null 2>&1)
  rm -rf "/tmp/luarocks-${ROCKS_VER}"
fi

# ---- luacheck (manual install — luarocks mirrors are unreliable) -
if ! command -v luacheck &>/dev/null; then
  # argparse (pure Lua, single file)
  if [ ! -f /usr/local/share/lua/5.4/argparse.lua ]; then
    git clone --depth 1 -q https://github.com/mpeterv/argparse.git /tmp/argparse
    sudo cp /tmp/argparse/src/argparse.lua /usr/local/share/lua/5.4/
    rm -rf /tmp/argparse
  fi

  # luafilesystem (C module)
  if [ ! -f /usr/local/lib/lua/5.4/lfs.so ]; then
    git clone --depth 1 -q https://github.com/lunarmodules/luafilesystem.git /tmp/luafilesystem
    make -C /tmp/luafilesystem LUA_VERSION=5.4 LUA_INC=/usr/local/include >/dev/null 2>&1
    sudo cp /tmp/luafilesystem/src/lfs.so /usr/local/lib/lua/5.4/
    rm -rf /tmp/luafilesystem
  fi

  # luacheck itself (pure Lua)
  git clone --depth 1 -q https://github.com/lunarmodules/luacheck.git /tmp/luacheck
  sudo cp -r /tmp/luacheck/src/luacheck /usr/local/share/lua/5.4/
  sudo install -m 0755 /tmp/luacheck/bin/luacheck.lua /usr/local/bin/luacheck
  rm -rf /tmp/luacheck
fi

# ---- lua-language-server (prebuilt) -------------------------------
if ! command -v lua-language-server &>/dev/null; then
  LUA_LS_VER=$(curl -sI https://github.com/LuaLS/lua-language-server/releases/latest | grep -i '^location:' | grep -oP '/(\d+\.\d+\.\d+)' | tr -d '/')
  sudo mkdir -p "$LUA_LS_DIR"
  curl -sL "https://github.com/LuaLS/lua-language-server/releases/download/${LUA_LS_VER}/lua-language-server-${LUA_LS_VER}-linux-x64.tar.gz" | sudo tar xz -C "$LUA_LS_DIR"
  sudo ln -sf "$LUA_LS_DIR/bin/lua-language-server" /usr/local/bin/lua-language-server

  # .luarc-check.lua expects 3rd-party stubs at <root>/share/lua-language-server/meta/3rd
  # but the tarball puts them at <root>/meta/3rd — bridge with a symlink
  sudo mkdir -p "$LUA_LS_DIR/share/lua-language-server/meta"
  sudo ln -sf "$LUA_LS_DIR/meta/3rd" "$LUA_LS_DIR/share/lua-language-server/meta/3rd"
fi

# ---- plenary.nvim (test framework dependency) --------------------
if [ ! -d "$PLENARY_DIR" ]; then
  sudo git clone --depth 1 -q https://github.com/nvim-lua/plenary.nvim.git "$PLENARY_DIR"
fi

# ---- Environment variables (persisted for the session) -----------
grep -q '^export PROJECT_ROOT=' "$CLAUDE_ENV_FILE" 2>/dev/null || echo "export PROJECT_ROOT=\"${CLAUDE_PROJECT_DIR}\"" >>"$CLAUDE_ENV_FILE"
grep -q '^export PLENARY_PATH=' "$CLAUDE_ENV_FILE" 2>/dev/null || echo "export PLENARY_PATH=\"${PLENARY_DIR}\"" >>"$CLAUDE_ENV_FILE"
