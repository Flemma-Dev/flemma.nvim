{
  pkgs ? import <nixpkgs> { },
}:
let
  nodejs_lts = pkgs.nodejs_24;
  plenary-nvim = pkgs.vimPlugins.plenary-nvim;
in
pkgs.mkShell rec {
  name = "flemma-dev-shell";

  shellHook = ''
    PROJECT_ROOT=$(pwd)
    export PROJECT_ROOT

    PLENARY_PATH=${plenary-nvim}
    export PLENARY_PATH
  '';

  buildInputs = with pkgs; [
    actionlint
    bubblewrap
    gh
    google-cloud-sdk
    libsecret
    links2
    nodejs_lts.pkgs.pnpm
    socat
    vhs
    # Neovim plug-ins
    plenary-nvim
    # Lua tools
    lua-language-server
    lua54Packages.luacheck

    (writeShellScriptBin "mcporter" ''
      exec ${lib.getExe envchain} mcp_keys pnpm --silent --package=mcporter@latest dlx -- mcporter "$@"
    '')

    nixfmt-rfc-style
    nodejs_lts.pkgs.prettier
    shfmt
    stylua
    taplo
    treefmt
    yamlfmt
  ];
}
