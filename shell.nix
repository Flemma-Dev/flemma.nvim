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
    google-cloud-sdk
    imagemagick
    libsecret
    nodejs_lts.pkgs.pnpm
    vhs
    # Neovim plug-ins
    plenary-nvim
    # Lua tools
    lua-language-server
    lua54Packages.luacheck

    (writeShellApplication {
      name = "flemma-fmt";
      runtimeInputs = [
        nixfmt-tree
        nodejs_lts.pkgs.prettier
        stylua
      ];
      text = ''
        treefmt

        find . -name "*.lua" -print0 | xargs -0 \
        stylua

        find . -name "*.md" -not -path '*/.claude/*' -print0 | xargs -0 \
        prettier --write
      '';
    })

    (writeShellApplication {
      name = "flemma-amp";
      text = "exec pnpm --silent --package=@sourcegraph/amp@latest dlx -- amp \"$@\"";
    })

    (writeShellApplication {
      name = "flemma-claude";
      text = "exec pnpm --silent --package=@anthropic-ai/claude-code@latest dlx -- claude \"$@\"";
    })

    (writeShellApplication {
      name = "flemma-codex";
      text = "exec pnpm --silent --package=@openai/codex dlx -- codex \"$@\"";
    })
  ];
}
