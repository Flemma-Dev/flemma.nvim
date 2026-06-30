{
  pkgs-stable ? import <nixpkgs> { },
  pkgs-unstable ? pkgs-stable,
}:
let
  nvim-stable = pkgs-stable.neovim;
  nvim-unstable = pkgs-unstable.neovim;
  plenary-nvim = pkgs-stable.vimPlugins.plenary-nvim;
  nodejs-stable = pkgs-stable.nodejs_24;
  mcporter = (
    pkgs-stable.writeShellScriptBin "mcporter" ''
      exec ${pkgs-stable.lib.getExe pkgs-stable.envchain} mcp_keys pnpm --silent --package=mcporter@latest dlx -- mcporter "$@"
    ''
  );
in
pkgs-stable.mkShell {
  name = "flemma-dev-shell";

  shellHook = ''
    PROJECT_ROOT=$(pwd)
    export PROJECT_ROOT

    PLENARY_PATH=${plenary-nvim}
    export PLENARY_PATH

    NVIM_VERSIONS="neovim-${nvim-stable.version}:${nvim-stable}/bin/nvim:${nvim-stable}/share/nvim/runtime:${plenary-nvim} neovim-${nvim-unstable.version}:${nvim-unstable}/bin/nvim:${nvim-unstable}/share/nvim/runtime:${plenary-nvim}"
    export NVIM_VERSIONS
  '';

  buildInputs = with pkgs-unstable; [
    actionlint
    bubblewrap
    gh
    google-cloud-sdk
    libsecret
    links2
    mcporter
    nodejs-stable.pkgs.pnpm
    socat
    tree-sitter
    vhs
    # Neovim plug-ins
    plenary-nvim
    # Lua tools
    lua-language-server
    lua54Packages.luacheck
    # Formatters
    nixfmt
    nodejs-stable.pkgs.prettier
    shfmt
    stylua
    taplo
    treefmt
    yamlfmt
  ];
}
